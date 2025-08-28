#!/bin/bash
echo -e "
##################################
#
# Welcome to \033[1;36m`hostname -s`,\033[0m you are logged in as \033[1;20m`whoami`\033[0m
# This system is running \033[1;32m`cat /etc/redhat-release`\033[0m
# Kernel is \033[1;33m`uname -r`\033[0m
# Uptime is
\033[1;20m>>`uptime | sed 's/.*up ([^,]*), .*/1/'`\033[0m

\033[1;21m**Disk Usage (root): \033[1;33m`df -h | grep '/$' | awk '{print $5}'`\033[0m
###################################"
figlet -f small `hostname -s`
echo -e "-----------------------------"