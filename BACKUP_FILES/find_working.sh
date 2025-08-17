#!/bin/bash
cd /Users/fpisidoro/Documents/Isidoro\ Medical\ Engineering\ Workfiles/xanatomypromd

# Find the last commit before the first "Fix 3D view" commit
git log --oneline | grep -n "Fix 3D view" | tail -1

# Show commits before that
git log --oneline -20 | head -15
