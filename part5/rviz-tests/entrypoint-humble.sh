#!/bin/bash
set -e

eval "$(micromamba shell hook -s bash)"
micromamba activate ros_env

exec "$@"