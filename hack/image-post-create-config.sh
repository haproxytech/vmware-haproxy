#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################################################################################
# usage: image-post-create-config.sh BUILD_DIR
#  This program runs after a new image is created and:
#    1. Creates a snapshot of the image named "new"
#    2. Modifies the image to use 2 vCPU
#    3. Creates a snapshot of the image named "2cpu"
#    4. Attaches the ISO build/images/cloudinit/cidata.iso
################################################################################

set -o errexit
set -o nounset
set -o pipefail

if [ "${#}" -ne "1" ]; then
  echo "usage: ${0} BUILD_DIR" 1>&2
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

create_snapshot() {
  snapshots="$(vmrun listSnapshots "${VMX_FILE}" 2>/dev/null)"
  if [[ ${snapshots} = *${1-}* ]]; then
    echo "image-post-create-config: skip snapshot '${1-}'; already exists"
  else
    echo "image-post-create-config: create snapshot '${1-}'"
    vmrun snapshot "${VMX_FILE}" "${1-}"
  fi
}

create_snapshot new

if grep -q 'guestinfo.userdata' "${VMX_FILE}"; then
  echo "image-post-create-config: skipping cloud-init data; already exists"
else
  echo "image-post-create-config: insert cloud-init data"
  CIDATA_DIR="$(dirname "${BASH_SOURCE[0]}")/../example"
  cat <<EOF >>"${VMX_FILE}"
guestinfo.userdata = "$({ base64 -w0 || base64; } 2>/dev/null <"${CIDATA_DIR}/user-data")"
guestinfo.userdata.encoding = "base64"
guestinfo.metadata = "$({ base64 -w0 || base64; } 2>/dev/null <"${CIDATA_DIR}/meta-data")"
guestinfo.metadata.encoding = "base64"
EOF
  create_snapshot cloudinit
fi
