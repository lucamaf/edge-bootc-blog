#!/bin/bash
#exec > /var/tmp/power.csv 2>&1
script -q -c /usr/bin/power.sh | tee /var/tmp/power.csv