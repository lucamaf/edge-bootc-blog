#!/bin/bash
set -e

eval "$(micromamba shell hook -s bash)"
micromamba activate ros_env

# Overlay the colcon workspace containing the source-built moveit2_tutorials
# (servo_keyboard_input) on top of the ros_env's own setup, standard ROS2
# workspace-overlay convention.
source /opt/servo_keyboard_ws/install/local_setup.bash

exec "$@"