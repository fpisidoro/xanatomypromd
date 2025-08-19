// Add this extension to XAnatomyProMainView.swift after the main struct

extension XAnatomyProMainView {
    
    func debugROISystem() {
        print("\n" + String(repeating: "=", count: 60))
        print("🔍 COMPREHENSIVE ROI SYSTEM DEBUG")
        print(String(repeating: "=", count: 60))
        
        // 1. Check if ROI data is loaded
        print("\n1️⃣ ROI DATA LOADING:")
        if let roiData = dataCoordinator.roiData {
            print("   ✅ ROI data loaded")
            print("   Structure Set: \(roiData.structureSetName ?? "Unknown")")
            print("   Patient: \(roiData.patientName ?? "Unknown")")
            print("   Number of ROIs: \(roiData.roiStructures.count)")
            
            for roi in roiData.roiStructures {
                print("\n   ROI #\(roi.roiNumber): '\(roi.roiName)'")
                print("      Color: RGB(\(roi.displayColor.x), \(roi.displayColor.y), \(roi.displayColor.z))")
                print("      Contours: \(roi.contours.count)")
                
                let zPositions = roi.contours.map { $0.slicePosition }.sorted()
                if let minZ = zPositions.first, let maxZ = zPositions.last {
                    print("      Z-range: \(minZ)mm to \(maxZ)mm")
                    print("      Z-positions: \(zPositions)")
                }
            }
        } else {
            print("   ❌ NO ROI DATA LOADED!")
        }
        
        // 2. Check volume data
        print("\n2️⃣ VOLUME DATA:")
        if let volumeData = dataCoordinator.volumeData {
            print("   ✅ Volume loaded")
            print("   Dimensions: \(volumeData.dimensions)")
            print("   Origin: \(volumeData.origin)")
            print("   Spacing: \(volumeData.spacing)")
            
            let minZ = volumeData.origin.z
            let maxZ = volumeData.origin.z + Float(volumeData.dimensions.z - 1) * volumeData.spacing.z
            print("   Z-range: \(minZ)mm to \(maxZ)mm")
        } else {
            print("   ❌ NO VOLUME DATA!")
        }
        
        // 3. Check coordinate system
        print("\n3️⃣ COORDINATE SYSTEM:")
        print("   Current world position: \(coordinateSystem.currentWorldPosition)")
        print("   Current slice index (axial): \(coordinateSystem.getCurrentSliceIndex(for: MPRPlane.axial))")
        print("   Volume origin: \(coordinateSystem.volumeOrigin)")
        print("   Volume spacing: \(coordinateSystem.volumeSpacing)")
        print("   Volume dimensions: \(coordinateSystem.volumeDimensions)")
        
        let currentZ = coordinateSystem.currentWorldPosition.z
        print("   Current Z: \(currentZ)mm")
        
        // 4. Check ROI settings
        print("\n4️⃣ ROI DISPLAY SETTINGS:")
        print("   Is visible: \(sharedViewingState.roiSettings.isVisible)")
        print("   Global opacity: \(sharedViewingState.roiSettings.globalOpacity)")
        print("   Show outline: \(sharedViewingState.roiSettings.showOutline)")
        print("   Show filled: \(sharedViewingState.roiSettings.showFilled)")
        
        // 5. Check Z-coordinate alignment
        print("\n5️⃣ Z-COORDINATE ALIGNMENT CHECK:")
        if let roiData = dataCoordinator.roiData, let volumeData = dataCoordinator.volumeData {
            let volumeMinZ = volumeData.origin.z
            let volumeMaxZ = volumeData.origin.z + Float(volumeData.dimensions.z - 1) * volumeData.spacing.z
            
            print("   Volume Z-range: \(volumeMinZ)mm to \(volumeMaxZ)mm")
            
            for roi in roiData.roiStructures {
                let zPositions = roi.contours.map { $0.slicePosition }
                
                for z in zPositions {
                    if z < volumeMinZ || z > volumeMaxZ {
                        print("   ❌ ROI contour at Z=\(z)mm is OUTSIDE volume bounds!")
                    } else {
                        let sliceIndex = Int((z - volumeData.origin.z) / volumeData.spacing.z)
                        print("   ✅ ROI contour at Z=\(z)mm maps to slice \(sliceIndex)")
                    }
                }
            }
            
            // Check if current position matches any ROI
            let tolerance = volumeData.spacing.z * 0.5
            var foundMatch = false
            
            for roi in roiData.roiStructures {
                for contour in roi.contours {
                    if abs(contour.slicePosition - currentZ) <= tolerance {
                        print("   ✅ MATCH: Current Z=\(currentZ)mm matches contour at Z=\(contour.slicePosition)mm")
                        foundMatch = true
                    }
                }
            }
            
            if !foundMatch {
                print("   ⚠️ Current Z=\(currentZ)mm doesn't match any ROI contours")
                
                // Find nearest
                var nearestDistance = Float.infinity
                var nearestZ: Float = 0
                
                for roi in roiData.roiStructures {
                    for contour in roi.contours {
                        let distance = abs(contour.slicePosition - currentZ)
                        if distance < nearestDistance {
                            nearestDistance = distance
                            nearestZ = contour.slicePosition
                        }
                    }
                }
                
                if nearestDistance < Float.infinity {
                    print("   💡 Nearest ROI contour is at Z=\(nearestZ)mm (distance: \(nearestDistance)mm)")
                    let targetSlice = Int((nearestZ - volumeData.origin.z) / volumeData.spacing.z)
                    print("   💡 Navigate to slice \(targetSlice) to see ROI")
                }
            }
        }
        
        print("\n" + String(repeating: "=", count: 60))
        print("🏁 END DEBUG")
        print(String(repeating: "=", count: 60))
    }
}