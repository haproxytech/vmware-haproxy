# A Guide to Virtual IP management in the HAProxy Appliance

## Summary

HAProxy setups are often configured to load-balance traffic on a single endpoint, optionally using a floating IP in a Highly Available configuration.

This HAProxy appliance is designed to allow HAProxy to load balance traffic across a range of Virtual IPs (VIP). This uses a capability of Linux called AnyIP which allows the appliance to respond to all IP addresses within specified ranges.

## How does AnyIP work?

AnyIP works using the local routing table in Linux, defining Virtual IPs the appliance can use. You can view the routing table with the following command:

```
ip route list table local
```
By adding an entry to the routing table containing an IP range in CIDR notation assigned to the loopback inteface, the appliance will immediately start responding to all IPs in the range. You can experiment with this in a Linux VM using:

```
ip route add local <range> dev lo
ping <IP in the range>
```
Removing the range is achieved by:

```
ip route delete local <range>
```
Note that these examples are purely for illustration. You don't have to manually configure the routing tables in the appliance. That's is managed for you (see below).

## How do I configure VIP ranges in the appliance?

When you deploy the appliance, it will ask you for one or more VIP ranges which it was then persist in a configuration file `/etc/vmware/anyip-routes.cfg`. The appliance will then automatically ensure that the local routing table in the appliance is kept in sync with this file, which is does using a simple utility `/var/lib/vmware/anyiproutectl.sh`.

Once the appliance is up and running, you can test that the AnyIP is working by pinging IP addresses in the configured VIP ranges. You can do this from within the appliance or outside. It should respond to all of them.

If you want to extend the VIP ranges of the appliance, you can modify the `/etc/vmware/anyip-routes.cfg` file and that will automatically update the routing tables. However, please note that the control plane managing the configuration of the HAProxy instance *also* has to be told that it can allocate IPs out of this new range.

## What precautions do I need to consider?

You need to be careful using AnyIP because the appliance will immediately respond to *every* IP in the range. That means that anything else on the network that has been assigned an IP in that range could be impacted.

It also means that you cannot assume that just because a VIP is pingable, that HAProxy has a frontend configured and defined for it. The way to test that HAProxy is serving traffic is to use a utility like `curl`.

Note that HAProxy itself has no knowledge of the AnyIP configuration. The external control plane responsible for IP Address management updates HAProxy frontend configurations and therefore needs to know the IP range that the appliance has been configured with. This is why in vSphere with Tanzu Workload Managment configuration, it askes for an IP range it can use for assigning VIPs for load-balanced Kubernetes Services.

## Troubleshooting

AnyIP is a fairly simple concept, so there's not too many things to check

1. Check that you can ping VIPs from a shell within the appliance
2. Ensure that the VIP ranges you want are in `/etc/vmware/anyip-routes.cfg` and there are no typos
3. Check that the VIP ranges you want are present in the local routing table.
```
ip route list table local
# you should see an entry that looks like this:
local 192.168.20.128/25 dev lo scope host
```
4. Make sure that DHCP is not assigning IP addresses in the same range
5. Make sure that `/var/lib/vmware/anyiproutectl.sh` is running and watching the file
```
ps -ef | grep anyiproutectl
root      1076     1  0 Nov19 ?        00:00:00 /bin/bash /var/lib/vmware/anyiproutectl.sh watch
```
6. Make sure that the configuration on the control plane managing HAProxy frontends agrees with the configuration in the appliance. In the case of vSphere with Tanzu Workload Enablement, it's the field marked "IP Address Ranges for Virtual Servers" (see https://youtu.be/wfYDDbBJHfM?t=1947). The ranges in here should be the same or a subset of the ranges in `/etc/vmware/anyip-routes.cfg`.