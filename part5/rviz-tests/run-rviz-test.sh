#!/bin/bash
# Launches the rviz-tests container on the HOST (the RHEL10 box with the
# Quadro P620), passing through the host's Wayland session and the GPU via
# the already-configured nvidia-container-toolkit/CDI setup.
#
# Usage:
#   ./run-rviz-test.sh [image] -- [command...]
#   ./run-rviz-test.sh                          # runs rviz2 (default)
#   ./run-rviz-test.sh quay.io/luferrar/part5:rviz-humble -- check-gpu.sh
#   ./run-rviz-test.sh quay.io/luferrar/part5:rviz-humble -- bash

set -e

IMAGE="quay.io/luferrar/part5:rviz-humble"
if [ -n "$1" ] && [ "$1" != "--" ]; then
    IMAGE="$1"
    shift
fi
if [ "$1" = "--" ]; then
    shift
fi

XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

if [ ! -S "$WAYLAND_SOCKET" ]; then
    echo "Error: no Wayland socket at $WAYLAND_SOCKET" >&2
    echo "Run this from a terminal inside your Wayland desktop session on the host" >&2
    echo "(not over a plain SSH session without a forwarded/available compositor)." >&2
    exit 1
fi

echo "Image:            $IMAGE"
echo "Wayland socket:    $WAYLAND_SOCKET"
echo "Running as:        $(id -u):$(id -g)"
echo ""

exec podman run --rm -it \
    --device nvidia.com/gpu=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    -e QT_QPA_PLATFORM=wayland \
    -v "$WAYLAND_SOCKET:$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" \
    -v /etc/passwd:/etc/passwd:ro \
    --user "$(id -u):$(id -g)" \
    --security-opt label=disable \
    "$IMAGE" "$@"