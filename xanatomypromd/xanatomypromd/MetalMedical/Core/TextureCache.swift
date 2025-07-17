import Metal
import Foundation

// MARK: - Texture Cache for Medical Imaging
// Efficient memory management for 500+ slice CT datasets
// Optimized for real-time slice navigation and windowing

public class TextureCache {
    
    // MARK: - Configuration
    
    public struct CacheConfig {
        let maxCachedTextures: Int
        let preloadRadius: Int  // Number of slices to preload around current position
        let enableBackgroundLoading: Bool
        
        public init(
            maxCachedTextures: Int = 20,
            preloadRadius: Int = 3,
            enableBackgroundLoading: Bool = true
        ) {
            self.maxCachedTextures = maxCachedTextures
            self.preloadRadius = preloadRadius
            self.enableBackgroundLoading = enableBackgroundLoading
        }
    }
    
    // MARK: - Cache Entry
    
    private struct CacheEntry {
        let texture: MTLTexture
        let windowedTexture: MTLTexture?
        let lastAccessed: Date
        let windowConfig: String  // Cache key for windowing parameters
        
        init(texture: MTLTexture, windowedTexture: MTLTexture? = nil, windowConfig: String = "") {
            self.texture = texture
            self.windowedTexture = windowedTexture
            self.lastAccessed = Date()
            self.windowConfig = windowConfig
        }
    }
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let config: CacheConfig
    private var rawTextureCache: [Int: CacheEntry] = [:]
    private var windowedTextureCache: [String: CacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "com.xanatomy.texture-cache", qos: .userInitiated)
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Statistics
    
    public struct CacheStats {
        let totalTextures: Int
        let memoryUsage: Int64  // Bytes
        let hitRate: Double
        let missCount: Int
        let hitCount: Int
    }
    
    private var hitCount = 0
    private var missCount = 0
    
    // MARK: - Initialization
    
