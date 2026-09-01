#!/bin/bash
# Launches the rviz-tests container on the HOST (the RHEL10 box with the
# Quadro P620), passing through the GPU via nvidia-container-toolkit/CDI
# (see nvidia-cdi-setup.md) and the GUI via X11/XWayland.
#
# X11, not Wayland: RoboStack/conda-forge's Qt build for ros-humble-desktop
# has no "wayland" platform plugin at all (confirmed by Qt's own error
# listing its available plugins - xcb was the only relevant one present),
# so Wayland passthrough can't work with this toolchain regardless of host
# setup. xcb connects to XWayland, which RHEL10 keeps specifically for X11
# app compatibility even though the standalone Xorg server is gone.
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

DISPLAY="${DISPLAY:-:0}"

if [ ! -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
    echo "Error: no X11/XWayland socket for DISPLAY=$DISPLAY" >&2
    echo "Run this from a terminal inside your desktop session on the host." >&2
    exit 1
fi

# Container connects as the same host UID, so it should already be covered
# by the host's own X11 auth cookie - but XWayland's actual cookie file
# often isn't ~/.Xauthority (it's commonly a transient file under
# /run/user/<uid>/ on a Wayland session), so read whatever $XAUTHORITY the
# host shell actually has rather than assuming a path.
XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
XAUTH_MOUNT=()
if [ -f "$XAUTHORITY" ]; then
    XAUTH_MOUNT=(-v "$XAUTHORITY:/tmp/.Xauthority:ro" -e XAUTHORITY=/tmp/.Xauthority)
else
    echo "Warning: no X11 auth cookie found at $XAUTHORITY - relying on xhost only." >&2
fi

# Belt-and-braces fallback in case the cookie approach above doesn't cover
# it (e.g. cookie file is stale) - bare "local:" authorizes local-socket
# connections, unlike the previous "local:podman" (not a real system user,
# so that authorized nothing).
xhost +local: > /dev/null 2>&1 || true

echo "Image:      $IMAGE"
echo "DISPLAY:    $DISPLAY"
echo "Running as: $(id -u):$(id -g)"
echo ""

exec podman run --rm -it \
    --device nvidia.com/gpu=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e DISPLAY="$DISPLAY" \
    -e QT_QPA_PLATFORM=xcb \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /etc/passwd:/etc/passwd:ro \
    "${XAUTH_MOUNT[@]}" \
    --user "$(id -u):$(id -g)" \
    --security-opt label=disable \
    "$IMAGE" "$@"