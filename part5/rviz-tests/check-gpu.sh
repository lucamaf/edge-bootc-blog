#!/bin/bash
# Confirms rviz2's GL/EGL context is actually backed by the NVIDIA driver
# and not silently falling back to software rendering (llvmpipe) or being
# picked up only by XWayland compositing rather than the app itself.
# Run this INSIDE the container (it's the default alternate command, see
# README), then cross-check with `nvidia-smi` on the HOST while rviz2 is
# running - that's the more reliable signal, since a known rviz2/Wayland
# issue is GPU use showing up under XWayland's process rather than rviz2's.

echo "== EGL renderer =="
if command -v eglinfo &> /dev/null; then
    RENDERER=$(eglinfo 2>/dev/null | grep -i renderer | head -1)
    if [ -n "$RENDERER" ]; then
        echo "$RENDERER"
    else
        echo "No renderer line found; full eglinfo output:"
        eglinfo
    fi
else
    echo "eglinfo not found (mesa-demos not installed?)"
fi

echo ""
echo "== GLX renderer (XWayland fallback path) =="
if command -v glxinfo &> /dev/null; then
    glxinfo | grep -i "OpenGL renderer" || echo "glxinfo ran but produced no renderer line"
else
    echo "glxinfo not found (glx-utils not installed?)"
fi

echo ""
echo "== What to look for =="
echo "  Good:  renderer string contains 'NVIDIA' / 'Quadro P620'"
echo "  Bad:   renderer string contains 'llvmpipe' (software rendering) or the"
echo "         command fails outright (GPU/driver libs not reaching the container)"
echo ""
echo "Also run 'nvidia-smi' on the HOST while rviz2 is running to confirm a"
echo "GPU process actually shows up."