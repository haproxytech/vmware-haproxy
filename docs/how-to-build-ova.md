# Building the Appliance

This page describes how to build the appliance OVA.

## Requirements

Building the OVA requires:

* VMware Fusion or Workstation
* Packer 1.4.1
* Ansible 2.8+

## Build the OVA

To build the OVA please run the following the command:

```shell
export PATH=/Applications/VMware\ Fusion.app/Contents/Library/:$PATH  ## add `vmware-vdiskmanager` to path
make build-ova
```

The above command build the OVA with Packer in _headless_ mode, meaning that VMware Fusion/Workstation will not display the virtual machine (VM) as it is being built. If the build process fails or times out, please use the following command to build the OVA in the foreground:

```shell
export PATH=/Applications/VMware\ Fusion.app/Contents/Library/:$PATH  ## add `vmware-vdiskmanager` to path
FOREGROUND=1 make build-ova
```

Once the OVA is built, it should be located at `./output/ova/haproxy.ova` and be around `500MiB`.
