#!/bin/bash
set -e

source /opt/ros/lyrical/setup.bash
source /opt/gpu_pointcloud_ws/install/local_setup.bash

# pip-installed nvidia-*-cu12 wheels (nvrtc, and potentially others later)
# put their .so files under their own package dir, e.g.
# .../site-packages/nvidia/cuda_nvrtc/lib/libnvrtc.so.12 - never on the
# standard dynamic linker search path, so CuPy's bare-filename dlopen()
# can't find them even though the package (and the .so) genuinely is
# installed. Location varies between lib and lib64 depending on how pip
# tags each wheel, so search both rather than hardcode one.
NVIDIA_LIB_DIRS=$(find /usr/local/lib /usr/local/lib64 -maxdepth 6 -path '*/nvidia/*/lib' -type d 2>/dev/null | tr '\n' ':')
if [ -n "$NVIDIA_LIB_DIRS" ]; then
    export LD_LIBRARY_PATH="${NVIDIA_LIB_DIRS}${LD_LIBRARY_PATH}"
fi

exec "$@"