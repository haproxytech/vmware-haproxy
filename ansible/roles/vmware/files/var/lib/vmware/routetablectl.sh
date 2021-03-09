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
# usage: routetablectl [FLAGS]
#  This program is used to control custom route tables on this host.
################################################################################

set -o errexit
set -o nounset
set -o pipefail

################################################################################
##                                  usage
################################################################################

USAGE="usage: ${0} [FLAGS] CMD
  Controls custom route tables on this host

CMD
  up      enables the routes
  down    disables the routes
  watch   runs in the foreground while watching the config file for changes

FLAGS
  -h    show this help and exit

Globals
  CONFIG_FILE
    path to this program's config file. default: /etc/vmware/route-tables.cfg
  RT_TABLES_FILE
    path to the rt_tables file. default: /etc/iproute2/rt_tables
"

################################################################################
##                                   const
################################################################################

# The prefix for the names of route tables created with this program.
RT_TABLE_NAME_PREFIX="rtctl_"

################################################################################
##                                   args
################################################################################

# The path to the config file used by this program.
CONFIG_FILE="${CONFIG_FILE:-/etc/vmware/route-tables.cfg}"

# The path to the file with the route table identifiers.
RT_TABLES_FILE="${RT_TABLES_FILE:-/etc/iproute2/rt_tables}"

# Path to the file for additional workload networks.
WORKLOAD_NETWORKS_FILE="${WORKLOAD_NETWORKS_FILE:-/etc/vmware/workload-networks.cfg}"

# Name of the route table for workload networks.
WORKLOAD_RT="${WORKLOAD_RT:-${RT_TABLE_NAME_PREFIX}workload}"

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
  echo "${@}" 2>&1
}

function call() {
  echo2 "${@}"
  eval "${@}"
}

# Returns the name of the device that has the provided MAC address.
function dev_from_mac() {
  ip -o link | awk -F': ' -vIGNORECASE=1 '/'"${1}"'/ { print $2 }' | awk -F'@' '{print $1}'
}

# Disable any custom route tables.
function down_routes() {
  printf '' >"${RT_TABLES_FILE}.tmp"
  while IFS= read -r line; do
    # Copy the line only if it is not a rtctl_ table.
    if [[ "${line}" != *"${RT_TABLE_NAME_PREFIX}"* ]]; then
      echo "${line}" >>"${RT_TABLES_FILE}.tmp"
    # Otherwise, get the name of the table and disable it.
    else
      # Get the name of the route table.
      route_table_name="$(echo "${line}" | awk -F' ' '{print $2}')"
      echo2 "discovered route table ${route_table_name}"

      # Remove the rules for this route table.
      while ip call "rule del from 0/0 to 0/0 table ${route_table_name} 2>/dev/null"; do true; done

      # Remove any existing routes from our route tables.
      while IFS= read -r route; do
        call "ip route del table ${route_table_name} ${route}"
      done < <(ip route show table "${route_table_name}")
    fi
  done < "${RT_TABLES_FILE}"
  mv -f "${RT_TABLES_FILE}.tmp" "${RT_TABLES_FILE}"
}

# Adds route tables to the route tables file. Prevents duplicates from being added.
function add_route_tables() {
  tables=$(grep -E '^\w' "${CONFIG_FILE}" || echo "" | cut -d, -f1,2 | uniq)
  for table in ${tables}; do
    IFS=, read -ra line <<< "${table}"
    route_table_id="${line[0]}"
    route_table_name="${RT_TABLE_NAME_PREFIX}${line[1]}"
    echo2 "create new route table id=${route_table_id} name=${route_table_name}"
    printf '%d\t%s\n' "${route_table_id}" "${route_table_name}" >>"${RT_TABLES_FILE}"
  done
}

# Adds lookup rules for workload routes. The net result is that additional workloads can be reached
# via the default gateway of the workload network route table.
function add_workload_network_rules() {
  if [ ! -f "${WORKLOAD_NETWORKS_FILE}" ]; then
    echo2 "no additional workload networks detected"
    return
  fi

  while IFS= read -r cfg_cidr; do
    # Skip empty and commented lines.
    if [ -z "${cfg_cidr}" ] || [ "${cfg_cidr::1}" == "#" ]; then
      continue
    fi
    call "ip rule add to ${cfg_cidr} lookup ${WORKLOAD_RT}"
  done < "${WORKLOAD_NETWORKS_FILE}"
}

# Enables the custom route tables.
function up_routes() {
  # Enabling the custom route tables first requires removing any custom route
  # tables.
  down_routes

  if [ ! -f "${CONFIG_FILE}" ]; then
    echo2 "missing config file ${CONFIG_FILE}"
    return 0
  fi

  add_route_tables
  add_workload_network_rules

  while IFS= read -r line; do
    # Skip empty and commented lines.
    if [ -z "${line}" ] || [ "${line::1}" == "#" ]; then
      continue
    fi

    # Split the line into its parts.
    IFS=, read -ra line_parts <<<"${line}"

    # Store route table configuration's parts.
    cfg_table_name="${line_parts[1]}"
    cfg_mac_addr="${line_parts[2]}"
    cfg_cidr="${line_parts[3]}"
    cfg_gateway=""

    if [[ ${#line_parts[@]} == 5 ]]; then
        cfg_gateway="${line_parts[4]}"
    fi

    cfg_dev="$(dev_from_mac "${cfg_mac_addr}")"
    route_table_name="${RT_TABLE_NAME_PREFIX}${cfg_table_name}"

    if [[ "${cfg_gateway}" == "" ]]; then
        cfg_destination=$(python3 -c "import sys; import ipaddress; print(ipaddress.ip_network(sys.argv[1], strict=False))" "${cfg_cidr}")
        host="$(echo "${cfg_cidr}" | cut -d/ -f 1)"
        call "ip route add table ${route_table_name} ${cfg_destination} dev ${cfg_dev} proto kernel scope link src ${host}"
    else
        # Create default route for new route table.
        call "ip route add table ${route_table_name} default via ${cfg_gateway} dev ${cfg_dev} proto static"
        # Create IP rule for new route table.
        call "ip rule add from ${cfg_cidr} lookup ${route_table_name}"
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
