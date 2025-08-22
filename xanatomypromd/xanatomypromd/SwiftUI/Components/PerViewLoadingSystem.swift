// MARK: - Universal Per-View Loading Protocol
// This protocol ensures any medical viewer component can handle its own loading

import SwiftUI
import Combine

/// Protocol for views that need to manage their own loading state
protocol LoadableView {
    associatedtype LoadingState: ViewLoadingState
    var loadingState: LoadingState { get }
    func startLoading()
    func updateLoadingProgress(_ progress: Float, message: String)
    func completeLoading()
}

/// Base loading state for any view
protocol ViewLoadingState: ObservableObject {
    var isLoading: Bool { get set }
    var progress: Float { get set }
    var message: String { get set }
    var hasError: Bool { get set }
    var errorMessage: String { get set }
}

// MARK: - MPR View Loading State
@MainActor
class MPRViewLoadingState: ObservableObject, ViewLoadingState {
    @Published var isLoading: Bool = true
    @Published var progress: Float = 0.0
    @Published var message: String = "Initializing MPR..."
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""
    
    // MPR-specific loading stages
    @Published var volumeDataReady: Bool = false
    @Published var textureReady: Bool = false
    @Published var sliceReady: Bool = false
    @Published var roiReady: Bool = false
    
    enum LoadingStage: String, CaseIterable {
        case volumeData = "Loading volume data..."
        case textureCreation = "Creating GPU textures..."
        case sliceGeneration = "Generating MPR slices..."
        case roiProcessing = "Processing ROI data..."
        case complete = "Ready"
        
        var progressValue: Float {
            switch self {
            case .volumeData: return 0.25
            case .textureCreation: return 0.50
            case .sliceGeneration: return 0.75
            case .roiProcessing: return 0.90
            case .complete: return 1.0
            }
        }
    }
    
    func updateStage(_ stage: LoadingStage) {
        progress = stage.progressValue
        message = stage.rawValue
        
        switch stage {
        case .volumeData:
            volumeDataReady = false
        case .textureCreation:
            volumeDataReady = true
            textureReady = false
        case .sliceGeneration:
            textureReady = true
            sliceReady = false
        case .roiProcessing:
            sliceReady = true
            roiReady = false
        case .complete:
            roiReady = true
            isLoading = false
        }
    }
    
    func setError(_ error: String) {
        hasError = true
        errorMessage = error
        isLoading = false
    }
}

// MARK: - 3D View Loading State
@MainActor
class ThreeDViewLoadingState: ObservableObject, ViewLoadingState {
    @Published var isLoading: Bool = true
    @Published var progress: Float = 0.0
    @Published var message: String = "Initializing 3D..."
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""
    
    // 3D-specific loading stages
    @Published var volumeDataReady: Bool = false
    @Published var metalSetupReady: Bool = false
    @Published var shadersReady: Bool = false
    @Published var roiSetupReady: Bool = false
    
    enum LoadingStage: String, CaseIterable {
        case volumeData = "Loading 3D volume..."
        case metalSetup = "Initializing Metal renderer..."
        case shaderCompilation = "Compiling 3D shaders..."
        case roiSetup = "Setting up 3D ROI..."
        case complete = "3D Ready"
        
        var progressValue: Float {
            switch self {
            case .volumeData: return 0.25
            case .metalSetup: return 0.50
            case .shaderCompilation: return 0.75
            case .roiSetup: return 0.90
            case .complete: return 1.0
            }
        }
    }
    
    func updateStage(_ stage: LoadingStage) {
        progress = stage.progressValue
        message = stage.rawValue
        
        switch stage {
        case .volumeData:
            volumeDataReady = false
        case .metalSetup:
            volumeDataReady = true
            metalSetupReady = false
        case .shaderCompilation:
            metalSetupReady = true
            shadersReady = false
        case .roiSetup:
            shadersReady = true
            roiSetupReady = false
        case .complete:
            roiSetupReady = true
            isLoading = false
        }
    }
    
    func setError(_ error: String) {
        hasError = true
        errorMessage = error
        isLoading = false
    }
}

// MARK: - Universal View Loading Indicator
struct ViewLoadingIndicator<T: ViewLoadingState>: View {
    @ObservedObject var loadingState: T
    let viewType: String
    let viewSize: CGSize
    
    @State private var pulseAnimation = false
    @State private var spinnerRotation: Double = 0
    
