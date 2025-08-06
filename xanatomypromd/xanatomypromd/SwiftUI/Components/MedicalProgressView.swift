import SwiftUI

// MARK: - Medical Progress View
// A cool, medical-themed progress indicator for DICOM loading

struct MedicalProgressView: View {
    let current: Int
    let total: Int
    let message: String
    
    @State private var pulseAnimation = false
    @State private var scanLinePosition: CGFloat = 0
    
    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    private var percentage: Int {
        return Int(progress * 100)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // CT Scanner Animation
            ZStack {
                // Scanner ring
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .stroke(Color.cyan.opacity(0.6), lineWidth: 2)
                    .frame(width: 90, height: 90)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .opacity(pulseAnimation ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                
                // Scanning beam
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0), Color.cyan, Color.cyan.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 80, height: 2)
                    .rotationEffect(.degrees(Double(current) * 360.0 / Double(max(total, 1))))
                    .animation(.linear(duration: 0.3), value: current)
                
                // Center indicator
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text("\(percentage)%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            
            // Progress Details
            VStack(spacing: 8) {
                Text(message)
                    .font(.headline)
                    .foregroundColor(.white)
                
                // File counter
                HStack {
                    Text("Slice")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(current)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                    Text("of")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(total)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        // Progress fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(progress), height: 8)
                            .animation(.spring(response: 0.3), value: progress)
                        
                        // Scanning line effect
                        if progress > 0 && progress < 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: 2, height: 12)
                                .offset(x: geometry.size.width * CGFloat(progress) - 1)
                                .opacity(pulseAnimation ? 1.0 : 0.3)
                        }
                    }
                }
                .frame(height: 8)
                
                // Status text
                if progress >= 1.0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Complete")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                } else {
                    Text("Processing DICOM data...")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Quick Loading View

struct QuickLoadingView: View {
    let message: String
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Simple spinner
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.cyan, lineWidth: 3)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotation)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .onAppear {
            rotation = 360
        }
    }
}

// MARK: - Preview

struct MedicalProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 40) {
                MedicalProgressView(
                    current: 27,
                    total: 53,
                    message: "Loading CT Series"
                )
                
                QuickLoadingView(message: "Generating sagittal view...")
            }
        }
        .previewLayout(.sizeThatFits)
    }
}
