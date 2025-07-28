import SwiftUI
import Foundation

// MARK: - ROI Test View
// Simple UI for testing ROI functionality without breaking existing CT viewer
// Can be easily integrated or used standalone for testing

struct ROITestView: View {
    
    @StateObject private var roiTest = ROITestImplementation()
    @State private var isLoading = false
    @State private var testResults: [String] = []
    @State private var selectedPlane: MPRPlane = .axial
    @State private var slicePosition: Float = 100.0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                // Header
                Text("ROI Integration Test")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                if isLoading {
                    ProgressView("Loading RTStruct data...")
                        .foregroundColor(.white)
                } else {
                    // Test Controls
                    testControlsSection
                    
                    // ROI Information
                    roiInformationSection
                    
                    // Test Results
                    testResultsSection
                }
                
                Spacer()
            }
            .padding()
            .background(Color.black)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            loadROIData()
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Test Controls
    
    private var testControlsSection: some View {
        VStack(spacing: 16) {
            Text("Test Controls")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                Button("Load RTStruct") {
                    loadROIData()
                }
                .buttonStyle(TestButtonStyle())
                
                Button("Run All Tests") {
                    runAllTests()
                }
                .buttonStyle(TestButtonStyle())
                
                Button("Clear Results") {
                    testResults.removeAll()
                }
                .buttonStyle(TestButtonStyle(color: .red))
            }
            
            // Plane and slice selection
            HStack(spacing: 20) {
                VStack {
                    Text("Plane")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Picker("Plane", selection: $selectedPlane) {
                        ForEach(MPRPlane.allCases, id: \\.self) { plane in
                            Text(plane.abbreviation).tag(plane)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                VStack {
                    Text("Slice Position: \(String(format: "%.0f", slicePosition))mm")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Slider(value: $slicePosition, in: 0...200, step: 5)
                        .accentColor(.blue)
                }
            }
            
            Button("Test ROI Display") {
                testROIDisplay()
            }
            .buttonStyle(TestButtonStyle(color: .blue))
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - ROI Information
    
    private var roiInformationSection: some View {
        VStack(spacing: 12) {
            Text("ROI Information")
                .font(.headline)
                .foregroundColor(.white)
            
            if roiTest.isROIDataReady {
                let roiNames = roiTest.getROIManager().getROINames()
                
                if roiNames.isEmpty {
                    Text("No ROI structures found")
                        .foregroundColor(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Found \(roiNames.count) ROI structures:")
                            .foregroundColor(.green)
                        
                        ForEach(Array(roiNames.enumerated()), id: \\.offset) { index, name in
                            Text("• \(name)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            } else {
                Text("No RTStruct data loaded")
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Test Results
    
    private var testResultsSection: some View {
        VStack(spacing: 12) {
            Text("Test Results")
                .font(.headline)
                .foregroundColor(.white)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if testResults.isEmpty {
                        Text("No test results yet")
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        ForEach(Array(testResults.enumerated()), id: \\.offset) { index, result in
                            Text(result)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Test Functions
    
    private func loadROIData() {
        isLoading = true
        testResults.removeAll()
        
        Task {
            await roiTest.loadTestRTStruct()
            
            DispatchQueue.main.async {
                isLoading = false
                if roiTest.isROIDataReady {
                    testResults.append("✅ RTStruct data loaded successfully")
                    let roiCount = roiTest.getROIManager().getROINames().count
                    testResults.append("📊 Found \(roiCount) ROI structures")
                } else {
                    testResults.append("❌ Failed to load RTStruct data")
                }
            }
        }
    }
    
    private func runAllTests() {
        testResults.removeAll()
        testResults.append("🚀 Starting comprehensive ROI tests...")
        
        Task {
            await roiTest.runAllTests()
            
            DispatchQueue.main.async {
                testResults.append("✅ All tests completed")
                testResults.append("Check console for detailed results")
            }
        }
    }
    
    private func testROIDisplay() {
        guard roiTest.isROIDataReady else {
            testResults.append("❌ No RTStruct data loaded")
            return
        }
        
        testResults.append("🧪 Testing ROI display for \(selectedPlane.rawValue) at \(String(format: "%.0f", slicePosition))mm")
        
        // Test ROI display with typical volume parameters
        let volumeOrigin = SIMD3<Float>(0, 0, 0)
        let volumeSpacing = SIMD3<Float>(0.7, 0.7, 3.0)
        
        roiTest.testROIDisplay(
            plane: selectedPlane,
            slicePosition: slicePosition,
            volumeOrigin: volumeOrigin,
            volumeSpacing: volumeSpacing
        )
        
        let roiInfo = roiTest.getROIManager().getROIInfoForSlice(
            plane: selectedPlane,
            slicePosition: slicePosition
        )
        
        if roiInfo.isEmpty {
            testResults.append("ℹ️ No ROIs found on this slice")
        } else {
            testResults.append("🎯 Found \(roiInfo.count) ROIs on slice:")
            for info in roiInfo {
                testResults.append("  • \(info)")
            }
        }
    }
}

// MARK: - Custom Button Style

struct TestButtonStyle: ButtonStyle {
    let color: Color
    
    init(color: Color = .blue) {
        self.color = color
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.6 : 0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    ROITestView()
}