    public init(device: MTLDevice, config: CacheConfig = CacheConfig()) {
        self.device = device
        self.config = config
        
        setupMemoryPressureMonitoring()
        print("✅ TextureCache initialized")
        print("   💾 Max cached textures: \(config.maxCachedTextures)")
        print("   🔄 Preload radius: \(config.preloadRadius)")
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    // MARK: - Primary Cache Interface
    
    /// Get texture for slice index, creating if needed
    public func getTexture(
        for sliceIndex: Int,
        pixelData: PixelData,
        metalRenderer: MetalRenderer,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        cacheQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Check cache first
            if let entry = self.rawTextureCache[sliceIndex] {
                self.hitCount += 1
                self.rawTextureCache[sliceIndex] = CacheEntry(
                    texture: entry.texture,
                    windowedTexture: entry.windowedTexture,
                    windowConfig: entry.windowConfig
                )
                
                DispatchQueue.main.async {
                    completion(entry.texture)
                }
                return
            }
            
            // Cache miss - create texture
            self.missCount += 1
            
            do {
                let texture = try metalRenderer.createTexture(from: pixelData)
                
                // Add to cache
                self.addToCache(texture: texture, sliceIndex: sliceIndex)
                
                DispatchQueue.main.async {
                    completion(texture)
                }
                
                // Trigger preloading if enabled
                if self.config.enableBackgroundLoading {
                    self.preloadAdjacentSlices(around: sliceIndex)
                }
                
            } catch {
                print("❌ Failed to create texture for slice \(sliceIndex): \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    /// Get windowed texture with specific window/level settings
    public func getWindowedTexture(
        for sliceIndex: Int,
        windowCenter: Float,
        windowWidth: Float,
        metalRenderer: MetalRenderer,
        baseTexture: MTLTexture,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        let cacheKey = "\(sliceIndex)_\(windowCenter)_\(windowWidth)"
        
        cacheQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Check windowed cache
            if let entry = self.windowedTextureCache[cacheKey] {
                self.hitCount += 1
                
                DispatchQueue.main.async {
                    completion(entry.windowedTexture ?? entry.texture)
                }
                return
            }
            
            // Create windowed texture
            let config = MetalRenderer.RenderConfig(
                windowCenter: windowCenter,
                windowWidth: windowWidth
            )
            
            metalRenderer.renderCTImage(
                inputTexture: baseTexture,
                config: config
            ) { [weak self] windowedTexture in
                guard let self = self, let windowedTexture = windowedTexture else {
                    completion(nil)
                    return
                }
                
                // Cache the windowed result - back on cache queue
                self.cacheQueue.async {
                    // Double-check self is still valid
                    guard self.windowedTextureCache.keys.contains(cacheKey) == false else {
                        // Already cached by another thread
                        completion(windowedTexture)
                        return
                    }
                    
                    let entry = CacheEntry(
                        texture: baseTexture,
                        windowedTexture: windowedTexture,
                        windowConfig: cacheKey
                    )
                    self.windowedTextureCache[cacheKey] = entry
                    self.enforceWindowedCacheLimit()
                    
                    completion(windowedTexture)
                }
            }
        }
    }
    
    // MARK: - Preloading
    
    /// Preload textures around current slice for smooth navigation
    public func preloadSlices(
        around currentIndex: Int,
        totalSlices: Int,
        pixelDataProvider: @escaping (Int) -> PixelData?,
        metalRenderer: MetalRenderer
    ) {
        guard config.enableBackgroundLoading else { return }
        
        let startIndex = max(0, currentIndex - config.preloadRadius)
        let endIndex = min(totalSlices - 1, currentIndex + config.preloadRadius)
        
        for index in startIndex...endIndex {
            // Skip if already cached
            if rawTextureCache[index] != nil { continue }
            
            guard let pixelData = pixelDataProvider(index) else { continue }
            
            cacheQueue.async { [weak self] in
                guard let self = self else { return }
                
                do {
                    let texture = try metalRenderer.createTexture(from: pixelData)
                    self.addToCache(texture: texture, sliceIndex: index)
                } catch {
                    print("⚠️  Preload failed for slice \(index): \(error)")
                }
            }
        }
    }
    
    private func preloadAdjacentSlices(around currentIndex: Int) {
        // This would be called with actual pixel data in the full implementation
        // For now, it's a placeholder for the preloading logic
        print("🔄 Triggering preload around slice \(currentIndex)")
    }
    
    // MARK: - Cache Management
    
    private func addToCache(texture: MTLTexture, sliceIndex: Int) {
        let entry = CacheEntry(texture: texture)
        rawTextureCache[sliceIndex] = entry
        
        // Enforce cache size limit
        if rawTextureCache.count > config.maxCachedTextures {
            evictOldestTextures()
        }
    }
    
    private func evictOldestTextures() {
        let sortedEntries = rawTextureCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        let entriesToRemove = sortedEntries.prefix(rawTextureCache.count - config.maxCachedTextures)
        
        for (sliceIndex, _) in entriesToRemove {
            rawTextureCache.removeValue(forKey: sliceIndex)
        }
        
        print("🗑️  Evicted \(entriesToRemove.count) textures from cache")
    }
    
    private func enforceWindowedCacheLimit() {
        // Ensure we're on the cache queue
        dispatchPrecondition(condition: .onQueue(cacheQueue))
        
        let maxWindowedTextures = config.maxCachedTextures / 2  // Use half limit for windowed cache
        
        guard windowedTextureCache.count > maxWindowedTextures else { return }
        
        let sortedEntries = windowedTextureCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        let entriesToRemove = sortedEntries.prefix(windowedTextureCache.count - maxWindowedTextures)
        
        for (cacheKey, _) in entriesToRemove {
            windowedTextureCache.removeValue(forKey: cacheKey)
        }
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: cacheQueue
        )
        
        memoryPressureSource?.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        
        memoryPressureSource?.resume()
    }
    
    private func handleMemoryPressure() {
        print("⚠️  Memory pressure detected - clearing texture caches")
        
        // Clear windowed cache first
        windowedTextureCache.removeAll()
        
        // Reduce raw texture cache to 25% of limit
        let targetSize = config.maxCachedTextures / 4
        if rawTextureCache.count > targetSize {
            let sortedEntries = rawTextureCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
            let entriesToRemove = sortedEntries.prefix(rawTextureCache.count - targetSize)
            
            for (sliceIndex, _) in entriesToRemove {
                rawTextureCache.removeValue(forKey: sliceIndex)
            }
        }
    }
    
    // MARK: - Cache Statistics
    
    public func getStats() -> CacheStats {
        return cacheQueue.sync {
            let totalTextures = rawTextureCache.count + windowedTextureCache.count
            let memoryUsage = calculateMemoryUsage()
            let totalRequests = hitCount + missCount
            let hitRate = totalRequests > 0 ? Double(hitCount) / Double(totalRequests) : 0.0
            
            return CacheStats(
                totalTextures: totalTextures,
                memoryUsage: memoryUsage,
                hitRate: hitRate,
                missCount: missCount,
                hitCount: hitCount
            )
        }
    }
    
    private func calculateMemoryUsage() -> Int64 {
        var totalBytes: Int64 = 0
        
        for (_, entry) in rawTextureCache {
            totalBytes += Int64(entry.texture.width * entry.texture.height * 2)  // 16-bit textures
            if let windowedTexture = entry.windowedTexture {
                totalBytes += Int64(windowedTexture.width * windowedTexture.height * 4)  // RGBA textures
            }
        }
        
        for (_, entry) in windowedTextureCache {
            if let windowedTexture = entry.windowedTexture {
                totalBytes += Int64(windowedTexture.width * windowedTexture.height * 4)
            }
        }
        
        return totalBytes
    }
    
    // MARK: - Cache Control
    
    /// Clear all cached textures
    public func clearCache() {
        cacheQueue.async { [weak self] in
            self?.rawTextureCache.removeAll()
            self?.windowedTextureCache.removeAll()
            self?.hitCount = 0
            self?.missCount = 0
            print("🗑️  Texture cache cleared")
        }
    }
    
    /// Warm up cache with specific slice range
    public func warmUpCache(
        sliceRange: Range<Int>,
        pixelDataProvider: @escaping (Int) -> PixelData?,
        metalRenderer: MetalRenderer,
        completion: @escaping () -> Void
    ) {
        cacheQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            for index in sliceRange {
                guard let pixelData = pixelDataProvider(index) else { continue }
                
                do {
                    let texture = try metalRenderer.createTexture(from: pixelData)
                    self.addToCache(texture: texture, sliceIndex: index)
                } catch {
                    print("⚠️  Cache warmup failed for slice \(index): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    /// Print detailed cache information for debugging
    public func printCacheInfo() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let stats = self.getStats()
            print("""
            
            📊 TEXTURE CACHE STATS:
               🗃️  Total textures: \(stats.totalTextures)
               💾 Memory usage: \(ByteCountFormatter().string(fromByteCount: stats.memoryUsage))
               🎯 Hit rate: \(String(format: "%.1f", stats.hitRate * 100))%
               ✅ Hits: \(stats.hitCount)
               ❌ Misses: \(stats.missCount)
               🔄 Raw cache size: \(self.rawTextureCache.count)
               🪟 Windowed cache size: \(self.windowedTextureCache.count)
            
            """)
        }
    }
}
