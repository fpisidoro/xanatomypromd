import Metal
import Foundation

// MARK: - Simple Texture Cache
// Thread-safe minimal cache that eliminates complex threading issues
// Focus on reliability over advanced features

public class SimpleTextureCache {
    
    // MARK: - Simple Cache Entry
    
    private struct CacheEntry {
        let texture: MTLTexture
        let createdAt: Date
        
        init(texture: MTLTexture) {
            self.texture = texture
            self.createdAt = Date()
        }
    }
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let maxCachedTextures: Int
    private var cache: [Int: CacheEntry] = [:]
    private let lock = NSLock()
    
    // MARK: - Statistics
    
    private var hitCount = 0
    private var missCount = 0
    
    // MARK: - Initialization
    
    public init(device: MTLDevice, maxCachedTextures: Int = 10) {
        self.device = device
        self.maxCachedTextures = maxCachedTextures
        
        print("✅ SimpleTextureCache initialized (max: \(maxCachedTextures))")
    }
    
    // MARK: - Main Cache Interface
    
    /// Get texture for slice index, creating if needed
    public func getTexture(
        for sliceIndex: Int,
        pixelDataProvider: @escaping () -> PixelData?,
        metalRenderer: MetalRenderer,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        // Check cache first (thread-safe)
        lock.lock()
        let cachedEntry = cache[sliceIndex]
        lock.unlock()
        
        if let entry = cachedEntry {
            hitCount += 1
            DispatchQueue.main.async {
                completion(entry.texture)
            }
            return
        }
        
        // Cache miss - create texture on background queue
        missCount += 1
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            guard let pixelData = pixelDataProvider() else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            do {
                let texture = try metalRenderer.createTexture(from: pixelData)
                
                // Add to cache (thread-safe)
                self.lock.lock()
                self.cache[sliceIndex] = CacheEntry(texture: texture)
                self.enforceLimit()
                self.lock.unlock()
                
                DispatchQueue.main.async {
                    completion(texture)
                }
                
            } catch {
                print("❌ Failed to create texture for slice \(sliceIndex): \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Direct Texture Access (Synchronous)
    
    /// Get texture synchronously if available in cache
    public func getCachedTexture(for sliceIndex: Int) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        
        if let entry = cache[sliceIndex] {
            hitCount += 1
            return entry.texture
        }
        
        return nil
    }
    
    /// Add texture to cache directly
    public func cacheTexture(_ texture: MTLTexture, for sliceIndex: Int) {
        lock.lock()
        cache[sliceIndex] = CacheEntry(texture: texture)
        enforceLimit()
        lock.unlock()
    }
    
    // MARK: - Cache Management
    
    private func enforceLimit() {
        // This method is called while lock is held
        guard cache.count > maxCachedTextures else { return }
        
        // Remove oldest entries
        let sortedEntries = cache.sorted { $0.value.createdAt < $1.value.createdAt }
        let entriesToRemove = sortedEntries.prefix(cache.count - maxCachedTextures)
        
        for (sliceIndex, _) in entriesToRemove {
            cache.removeValue(forKey: sliceIndex)
        }
        
        print("🗑️  Evicted \(entriesToRemove.count) textures from cache")
    }
    
    // MARK: - Cache Statistics
    
    public func getStats() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        let totalRequests = hitCount + missCount
        let hitRate = totalRequests > 0 ? Double(hitCount) / Double(totalRequests) : 0.0
        
        return """
        📊 Cache Stats:
           🗃️  Cached textures: \(cache.count)/\(maxCachedTextures)
           🎯 Hit rate: \(String(format: "%.1f", hitRate * 100))%
           ✅ Hits: \(hitCount)
           ❌ Misses: \(missCount)
        """
    }
    
    // MARK: - Cache Control
    
    /// Clear all cached textures
    public func clearCache() {
        lock.lock()
        cache.removeAll()
        hitCount = 0
        missCount = 0
        lock.unlock()
        
        print("🗑️  SimpleTextureCache cleared")
    }
    
    /// Get all cached slice indices
    public func getCachedSliceIndices() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(cache.keys).sorted()
    }
    
    /// Check if slice is cached
    public func isSliceCached(_ sliceIndex: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return cache[sliceIndex] != nil
    }
    
    /// Preload multiple slices
    public func preloadSlices(
        _ sliceIndices: [Int],
        pixelDataProvider: @escaping (Int) -> PixelData?,
        metalRenderer: MetalRenderer,
        completion: @escaping (Int) -> Void  // Called for each completed slice
    ) {
        for sliceIndex in sliceIndices {
            // Skip if already cached
            if isSliceCached(sliceIndex) {
                completion(sliceIndex)
                continue
            }
            
            getTexture(
                for: sliceIndex,
                pixelDataProvider: { pixelDataProvider(sliceIndex) },
                metalRenderer: metalRenderer
            ) { texture in
                if texture != nil {
                    completion(sliceIndex)
                }
            }
        }
    }
}

// MARK: - Usage Helper

extension SimpleTextureCache {
    
    /// Convenient method for immediate texture creation without caching
    public static func createTexture(
        from pixelData: PixelData,
        using metalRenderer: MetalRenderer,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let texture = try metalRenderer.createTexture(from: pixelData)
                DispatchQueue.main.async {
                    completion(texture)
                }
            } catch {
                print("❌ Failed to create texture: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}
