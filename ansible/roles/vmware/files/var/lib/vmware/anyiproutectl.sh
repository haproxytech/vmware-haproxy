#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################################################################################
# usage: anyiproutectl [FLAGS]
#  This program is used to control Any IP routes on this host.
################################################################################

set -o errexit
set -o nounset
set -o pipefail

################################################################################
##                                  usage
################################################################################

USAGE="usage: ${0} [FLAGS] CMD
  Controls Any IP routes on this host

CMD
  up      enables the routes
  down    disables the routes
  watch   runs in the foreground while watching the config file for changes

FLAGS
  -h    show this help and exit

Globals
  CONFIG_FILE
    path to this program's config file. default: /etc/vmware/anyip-routes.cfg
"

################################################################################
##                                   args
################################################################################

# The path to the config file used by this program.
CONFIG_FILE="${CONFIG_FILE:-/etc/vmware/anyip-routes.cfg}"


################################################################################
##                                   funcs
################################################################################

# error stores exit code, writes arguments to STDERR, and returns stored exit code
# fatal is like error except it will exit program if exit code >0
function error() {
  local exit_code="${?}"
  echo "${@}" 1>&2
  return "${exit_code}"
}
function fatal() {
  error "${@}"
  exit 1
}
function echo2() {
  echo "${@}" 1>&2
}

# Disable any custom routes.
function down_routes() {
  while IFS= read -r line; do
    # Skip empty and commented lines.
    if [ -z "${line}" ] || [ "${line::1}" == "#" ]; then
      continue
    fi
    if ! ip route show table local | grep -qF "local ${line} dev lo scope host"; then
      echo2 "route already removed for ${line}"
    else
      echo2 "removing route for ${line}"
      ip route del table local "${line}" dev lo
    fi
  done <"${CONFIG_FILE}"
}

# Enables the custom routes.
function up_routes() {
  while IFS= read -r line; do
    # Skip empty and commented lines.
    if [ -z "${line}" ] || [ "${line::1}" == "#" ]; then
      continue
    fi
    if ip route show table local | grep -qF "local ${line} dev lo scope host"; then
      echo2 "route already exists for ${line}"
    else
      echo2 "adding route for ${line}"
      ip route add local "${line}" dev lo
    fi
  done <"${CONFIG_FILE}"
}

# Watches the config file and acts on any detected changes.
function watch_routes() {
  echo2 "watching configuration file for changes"
  inotifywait -m -e modify "${CONFIG_FILE}" | while read -r; do up_routes; done
}

################################################################################
##                                   main
################################################################################

# Parse the command-line arguments.
while getopts ":h" opt; do
  case ${opt} in
    h)
      fatal "${USAGE}"
      ;;
    \?)
      fatal "invalid option: -${OPTARG} ${USAGE}"
      ;;
    :)
      fatal "option -${OPTARG} requires an argument"
      ;;
  esac
done
shift $((OPTIND - 1))

CMD="${1-}"
case "${CMD}" in
  up)
    up_routes
    ;;
  down)
    down_routes
    ;;
  watch)
    watch_routes
    ;;
  *)
    error "${USAGE}"
    ;;
esac
