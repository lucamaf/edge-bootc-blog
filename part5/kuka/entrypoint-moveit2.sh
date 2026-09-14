#!/bin/bash
set -e

source /opt/ros/jazzy/setup.bash
source /opt/kuka_ws/install/local_setup.bash

exec "$@"
