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

USAGE="usage: ${0} [FLAGS]
  Controls Any IP routes on this host

FLAGS
  -h    show this help and exit
  -u    enable Any IP routes
  -f    behaves like -u, but runs in blocking mode while watching config file
  -d    disable Any IP routes

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
    echo2 "removing Any IP route for ${line}"
    ip route del table local "${line}" dev lo
  done <"${CONFIG_FILE}"
}

# Enables the custom routes.
function up_routes() {
  while IFS= read -r line; do
    # Skip empty and commented lines.
    if [ -z "${line}" ] || [ "${line::1}" == "#" ]; then
      continue
    fi
    echo2 "adding Any IP route for ${line}"
    ip route add local "${line}" dev lo
  done <"${CONFIG_FILE}"
}

# Starts monitoring the config file and calls the provided function
# when there are changes to the config file.
function start_monitoring() {
  echo2 "start monitoring ${1}"
  inotifywait -m -e modify "${CONFIG_FILE}" | eval "${1}"
}

################################################################################
##                                   main
################################################################################

# Parse the command-line arguments.
while getopts ":hudf" opt; do
  case ${opt} in
    h)
      fatal "${USAGE}"
      ;;
    u)
      up_routes
      exit "${?}"
      ;;
    f)
      start_monitoring up_routes
      exit "${?}"
      ;;
    d)
      down_routes
      exit "${?}"
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
error "${USAGE}"
