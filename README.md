# VMware + HAProxy

This project enables customers to build an OSS virtual appliance with HAProxy and its [Data Plane API](https://www.haproxy.com/documentation/dataplaneapi/latest) designed to enable Kubernetes workload management with Project Pacific on vSphere 7.

* [Download](#download)
* [Deploy](#deploy)
* [Build](#build)
* [Test](#test)
* [Upgrade](#upgrade)

## Download

The latest version of the appliance OVA is always available from the [releases](https://github.com/haproxytech/vmware-haproxy/releases) page:

### NOTE
If running on or upgrading to vSphere 7.0.1 or later, you _must_ upgrade to version v0.1.9 or later.

| Version | SHA256 |
|---|---|
| [v0.2.0](https://cdn.haproxy.com/download/haproxy/vsphere/ova/haproxy-v0.2.0.ova) | `07fa35338297c591f26b6c32fb6ebcb91275e36c677086824f3fd39d9b24fb09` |
| [v0.1.10](https://cdn.haproxy.com/download/haproxy/vsphere/ova/haproxy-v0.1.10.ova) | `81f2233b3de75141110a7036db2adabe4d087c2a6272c4e03e2924bff3dccc33` |
| [v0.1.9](https://cdn.haproxy.com/download/haproxy/vsphere/ova/haproxy-v0.1.9.ova) | `f3d0c88e7181af01b2b3e6a318ae03a77ffb0e1949ef16b2e39179dc827c305a` |
| [v0.1.8](https://cdn.haproxy.com/download/haproxy/vsphere/ova/vmware-haproxy-v0.1.8.ova) | `eac73c1207c05aeeece6d17dd1ac1dde0e557d94812f19082751cfb6925ad082` |

## Deploy

Refer to the [system requirements](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-C86B9028-2701-40FE-BA05-519486E010F4.html) and the [installation documentation](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-5673269F-C147-485B-8706-65E4A87EB7F0.html).

For a tutorial on deploying and using the HAProxy load balancer in vSphere with Tanzu, check out the [vSphere with Tanzu Quick Start Guide](https://core.vmware.com/resource/vsphere-tanzu-quick-start-guide).

## Build

Documentation on how to build the appliance is available [here](./docs/how-to-build-ova.md).

## Test

Documentation on how to test the components in the appliance with Docker containers is available [here](./docs/how-to-container.md).

## Configure

Documentation on how to configure the Virtual IPs managed by the appliance is available [here](./docs/virtual-ip-config.md).

## Upgrade

Documentation on recommended upgrade procedures can be found [here](./docs/upgrade.md).

