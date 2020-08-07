#!/bin/bash

# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

# The path to the postconfig script.
postconfig_sh=/var/lib/vmware/net-postconfig.sh

# These PCI slots are hard-coded in the OVF config
# This is the reliable way of determining which network is which
management_pci="0000:03:00.0" # 160
workload_pci="0000:0b:00.0" # 192
frontend_pci="0000:13:00.0" # 224

# These keys are hardcoded to match the data from OVF config
management_ip_key="network.management_ip"
workload_ip_key="network.workload_ip"
frontend_ip_key="network.frontend_ip"
management_gw_key="network.management_gateway"
workload_gw_key="network.workload_gateway"
frontend_gw_key="network.frontend_gateway"

# These are the display names for the nics
management_net_name="mgmt"
workload_net_name="workload"
frontend_net_name="frontend"

# If there is existing userdata, don't attempt to process
checkForExistingUserdata () {
    val=$(ovf-rpctool get userdata)
    if [ "$val" != "" ]; then
        echo "Exiting due to existing userdata"
        return 1
    fi
}

# Need to ensure that special characters are properly escaped for Sed, including forward slashes
# Input arg is string to escape
escapeString () {
    escaped=$(printf "%q" "$1" | sed 's/\//\\\//g')
    echo "$escaped"
}

# Retrieve and escape a string from the ovfenv
# Input arg is guestinfo ovf key
getOvfStringVal () {
    val=$(ovf-rpctool get.ovf "$1")
    if [ "$val" == "" ]; then
        exit 0
    fi
    escapeString "$val"
}

# Persist a string to a file
# Input values:
# - The string to write
# - The file to write to
# - The permissions to set
writeFile () {
    echo "$1" > "$2"
    formatCertificate "$2"
    chmod "$3" "$2"
}

getRootPwd () {
    val=$(ovf-rpctool get.ovf appliance.root_pwd)
    salt=$(openssl passwd -1 -salt SaltSalt "$val")
    escapeString "$salt"
}

getPermitRootLogin () {
    val=$(ovf-rpctool get.ovf appliance.permit_root_login)
    # note ESXi client returns true, vSphere client returns True
    if [ "$val" == "true" ] || [ "$val" == "True" ] ; then
        echo "yes"
    else
        echo "no"
    fi
}

bindSSHToManagementIP() {
    sed -i -e 's/#ListenAddress 0.0.0.0/ListenAddress '"${1}"'/' /etc/ssh/sshd_config
    echo "SSH is now bound to the management IP address ${1}"
}

bindDataPlaneAPIToManagementIP() {
    sed -i -e 's/--tls-host=0.0.0.0/--tls-host='"${1}"'/' /etc/haproxy/haproxy.cfg
    echo "Data Plane API is now bound to the management IP address ${1}"
}

bindServicesToManagementIP() {
    ip=$(ovf-rpctool get.ovf "$management_ip_key")
    if [ "$ip" == "" ] || [ "$ip" == "null" ]; then
        echo "management IP must be static" 1>&2
        return 1
    else
        ip="${ip%/*}"
        echo "binding SSH and Data Plane API to the management IP address ${ip}"
        bindSSHToManagementIP "${ip}"
        bindDataPlaneAPIToManagementIP "${ip}"
    fi
}

# If the certificate is copy/pasted into OVF, \ns are turned into spaces so it needs to be formatted
# Input value is a certificate file. It is modified in place
# This should be idempotent
formatCertificate () {
    sed -i \
    -e 's/BEGIN /BEGIN_/g' \
    -e 's/PRIVATE /PRIVATE_/g' \
    -e 's/END /END_/g' \
    -e 's/ /\n/g' \
    -e 's/BEGIN_/BEGIN /g' \
    -e 's/PRIVATE_/PRIVATE /g' \
    -e 's/END_/END /g' \
    "$1"
}

