#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################################################################################
# usage: test-route-programs
#  Deploys a local test environment for testing anyiproutectl and routetablectl
################################################################################

set -o errexit  # Exits immediately on unexpected errors (does not bypass traps)
set -o nounset  # Errors if variables are used without first being defined
set -o pipefail # Non-zero exit codes in piped commands causes pipeline to fail
                # with that code

# Change directories to the parent directory of the one in which this script is
# located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

################################################################################
##                                  usage
################################################################################

USAGE="usage: ${0} [FLAGS]
  Deploys a local test environment for testing anyiproutectl and routetablectl

FLAGS
  -h    show this help and exit
  -a    test anyiproutectl
  -r    test routetablectl

Globals
  HAPROXY_IMAGE
    name of the HAProxy image to use; otherwise builds locally
  HAPROXY_CONTAINER
    name of the HAProxy container. default: haproxy
"

################################################################################
##                                   const
################################################################################
DOCKER_NET_1=test-routes-1
DOCKER_NET_2=test-routes-2
DOCKER_NET_3=test-routes-3

################################################################################
##                                   args
################################################################################

HAPROXY_IMAGE="${HAPROXY_IMAGE-}"
HAPROXY_CONTAINER="${HAPROXY_CONTAINER:-haproxy}"

################################################################################
##                                  require
################################################################################

function check_dependencies() {
  command -v docker >/dev/null 2>&1 || fatal "docker is required"
}

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

# Gets the CIDR of the provided Docker network.
function net_cidr() {
  docker network inspect --format='{{range .IPAM.Config}}{{.Subnet}}{{end}}' "${1}"
}

# Gets the gateway of the provided Docker network.
function net_gateway() {
  docker network inspect --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}' "${1}"
}

# Gets the MAC address of the HAProxy container connnected to the provided
# network.
# Will fail unless the HAProxy container is running.
function net_mac_addr() {
  docker network inspect --format='{{range .Containers}}{{.MacAddress}}{{end}}' "${1}"
}

# Creates a Docker network if it does not exist.
function net_create() {
  if [ -z "$(docker network ls -qf "Name=${1}")" ]; then
    echo "creating docker network ${1}"
    docker network create --attachable --driver=bridge "${1}"
  fi
}

# Deletes a Docker network.
function net_delete() {
  echo "deleting docker network ${1}"
  docker network rm "${1}" 2>/dev/null || true
}

# Creates the Docker networks used with the tests.
function net_up() {
  net_create "${DOCKER_NET_1}"
  net_create "${DOCKER_NET_2}"
  net_create "${DOCKER_NET_3}"

  # Store the CIDR for the Docker networks.
  DOCKER_NET_1_CIDR="$(net_cidr "${DOCKER_NET_1}")"
  DOCKER_NET_2_CIDR="$(net_cidr "${DOCKER_NET_2}")"
  DOCKER_NET_3_CIDR="$(net_cidr "${DOCKER_NET_3}")"

  # Store the Gateways for the Docker networks.
  #DOCKER_NET_1_GATEWAY="$(net_cidr "${DOCKER_NET_1}")"
  DOCKER_NET_2_GATEWAY="$(net_gateway "${DOCKER_NET_2}")"
  DOCKER_NET_3_GATEWAY="$(net_gateway "${DOCKER_NET_3}")"
}

# Deletes the Docker networks used with the tests.
function net_down() {
  net_delete "${DOCKER_NET_1}"
  net_delete "${DOCKER_NET_2}"
  net_delete "${DOCKER_NET_3}"
}

# Stops the HAProxy container.
function stop_haproxy() {
  docker kill "${HAPROXY_CONTAINER}" || true
}

# Called before this program exits.
function on_exit() {
  stop_haproxy
  net_down
  [ -z "${TEMP_CONFIG:-}" ] || rm -f "${TEMP_CONFIG}"
}
trap on_exit EXIT

# Builds the HAProxy image if necessary.
function build_haproxy() {
  # If no image is specified then build it.
  if [ -z "${HAPROXY_IMAGE}" ]; then
    make build-image
    export HAPROXY_IMAGE=haproxy
  fi
}

