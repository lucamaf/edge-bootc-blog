#!/bin/bash
set -e

# The Fedora/Lyrical Copr has no ros2launch package (see README) - only
# launch/launch_ros themselves plus the ros2cli core verbs (action,
# component, daemon, node, param, pkg, run, service, topic). gpu_pointcloud
# .launch.py just runs two Node actions with no event handlers or other
# launch-framework features, so this drives the same two processes directly
# via `ros2 run`, matching the launch file's own defaults and
# DeclareLaunchArgument names/defaults one-for-one instead of going through
# LaunchService.

SOURCE=synthetic
TOPIC_IN=/points
TOPIC_OUT=/gpu_points
FRAME_ID=map
PUBLISH_RATE=60.0
NUM_POINTS=1000000
GPU_ITERATIONS=400
NEIGHBOR_SAMPLE=3000
COLORIZE=true
USE_RVIZ=true

for arg in "$@"; do
    key="${arg%%:=*}"
    value="${arg#*:=}"
    case "$key" in
        source) SOURCE="$value" ;;
        topic_in) TOPIC_IN="$value" ;;
        topic_out) TOPIC_OUT="$value" ;;
        frame_id) FRAME_ID="$value" ;;
        publish_rate) PUBLISH_RATE="$value" ;;
        num_points) NUM_POINTS="$value" ;;
        gpu_iterations) GPU_ITERATIONS="$value" ;;
        neighbor_sample) NEIGHBOR_SAMPLE="$value" ;;
        colorize) COLORIZE="$value" ;;
        use_rviz) USE_RVIZ="$value" ;;
        *) echo "Unknown argument: $arg (expected key:=value)" >&2; exit 1 ;;
    esac
done

RVIZ_CONFIG=/opt/gpu_pointcloud_ws/install/gpu_pointcloud_test/share/gpu_pointcloud_test/config/gpu_pointcloud.rviz

ros2 run gpu_pointcloud_test gpu_pointcloud_node --ros-args \
    -p source:="$SOURCE" \
    -p topic_in:="$TOPIC_IN" \
    -p topic_out:="$TOPIC_OUT" \
    -p frame_id:="$FRAME_ID" \
    -p publish_rate:="$PUBLISH_RATE" \
    -p num_points:="$NUM_POINTS" \
    -p gpu_iterations:="$GPU_ITERATIONS" \
    -p neighbor_sample:="$NEIGHBOR_SAMPLE" \
    -p colorize:="$COLORIZE" &
NODE_PID=$!

trap 'kill "$NODE_PID" 2>/dev/null' EXIT

if [ "$USE_RVIZ" = "true" ]; then
    ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG"
else
    wait "$NODE_PID"
fi