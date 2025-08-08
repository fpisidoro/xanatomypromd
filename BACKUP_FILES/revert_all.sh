#!/bin/bash
cd "/Users/fpisidoro/Documents/Isidoro Medical Engineering Workfiles/xanatomypromd"

# Reset hard to 3 commits ago (before all the broken changes)
git reset --hard HEAD~3

echo "Reset complete - reverted all broken coordinate system changes"