    var body: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.8)
            
            if loadingState.hasError {
                errorView
            } else {
                loadingView
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .onAppear {
            pulseAnimation = true
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                spinnerRotation = 360
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            // Medical scanner icon
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: 40, height: 40)
                
                // Inner rotating element
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.cyan, lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(spinnerRotation))
                
                // Progress indicator
                Text("\(Int(loadingState.progress * 100))%")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // View type label
            Text(viewType)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            // Progress message
            Text(loadingState.message)
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.cyan)
                        .frame(
                            width: geometry.size.width * CGFloat(loadingState.progress),
                            height: 4
                        )
                        .animation(.spring(response: 0.3), value: loadingState.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .scaleEffect(pulseAnimation ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
    }
    
    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.red)
            
            Text("Error Loading \(viewType)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text(loadingState.errorMessage)
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Data Loading Coordinator
// Coordinates data loading and notifies individual views when their data is ready
@MainActor
class ViewDataCoordinator: ObservableObject {
    // Global data state
    @Published var volumeData: VolumeData?
    @Published var roiData: MinimalRTStructParser.SimpleRTStructData?
    @Published var patientInfo: SimplePatientInfo?
    
    // Loading progress for coordination
    @Published var isVolumeLoading: Bool = false
    @Published var isROILoading: Bool = false
    @Published var volumeLoadingProgress: Float = 0.0
    
    // Per-view data readiness tracking
    private var viewCallbacks: [String: (Bool) -> Void] = [:]
    
    // REMOVED: Shared renderer - each view creates its own
    // Option 3: Share VolumeData only, not renderers
    
    func loadAllData() async {
        await loadVolumeData()
        await loadROIData()
        await loadPatientInfo()
        notifyViewsDataReady()
    }
    
    func registerViewCallback(viewId: String, callback: @escaping (Bool) -> Void) {
        viewCallbacks[viewId] = callback
        
        // If data is already ready, notify immediately
        if volumeData != nil {
            callback(true)
        }
    }
    
    func unregisterViewCallback(viewId: String) {
        viewCallbacks.removeValue(forKey: viewId)
    }
    
    private func notifyViewsDataReady() {
        let isReady = volumeData != nil
        for callback in viewCallbacks.values {
            callback(isReady)
        }
    }
    
    private func loadVolumeData() async {
        isVolumeLoading = true
        volumeLoadingProgress = 0.0
        
        do {
            let dicomFiles = getDICOMFiles()
            guard !dicomFiles.isEmpty else {
                print("❌ No DICOM files found")
                return
            }
            
            volumeLoadingProgress = 0.25
            
            // Option 3: Load VolumeData directly without shared renderer
            var datasets: [(DICOMDataset, Int)] = []
            
            for (index, fileURL) in dicomFiles.enumerated() {
                let data = try Data(contentsOf: fileURL)
                let dataset = try DICOMParser.parse(data)
                datasets.append((dataset, index))
            }
            
            // Create volume from datasets
            let loadedVolumeData = try VolumeData(from: datasets)
            volumeData = loadedVolumeData
            volumeLoadingProgress = 1.0
            print("✅ ViewDataCoordinator: Shared VolumeData loaded (\(loadedVolumeData.dimensions))")
            
        } catch {
            print("❌ Failed to load volume data: \(error)")
        }
        
        isVolumeLoading = false
    }
    
    private func loadROIData() async {
        let rtStructFiles = DICOMFileManager.getRTStructFiles()
        
        if let rtStructFile = rtStructFiles.first {
            do {
                let data = try Data(contentsOf: rtStructFile)
                let dataset = try DICOMParser.parse(data)
                
                if let result = MinimalRTStructParser.parseSimpleRTStruct(from: dataset) {
                    roiData = result
                    // ROI data loaded successfully
                }
            } catch {
                print("❌ Failed to load ROI data: \(error)")
            }
        }
    }
    
    private func loadPatientInfo() async {
        let dicomFiles = getDICOMFiles()
        if let firstFile = dicomFiles.first {
            do {
                let data = try Data(contentsOf: firstFile)
                let dataset = try DICOMParser.parse(data)
                
                let patientName = dataset.getString(tag: DICOMTag.patientName) ?? "Unknown Patient"
                let studyDate = dataset.getString(tag: DICOMTag.studyDate) ?? "Unknown Date"
                let modality = dataset.getString(tag: DICOMTag.modality) ?? "CT"
                
                patientInfo = SimplePatientInfo(
                    name: patientName,
                    studyDate: studyDate,
                    modality: modality
                )
            } catch {
                patientInfo = SimplePatientInfo(
                    name: "Test Patient XAPV2",
                    studyDate: "2025-01-28",
                    modality: "CT"
                )
            }
        }
    }
    
    // REMOVED: getVolumeRenderer() - each view manages its own renderer
    
    // MARK: - File Discovery (copied from XAnatomyDataManager)
    
    private func getDICOMFiles() -> [URL] {
        guard let bundlePath = Bundle.main.resourcePath else {
            return []
        }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: bundlePath),
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            let dicomFiles = fileURLs.filter { url in
                let filename = url.lastPathComponent
                return (url.pathExtension.lowercased() == "dcm" ||
                        filename.contains("2.16.840.1.114362")) &&
                       !filename.contains("rtstruct") &&
                       !filename.contains("test_")
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            return dicomFiles
            
        } catch {
            print("❌ Error reading bundle root: \(error)")
            return []
        }
    }
}

// MARK: - Simple Patient Info Structure
struct SimplePatientInfo {
    let name: String
    let studyDate: String
    let modality: String
}

// MARK: - Loading Error Types
enum ViewLoadingError: Error, LocalizedError {
    case rendererInitializationFailed
    case textureCreationFailed
    case sliceGenerationFailed
    case roiProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .rendererInitializationFailed:
            return "Failed to initialize Metal renderer"
        case .textureCreationFailed:
            return "Failed to create GPU textures"
        case .sliceGenerationFailed:
            return "Failed to generate MPR slice"
        case .roiProcessingFailed:
            return "Failed to process ROI data"
        }
    }
}
