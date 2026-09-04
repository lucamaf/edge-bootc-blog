#!/bin/bash
set -e

source /opt/ros/kilted/setup.bash
source /opt/gpu_pointcloud_ws/install/local_setup.bash

exec "$@"