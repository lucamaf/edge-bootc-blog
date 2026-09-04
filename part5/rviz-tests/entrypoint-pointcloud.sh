#!/bin/bash
set -e

eval "$(micromamba shell hook -s bash)"
micromamba activate ros_env

# Overlay the colcon workspace containing gpu_pointcloud_test on top of the
# ros_env's own setup, standard ROS2 workspace-overlay convention.
source /opt/gpu_pointcloud_ws/install/local_setup.bash

exec "$@"
