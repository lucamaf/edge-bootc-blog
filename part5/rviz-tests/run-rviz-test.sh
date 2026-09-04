#!/bin/bash
# Launches the rviz-tests container on the HOST (the RHEL10 box with the
# Quadro P620), passing through the GPU via nvidia-container-toolkit/CDI
# (see nvidia-cdi-setup.md) and the GUI via X11/XWayland or Wayland.
#
# Both socket types are mounted unconditionally (Wayland's is best-effort -
# not every image needs it); which one actually gets used is up to each
# image's own QT_QPA_PLATFORM default in its Containerfile, not this script
# - it used to hardcode -e QT_QPA_PLATFORM=xcb here, overriding whatever the
# image itself set. RoboStack/conda-forge's Qt build for ros-humble-desktop
# has no "wayland" platform plugin at all (confirmed by Qt's own error
# listing available plugins, xcb only), so those images stay on xcb/
# XWayland; quay.io/luferrar/part5:rviz-kilted's RPM-packaged Qt does have a
# working wayland plugin (via the separate qt5-qtwayland package) - once
# end-to-end rendering through it is actually confirmed, that image's own
# Containerfile default can move to wayland instead of xcb.
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
# by the host's own X11 auth cookie - but on a GNOME Wayland session (this
# one included) there usually is no ~/.Xauthority at all; Mutter generates
# a transient, randomly-named XWayland cookie under /run/user/<uid>/
# instead. Prefer $XAUTHORITY if the environment actually has it (it may,
# in an interactive login shell that imported the session environment,
# even though a plain non-interactive one won't), then fall back to
# locating Mutter's file directly, then finally the traditional path.
if [ -n "$XAUTHORITY" ] && [ -f "$XAUTHORITY" ]; then
    XAUTH_HOST="$XAUTHORITY"
else
    XAUTH_HOST=$(ls -t /run/user/"$(id -u)"/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
    if [ -z "$XAUTH_HOST" ] && [ -f "$HOME/.Xauthority" ]; then
        XAUTH_HOST="$HOME/.Xauthority"
    fi
fi

XAUTH_MOUNT=()
if [ -n "$XAUTH_HOST" ]; then
    XAUTH_MOUNT=(-v "$XAUTH_HOST:/tmp/.Xauthority:ro" -e XAUTHORITY=/tmp/.Xauthority)
else
    echo "Warning: no X11 auth cookie found (checked \$XAUTHORITY, Mutter's" >&2
    echo "transient cookie, and ~/.Xauthority) - connection will likely fail." >&2
fi

# Belt-and-braces fallback in case the cookie approach above doesn't cover
# it (e.g. cookie file is stale) - only if xhost is actually installed,
# which it isn't guaranteed to be on a Wayland-first RHEL10 desktop.
if command -v xhost > /dev/null 2>&1; then
    xhost +local: > /dev/null 2>&1 || true
fi

# Best-effort Wayland socket mount, alongside X11/XWayland above - not
# every image can use it (see header), but it's harmless to mount for the
# ones that don't. Same $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY resolution this
# script used back when Wayland was the only path it supported.
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

WAYLAND_MOUNT=()
if [ -S "$WAYLAND_SOCKET" ]; then
    WAYLAND_MOUNT=(
        -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
        -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
        -v "$WAYLAND_SOCKET:$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    )
fi

echo "Image:      $IMAGE"
echo "DISPLAY:    $DISPLAY"
echo "Running as: $(id -u):$(id -g)"
echo ""

exec podman run --rm -it \
    --userns=keep-id \
    --device nvidia.com/gpu=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e DISPLAY="$DISPLAY" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /etc/passwd:/etc/passwd:ro \
    "${XAUTH_MOUNT[@]}" \
    "${WAYLAND_MOUNT[@]}" \
    --user "$(id -u):$(id -g)" \
    --security-opt label=disable \
    "$IMAGE" "$@"