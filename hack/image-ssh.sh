#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################################################################################
# usage: image-ssh.sh BUILD_DIR [SSH_USER]
#  This program uses SSH to connect to an image running locally in VMware
#  Workstation or VMware Fusion.
################################################################################

set -o errexit
set -o nounset
set -o pipefail

if [ "${#}" -lt "1" ]; then
  echo "usage: ${0} BUILD_DIR [SSH_USER]" 1>&2
  exit 1
fi

VM_RUN="${VM_RUN:-$(command -v vmrun 2>/dev/null)}"
if [ ! -e "${VM_RUN}" ] || [ ! -x "${VM_RUN}" ]; then
  echo "vmrun must be in \$PATH or specified by \$VM_RUN" 1>&2
  exit 1
fi
VM_RUN_DIR="$(dirname "${VM_RUN}")"
export PATH="${VM_RUN_DIR}:${PATH}"

# Get the path of the VMX file.
VMX_FILE=$(/bin/ls "${1-}"/*.vmx)

# Get the SSH user.
SSH_USER="${SSH_USER:-${2-}}"
SSH_USER="${SSH_USER:-capv}"

# Get the VM's IP address.
IP_ADDR="$(vmrun getGuestIPAddress "${VMX_FILE}")"

# SSH into the VM with the provided user.
SSH_KEY="$(dirname "${BASH_SOURCE[0]}")/../example/id_rsa"
echo "image-ssh: ssh -i ${SSH_KEY} ${SSH_USER}@${IP_ADDR}"
exec ssh -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}" "${SSH_USER}"@"${IP_ADDR}"
