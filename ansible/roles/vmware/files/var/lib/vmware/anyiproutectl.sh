#!/bin/bash

# Copyright 2020 HAProxy Technologies
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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

    ip="${line}"
    # When doing the grep, remove a possible /32 since the "ip route"
    # command will normalize /32 IP addresses by removing the /32.
    if ! ip route show table local | grep -qF "local ${ip%/32} dev lo scope host"; then
      echo2 "route already removed for ${ip}"
    else
      echo2 "removing route for ${ip}"
      ip route del table local "${ip}" dev lo
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

    ip="${line}"
    # When doing the grep, remove a possible /32 since the "ip route"
    # command will normalize /32 IP addresses by removing the /32.
    if ip route show table local | grep -qF "local ${ip%/32} dev lo scope host"; then
      echo2 "route already exists for ${ip}"
    else
      echo2 "adding route for ${ip}"
      ip route add local "${ip}" dev lo
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
