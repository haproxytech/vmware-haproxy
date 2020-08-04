#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Runs a target script n times with a fixed sleep between retries

DEFAULT_SLEEP_TIME_SECS=1
DEFAULT_RETRY_ATTEMPTS=3

USAGE="
usage: ${0} [FLAGS] COMMAND
  Runs a command n times with a configurable delay after each attempt

COMMAND
  Any valid bash command. Use quotes around the command for parameters

FLAGS
  -h    show this help and exit
  -s    sleep time in seconds (defaults to $DEFAULT_SLEEP_TIME_SECS)
  -r    retry attempts (defaults to $DEFAULT_RETRY_ATTEMPTS)
"

function error() {
  local exit_code="${?}"
  echo "${@}" 1>&2
  return "${exit_code}"
}

function fatal() {
  error "${@}" || exit 1
}

while getopts ":h:s:r:" opt; do
  case ${opt} in
    h)
      error "${USAGE}" && exit 1
      ;;
    s)
      SLEEP_TIME_SECS="${OPTARG}"
      ;;
    r)
      RETRY_ATTEMPTS="${OPTARG}"
      ;;
    \?)
      error "invalid option: -${OPTARG} ${USAGE}" && exit 1
      ;;
    :)
      error "option -${OPTARG} requires an argument" && exit 1
      ;;
  esac
done
shift $((OPTIND-1))

SLEEP_TIME_SECS=${SLEEP_TIME_SECS:-$DEFAULT_SLEEP_TIME_SECS}
RETRY_ATTEMPTS=${RETRY_ATTEMPTS:-$DEFAULT_RETRY_ATTEMPTS}

if [ "${#}" -lt "1" ]; then
  fatal "COMMAND is required ${USAGE}"
fi
COMMAND="${1}"

COMMAND_NAME=$(basename "$COMMAND" | cut -d ' ' -f 1)

rc=0
for i in $(seq 1 "$RETRY_ATTEMPTS"); do
    # Run as a new bash process as it may have environment variables preceeding the command
    bash -c "$COMMAND"; rc=$?
    if [ $rc -eq 0 ]; then
        exit 0
    else
        echo "Retrying $COMMAND_NAME $i. Last return code=$rc"
        sleep "$SLEEP_TIME_SECS"
    fi
done
echo "WARNING: $COMMAND_NAME failed all retry attempts. Last return code=$rc"
exit $rc