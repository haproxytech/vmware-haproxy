#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

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

USAGE="usage: ${0} [FLAGS]
  Controls custom route tables on this host

FLAGS
  -h    show this help and exit
  -u    enable custom route tables
  -f    behaves like -u, but runs in blocking mode while watching config file
  -d    disable custom route tables

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

      # Remove the rule for this route table.
      route_rule="$(ip rule | grep -F "${route_table_name}" | awk -F':[[:space:]]' '{print $2}')"
      echo2 "removing ip rule: ${route_rule}"
      # shellcheck disable=SC2086
      ip rule del ${route_rule}

      # Remove the default route for this route table.
      echo2 "removing default route for ${route_table_name}"
      ip route del table "${route_table_name}" default
    fi
  done <"${RT_TABLES_FILE}"
  mv -f "${RT_TABLES_FILE}.tmp" "${RT_TABLES_FILE}"
}

# Enables the custom route tables.
function up_routes() {
  # Enabling the custom route tables first requires removing any custom route
  # tables.
  down_routes

  while IFS= read -r line; do
    # Skip empty and commented lines.
    if [ -z "${line}" ] || [ "${line::1}" == "#" ]; then
      continue
    fi

    # Split the line into its parts.
    IFS=, read -ra line_parts <<<"${line}"

    # Store route table configuration's parts.
    cfg_table_id="${line_parts[0]}"
    cfg_table_name="${line_parts[1]}"
    cfg_mac_addr="${line_parts[2]}"
    cfg_cidr="${line_parts[3]}"
    cfg_gateway="${line_parts[4]}"
    cfg_dev="$(dev_from_mac "${cfg_mac_addr}")"
    route_table_name="${RT_TABLE_NAME_PREFIX}${cfg_table_name}"

    # Create a new route table.
    echo2 "create new route table id=${cfg_table_id} name=${route_table_name}"
    printf '%d\t%s\n' "${cfg_table_id}" "${route_table_name}" >>"${RT_TABLES_FILE}"

    # Create default route for new route table.
    echo2 "create default route for ${route_table_name}"
    ip route add table "${route_table_name}" default via "${cfg_gateway}" dev "${cfg_dev}" proto static

    # Create IP rule for new route table.
    echo2 "create IP rule for ${route_table_name}"
    ip rule add from "${cfg_cidr}" lookup "${route_table_name}"
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