# Produces the necessary metadata config for an interface
# Input values:
# - nic ID
# - interface name
# - mac address
# - static IP (CIDR notation)
# If static IP is not defined, DHCP is assumed
getNetworkInterfaceYamlConfig () {
    cfg1="        $1:\n            match:\n                macaddress: $3\n            wakeonlan: true\n"
    cfg2=""
    if [ "$4" == "" ] || [ "$4" == "null" ]; then
        cfg2="            dhcp4: true"
    else
        cfg2="            dhcp4: false\n            addresses:\n            - "$4
    fi
    echo "$cfg1$cfg2"
}

# Given one of the PCI constants above, find the network associated with it
# This will return a non-zero return code if the provided PCI constant cannot
# be found on this host.
getNetworkForPCI () {
	for name in "eth0" "eth1" "eth2"; do
		devPath=$(cd /sys/class/net/$name/device; /bin/pwd)
		pci=$(echo "$devPath" | cut -d '/' -f 6)
		if [ "$pci" == "$1" ]; then
			echo "$name"
			return 0
		fi
	done
	return 1
}

# Given a network, find the mac address associated with it
getMacForNetwork () {
	cat /sys/class/net/"$1"/address
}

# Writes out the config for the management network
getManagementNetworkConfig () {
    network=$(getNetworkForPCI "$management_pci")
    mac=$(getMacForNetwork "$network")
    ip=$(ovf-rpctool get.ovf "$management_ip_key")
    config="$(getNetworkInterfaceYamlConfig "id0" "$management_net_name" "$mac" "$ip")"
    gateway=$(ovf-rpctool get.ovf "$management_gw_key")
    if [ "$gateway" != "" ] && [ "$gateway" != "null" ]; then
        config="$config\n            gateway4: $gateway"
    fi
    nameservers=$(ovf-rpctool get.ovf network.nameservers)
    if [ "$nameservers" == "" ] || [ "$nameservers" == "null" ]; then
        nameservers="1.1.1.1, 1.0.0.1"
    fi
    config="$config\n            nameservers:"
    config="$config\n              addresses: [${nameservers}]"
    echo -e "$(escapeString "$config")"
}

# Writes out the config for the backend network
getWorkloadNetworkConfig () {
    network=$(getNetworkForPCI "$workload_pci")
    mac=$(getMacForNetwork "$network")
    ip=$(ovf-rpctool get.ovf "$workload_ip_key")
    echo -e "$(escapeString "$(getNetworkInterfaceYamlConfig "id1" "$workload_net_name" "$mac" "$ip")")"
}

# Writes out the config for the frontend network
# Note that this is conditional on there being a third network device that is
# the device connected to the frontend network.
# If there is no third device, then this function returns gracefully with a
# successful return code.
getFrontendNetworkConfig () {
    if ! network="$(getNetworkForPCI "$frontend_pci")"; then
        return 0
    fi
    mac=$(getMacForNetwork "$network")
    ip=$(ovf-rpctool get.ovf "$frontend_ip_key")
    echo -e "$(escapeString "$(getNetworkInterfaceYamlConfig "id2" "$frontend_net_name" "$mac" "$ip")")"
}

# Get all values from OVF and insert them into the userdata template
publishUserdata () {
    encoded_userdata=$(sed \
    -e 's/ROOT_PWD_FROM_OVFENV/'"$(getRootPwd)"'/' \
    -e 's/PERMIT_ROOT_LOGIN/'"$(getPermitRootLogin)"'/' \
    -e 's/HAPROXY_USER/'"$(getOvfStringVal "loadbalance.haproxy_user")"'/' \
    -e 's/HAPROXY_PWD/'"$(getOvfStringVal "loadbalance.haproxy_pwd")"'/' \
    -e 's/CREATE_DEFAULT_CA/'"$(getCreateDefaultCA)"'/' \
    -e 's/MANAGEMENT_NET_NAME/'"$management_net_name"'/' \
    userdata.txt | base64)

    echo "$encoded_userdata" > /var/lib/vmware/encoded_userdata.txt
    ovf-rpctool set userdata "$encoded_userdata"
    ovf-rpctool set userdata.encoding "base64"
}

