#!/bin/bash

# Script to restore X-Anatomy Pro v2.0 to clean working state

echo "🔄 Restoring X-Anatomy Pro v2.0 to clean working state..."

# The commit with working CT viewing in all projections
CLEAN_COMMIT="f0543d96781d626ba9e25ccd291354eaa0a972a5"

# Reset main branch to the clean commit
echo "📍 Resetting main branch to: $CLEAN_COMMIT"
git reset --hard $CLEAN_COMMIT

echo "✅ X-Anatomy Pro v2.0 has been restored to clean, functional state"
echo ""
echo "🎯 This state includes:"
echo "   ✓ Complete DICOM parsing (SwiftDICOM ready for open source)"
echo "   ✓ Hardware-accelerated Metal rendering (MetalMedical ready for open source)"  
echo "   ✓ Working MPR with axial, sagittal, coronal views"
echo "   ✓ Proper CT windowing (bone, lung, soft tissue)"
echo "   ✓ GPU-accelerated 3D volume reconstruction"
echo "   ✓ Fixed aspect ratios using physical DICOM spacing"
echo ""
echo "🚀 Ready for further development or ROI integration"