# Starts HAProxy if it is not running.
function start_haproxy() {
  if [ -z "$(docker ps -qf "Name=${HAPROXY_CONTAINER}")" ]; then

    echo "creating haproxy container: ${HAPROXY_CONTAINER}"
    # The container is create in privileged mode to enable the use of AnyIP
    docker create \
      --name="${HAPROXY_CONTAINER}" \
      --network="${DOCKER_NET_1}" \
      --privileged \
      --rm \
      "${HAPROXY_IMAGE}"

    # Connect the two, additional networks.
    docker network connect "${DOCKER_NET_2}" "${HAPROXY_CONTAINER}"
    docker network connect "${DOCKER_NET_3}" "${HAPROXY_CONTAINER}"

    echo "starting haproxy container: ${HAPROXY_CONTAINER}"
    docker start "${HAPROXY_CONTAINER}"

    # Store the container ID.
    #HAPROXY_CONTAINER_ID="$(docker inspect --format='{{.Id}}' "${HAPROXY_CONTAINER}")"

    # Store the MAC addresses for the container for each network.
    #DOCKER_NET_1_MAC="$(net_mac_addr "${DOCKER_NET_1}")"
    DOCKER_NET_2_MAC="$(net_mac_addr "${DOCKER_NET_2}")"
    DOCKER_NET_3_MAC="$(net_mac_addr "${DOCKER_NET_3}")"
  fi
}

function test_prereqs() {
  check_dependencies

  # Build the HAProxy image if necessary.
  build_haproxy

  # Create the networks.
  net_up

  # Start HAproxy.
  start_haproxy
}

function test_anyiproutectl() {
  test_prereqs

  # Run anyiproutectl.sh with an empty config file and expect no errors.
  docker exec -it "${HAPROXY_CONTAINER}" /var/lib/vmware/anyiproutectl.sh up

  # Get the AnyIP ranges for the Docker networks.
  DOCKER_NET_1_ANYIP_CIDR_1="${DOCKER_NET_1_CIDR%.*/*}.128/25"
  DOCKER_NET_2_ANYIP_CIDR_1="${DOCKER_NET_2_CIDR%.*/*}.128/25"
  DOCKER_NET_3_ANYIP_CIDR_1="${DOCKER_NET_3_CIDR%.*/*}.128/25"

  # Create the config file.
  TEMP_CONFIG=".$(date "+%s")"
  cat <<EOF >"${TEMP_CONFIG}"
${DOCKER_NET_1_ANYIP_CIDR_1}
${DOCKER_NET_2_ANYIP_CIDR_1}
EOF

  # Copy the config file to the container.
  docker cp "${TEMP_CONFIG}" "${HAPROXY_CONTAINER}":/etc/vmware/anyip-routes.cfg

  # Run the program with a populated config file and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" /var/lib/vmware/anyiproutectl.sh up

  # Run the program with a populated config file again and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" /var/lib/vmware/anyiproutectl.sh up

  # Define a random IP address in each of the AnyIP ranges.
  ANYIP_IP_1="${DOCKER_NET_1_ANYIP_CIDR_1%.*/*}.$(shuf -i 128-254 -n 1)"
  ANYIP_IP_2="${DOCKER_NET_2_ANYIP_CIDR_1%.*/*}.$(shuf -i 128-254 -n 1)"
  ANYIP_IP_3="${DOCKER_NET_3_ANYIP_CIDR_1%.*/*}.$(shuf -i 128-254 -n 1)"

  # Ping each of the IP addresses and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" ping -c2 "${ANYIP_IP_1}"
  docker exec "${HAPROXY_CONTAINER}" ping -c2 "${ANYIP_IP_2}"

  # Disable the AnyIP routes and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" /var/lib/vmware/anyiproutectl.sh down

  # Disable the AnyIP routes again and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" /var/lib/vmware/anyiproutectl.sh down

  # Ping each of the IP addresses and expect an error for each one.
  ! docker exec "${HAPROXY_CONTAINER}" ping -c2 -W1 "${ANYIP_IP_1}" || return "${?}"
  ! docker exec "${HAPROXY_CONTAINER}" ping -c2 -W1 "${ANYIP_IP_2}" || return "${?}"

  # Watch the config file for changes.
  docker exec --env "DOCKER_NET_3_ANYIP_CIDR_1=${DOCKER_NET_3_ANYIP_CIDR_1}" \
    -t "${HAPROXY_CONTAINER}" \
    sh -c '( /var/lib/vmware/anyiproutectl.sh watch & ) && sleep 2 && echo "${DOCKER_NET_3_ANYIP_CIDR_1}" >>/etc/vmware/anyip-routes.cfg && sleep 2'

  # Ping each the new IP address and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" ping -c2 "${ANYIP_IP_3}"
}

