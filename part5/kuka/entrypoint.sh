#!/bin/bash
set -e

eval "$(micromamba shell hook -s bash)"
micromamba activate ros_env
source /opt/kuka_ws/install/local_setup.bash

exec "$@"
