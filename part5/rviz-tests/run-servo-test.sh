#!/bin/bash
# Launches the MoveIt Servo demo (quay.io/luferrar/part5:rviz-servo) on the
# HOST, same X11/GPU passthrough as run-rviz-test.sh, plus what that one
# doesn't need: the realtime_servo_tutorial needs a SECOND terminal to
# trigger servoing while the launch file runs in the first
# (https://moveit.picknik.ai/humble/doc/examples/realtime_servo/realtime_servo_tutorial.html).
#
# A second `podman run` in an isolated network namespace wouldn't discover
# the first container's ROS2 nodes via DDS, so instead of that, this script
# runs the demo in a --name'd container and gives you an "exec" mode to run
# a second command inside that SAME container - guaranteed to share
# everything (network, process view) with the first, no DDS discovery
# involved. --net=host is set too, mainly so other host-side tooling can
# still see the node graph if you want it.
#
# Usage:
#   ./run-servo-test.sh                      # terminal 1: launches the demo
#   ./run-servo-test.sh exec <command...>     # terminal 2: run inside it
#
# Example (matches the tutorial):
#   ./run-servo-test.sh
#   # in a second terminal:
#   ./run-servo-test.sh exec ros2 service call /servo_node/start_servo std_srvs/srv/Trigger {}

set -e

IMAGE="quay.io/luferrar/part5:rviz-servo"
CONTAINER_NAME="rviz-servo"

if [ "$1" = "exec" ]; then
    shift
    exec podman exec -it "$CONTAINER_NAME" /usr/local/bin/entrypoint.sh "$@"
fi

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

# Same X11 auth cookie handling as run-rviz-test.sh - see that script for
# why (no ~/.Xauthority on a GNOME Wayland session; Mutter's cookie is
# transient and randomly named under /run/user/<uid>/ instead).
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

if command -v xhost > /dev/null 2>&1; then
    xhost +local: > /dev/null 2>&1 || true
fi

# Idempotent: clear out a stale container from a previous run that didn't
# get cleaned up (e.g. Ctrl+C mid-startup) so --name doesn't conflict.
podman rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true

echo "Image:      $IMAGE"
echo "Container:  $CONTAINER_NAME"
echo "DISPLAY:    $DISPLAY"
echo "Running as: $(id -u):$(id -g)"
echo ""
echo "For the tutorial's second terminal, run:"
echo "  ./run-servo-test.sh exec ros2 service call /servo_node/start_servo std_srvs/srv/Trigger {}"
echo ""

exec podman run --rm -it \
    --name "$CONTAINER_NAME" \
    --net=host \
    --userns=keep-id \
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