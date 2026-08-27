#!/bin/sh
set -e

: "${ALLOW_ANONYMOUS:=true}"
: "${MAX_CONNECTIONS:=-1}"
: "${MAX_KEEPALIVE:=60}"
: "${MAX_QUEUED_MESSAGES:=1000}"
: "${PERSISTENCE:=true}"

sed \
  -e "s/__ALLOW_ANONYMOUS__/${ALLOW_ANONYMOUS}/" \
  -e "s/__MAX_CONNECTIONS__/${MAX_CONNECTIONS}/" \
  -e "s/__MAX_KEEPALIVE__/${MAX_KEEPALIVE}/" \
  -e "s/__MAX_QUEUED_MESSAGES__/${MAX_QUEUED_MESSAGES}/" \
  -e "s/__PERSISTENCE__/${PERSISTENCE}/" \
  /mosquitto/config/mosquitto.conf.template > /mosquitto/config/mosquitto.conf

exec mosquitto -c /mosquitto/config/mosquitto.conf