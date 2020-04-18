#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################################################################################
# usage: image-govc-cloudinit.sh VM
#  This program updates a remote VM with the cloud-init data to ready it for
#  testing. This program requires a configured govc.
################################################################################

set -o errexit
set -o nounset
set -o pipefail

if [ "${#}" -lt "1" ]; then
  echo "usage: ${0} VM" 1>&2
  exit 1
fi

if ! command -v govc >/dev/null 2>&1; then
  echo "govc binary must be in \$PATH" 1>&2
  exit 1
fi

export GOVC_VM="${1-}"

create_snapshot() {
  snapshots="$(govc snapshot.tree)"
  if [[ ${snapshots} = *${1-}* ]]; then
    echo "image-govc-cloudinit: skip snapshot '${1-}'; already exists"
  else
    echo "image-post-cloudinit: create snapshot '${1-}'"
    vmrun snapshot "${VMX_FILE}" "${1-}"
  fi
}

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# If the VM has a "new" snapshot then revert to it and delete all other
# snapshots.
snapshots="$(govc snapshot.tree 2>/dev/null)" || true
if [[ ${snapshots} = *new* ]]; then
  echo "image-govc-cloudinit: reverting to snapshot 'new'"
  govc snapshot.revert new
  for s in ${snapshots}; do
    if [ "${s}" != "new" ] && [ "${s}" != "." ] ; then
      echo "image-govc-cloudinit: removing snapshot '${s}'"
      govc snapshot.remove "${s}"
    fi
  done
else
  echo "image-govc-cloudinit: creating snapshot 'new'"
  govc snapshot.create new
fi

echo "image-govc-cloudinit: initializing cloud-init data"
govc vm.change \
  -e "guestinfo.userdata.encoding=base64" \
  -e "guestinfo.metadata.encoding=base64" \
  -e "guestinfo.userdata='$(base64 -w0 <example/user-data)'" \
  -e "guestinfo.metadata='$(base64 -w0 <example/meta-data)'"

echo "image-govc-cloudinit: creating snapshot 'cloudinit'"
govc snapshot.create cloudinit