function test_routetablectl() {
  test_prereqs

  # Run routetablectl.sh with an empty config file and expect no errors.
  docker exec -it "${HAPROXY_CONTAINER}" /var/lib/vmware/routetablectl.sh up

  # Create the config file.
  #   <TableID>,<TableName>,<MACAddress>,<NetworkCIDR>,<Gateway4>
  TEMP_CONFIG=".$(date "+%s")"
  cat <<EOF >"${TEMP_CONFIG}"
2,frontend,${DOCKER_NET_2_MAC},${DOCKER_NET_2_CIDR},${DOCKER_NET_2_GATEWAY}
3,workload,${DOCKER_NET_3_MAC},${DOCKER_NET_3_CIDR},${DOCKER_NET_3_GATEWAY}
EOF

  # Copy the config file to the container.
  docker cp "${TEMP_CONFIG}" "${HAPROXY_CONTAINER}":/etc/vmware/route-tables.cfg

  # Run the program with a populated config file and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" /var/lib/vmware/routetablectl.sh up

  # Assert the file /etc/iproute2/rt_tables has the expected tables in it.
  docker exec "${HAPROXY_CONTAINER}" grep $'2\trtctl_frontend' /etc/iproute2/rt_tables
  docker exec "${HAPROXY_CONTAINER}" grep $'3\trtctl_workload' /etc/iproute2/rt_tables

  # Assert the expected IP rules exist.
  docker exec "${HAPROXY_CONTAINER}" sh -c 'ip rule | grep rtctl_frontend'
  docker exec "${HAPROXY_CONTAINER}" sh -c 'ip rule | grep rtctl_workload'

  # Assert the expected default gateways exist.
  docker exec "${HAPROXY_CONTAINER}" sh -c 'ip route show table rtctl_frontend | grep default'
  docker exec "${HAPROXY_CONTAINER}" sh -c 'ip route show table rtctl_workload | grep default'

  # Disable the routes and expect no errors.
  docker exec "${HAPROXY_CONTAINER}" /var/lib/vmware/routetablectl.sh down

  # Assert the file /etc/iproute2/rt_tables DOES NOT have the expected tables in it.
  ! docker exec "${HAPROXY_CONTAINER}" grep $'2\trtctl_frontend' /etc/iproute2/rt_tables || return "${?}"
  ! docker exec "${HAPROXY_CONTAINER}" grep $'3\trtctl_workload' /etc/iproute2/rt_tables || return "${?}"

  # Assert the expected IP rules  DO NOT exist.
  ! docker exec "${HAPROXY_CONTAINER}" sh -c 'ip rule | grep rtctl_frontend' || return "${?}"
  ! docker exec "${HAPROXY_CONTAINER}" sh -c 'ip rule | grep rtctl_workload' || return "${?}"

  # Assert the expected default gateways DO NOT exist.
  ! docker exec "${HAPROXY_CONTAINER}" sh -c 'ip route show table rtctl_frontend | grep default' || return "${?}"
  ! docker exec "${HAPROXY_CONTAINER}" sh -c 'ip route show table rtctl_workload | grep default' || return "${?}"
}

################################################################################
##                                   main
################################################################################

# Parse the command-line arguments.
while getopts ":har" opt; do
  case ${opt} in
    h)
      fatal "${USAGE}"
      ;;
    a)
      test_anyiproutectl
      exit "${?}"
      ;;
    r)
      test_routetablectl
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