# Generate entries for cloud-init metadata and append them to the template
publishMetadata () {
    encoded_metadata=$(sed \
    -e 's/MGMT_CONFIG/'"$(getManagementNetworkConfig)"'/' \
    -e 's/WORKLOAD_CONFIG/'"$(getWorkloadNetworkConfig)"'/' \
    -e 's/FRONTEND_CONFIG/'"$(getFrontendNetworkConfig)"'/' \
    metadata.txt | base64)

    echo "$encoded_metadata" > /var/lib/vmware/encoded_metadata.txt
    ovf-rpctool set metadata "$encoded_metadata"
    ovf-rpctool set metadata.encoding "base64"
}

# If both ca.crt and ca.key are not defined, create a default one
getCreateDefaultCA () {
    ca_cert=$(ovf-rpctool get.ovf appliance.ca_cert)
    ca_cert_key=$(ovf-rpctool get.ovf appliance.ca_cert_key)
    if [ "$ca_cert" != "" ] && [ "$ca_cert" != "null" ] && \
        [ "$ca_cert_key" != "" ] && [ "$ca_cert_key" != "null" ]; then
        echo "false"
    else
        echo "true"
    fi
}

# Don't write these to cloud-init as it's visible in the VM's guestinfo
# If either ca.crt or ca.key are missing, write out a default ca
writeCAfiles () {
    if [ "$(getCreateDefaultCA)" == "false" ]; then
        ca_cert=$(ovf-rpctool get.ovf appliance.ca_cert)
        ca_cert_key=$(ovf-rpctool get.ovf appliance.ca_cert_key)
        writeFile "$ca_cert" "/etc/haproxy/ca.crt" "644"
        writeFile "$ca_cert_key" "/etc/haproxy/ca.key" "644"
    fi
}

# Persist service CIDRs to a configuration file that's picked up by the anyip-routes service
writeAnyipConfig () {
    cidrs=$(ovf-rpctool get.ovf "loadbalance.service_ip_range")
    if [ "$cidrs" != "" ]; then
        echo -e "${cidrs//,/\\n}" >>"/etc/vmware/anyip-routes.cfg"
    fi
}

# If a network is DHCP, remove the default gateway for it
# Input values:
# - OVF key for the network IP
# - Interface name
disableDefaultRoute () {
    ip=$(ovf-rpctool get.ovf "$1")
    if [ "$ip" == "" ] || [ "$ip" == "null" ]; then
        echo "ip route del \$(ip route list | grep -E \"default.*$2.*dhcp\" | cut -d ' ' -f 1-5)" >>"${postconfig_sh}"
    fi
}

# Appends an entry to the route-table service's config file if a gateway was
# specified for this network.
# Input values:
# - 1 Table ID
# - 2 Table Name
# - 3 PCI Number
# - 4 IP Key
# - 5 Gateway Key
writeRouteTableConfig() {
    gateway=$(ovf-rpctool get.ovf "${5}")
    if [ "${gateway}" == "" ] || [ "${gateway}" == "null" ]; then
        return 0
    fi
    network=$(getNetworkForPCI "${3}")
    mac=$(getMacForNetwork "$network")
    ip=$(ovf-rpctool get.ovf "${4}")
    if [ "$ip" != "" ] && [ "$ip" != "null" ]; then
        echo "${1},${2},${mac},${ip},${gateway}" >>"/etc/vmware/route-tables.cfg"
    fi
}

# Write network postconfig actions to the script run by the net-postconfig service
writeNetPostConfig () {
    disableDefaultRoute "$workload_ip_key" "$workload_net_name"
    writeRouteTableConfig 2 workload "${workload_pci}" "${workload_ip_key}" "${workload_gw_key}"
    if getNetworkForPCI "$frontend_pci"; then
        disableDefaultRoute "$frontend_ip_key" "$frontend_net_name"
        writeRouteTableConfig 3 frontend "${frontend_pci}" "${frontend_ip_key}" "${frontend_gw_key}"
    fi
}

checkForExistingUserdata
publishUserdata
publishMetadata
bindServicesToManagementIP
writeCAfiles
writeAnyipConfig
writeRouteTableConfig
writeNetPostConfig
