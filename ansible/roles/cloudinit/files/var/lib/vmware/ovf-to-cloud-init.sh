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

set -e
set -x

# The path to the Data Plane API configuration file.
data_plane_api_cfg=/etc/haproxy/dataplaneapi.cfg

# These PCI slots are hard-coded in the OVF config
# This is the reliable way of determining which network is which
# Link files are used so that prescriptive naming behavior can
# be given to udevd. This keeps systemd-networkd from racing during
# early discovery/initialization of these devices.
# management_pci="0000:03:00.0" 160 eth0
# workload_pci="0000:0b:00.0" 192 eth1
# frontend_pci="0000:13:00.0" 224 eth2

# These keys are hardcoded to match the data from OVF config
hostname_key="network.hostname"
management_ip_key="network.management_ip"
workload_ip_key="network.workload_ip"
frontend_ip_key="network.frontend_ip"
management_gw_key="network.management_gateway"
workload_gw_key="network.workload_gateway"
frontend_gw_key="network.frontend_gateway"

# These are the display names for the nics
management_net_name="management"
workload_net_name="workload"
frontend_net_name="frontend"

# The script persists the encoded userdata and metadata to the filesystem
# This is both for post-mortem analysis and so that they can be refreshed on boot
encoded_userdata_path="/var/lib/vmware/encoded_userdata.txt"
encoded_metadata_path="/var/lib/vmware/encoded_metadata.txt"

ca_crt_path="/etc/haproxy/ca.crt"
ca_key_path="/etc/haproxy/ca.key"
anyip_cfg_path="/etc/vmware/anyip-routes.cfg"
net_postconfig_path="/var/lib/vmware/net-postconfig.sh"
first_boot_path="/var/lib/vmware/.ovf_to_cloud_init.done"

# Ensure that metadata exists in guestinfo for correct networking
# On first boot, the persisted metadata is written. On subsequent boots, it is read.
ensureMetadata () {
    if [ "$(ovf-rpctool get metadata)" == "" ]; then
        if [ -f "$encoded_metadata_path" ]; then
            encoded_metadata=$(cat $encoded_metadata_path)
            ovf-rpctool set metadata "$encoded_metadata"
            ovf-rpctool set metadata.encoding "base64"
        else
            echo "Error: Metadata is missing from $encoded_metadata_path"
        fi
    fi
}

# If there is no ovfenv, there's nothing to process
checkForExistingOvfenv () {
    val=$(ovf-rpctool get ovfenv)
    if [ "$val" == "" ]; then
        echo "Exiting due to no ovfenv to process"
        return 1
    fi
}

# Need to ensure that special characters are properly escaped for Sed, including forward slashes
# Input arg is string to escape
escapeString () {
    escaped=$(printf "%q" "$1" | sed 's/\//\\\//g')
    echo "$escaped"
}

# Persist a string to a file
# Input values:
# - The string to write
# - The file to write to
# - The permissions to set
writeCertFile () {
    echo "$1" > "$2"
    formatCertificate "$2"
    chmod "$3" "$2"
}

getRootPwd () {
    val=$(ovf-rpctool get.ovf appliance.root_pwd)
    salt=$(openssl passwd -1 -salt SaltSalt "$val")
    escapeString "$salt"
}

bindSSHToIP() {
    sed -i -e 's/#ListenAddress 0.0.0.0/ListenAddress '"${1}"'/' /etc/ssh/sshd_config
    echo "SSH is now bound to IP address ${1}"
}

bindDataPlaneAPIToIP() {
    sed -i -e 's/TLS_HOST=0.0.0.0/TLS_HOST='"${1}"'/' "${data_plane_api_cfg}"
    echo "Data Plane API is now bound to IP address ${1}"
}

bindServicesToManagementIP() {
    ip=$(ovf-rpctool get.ovf "$management_ip_key")
    if [ "$ip" == "" ] || [ "$ip" == "null" ]; then
        echo "management IP must be static" 1>&2
        return 1
    else
        ip="${ip%/*}"
        echo "binding SSH and Data Plane API to the management IP address ${ip}"
        bindSSHToIP "${ip}"
        bindDataPlaneAPIToIP "${ip}"
    fi
}

setDataPlaneAPIPort() {
    port=$(ovf-rpctool get.ovf "loadbalance.dataplane_port")
    if [ "${port}" == "" ] || [ "${port}" == "0" ] || [ "${port}" == "null" ]; then
        port=5556
    fi
    sed -i -e 's/TLS_PORT=5556/TLS_PORT='"${port}"'/' "${data_plane_api_cfg}"
    echo "Data Plane API port set to ${port}"
}

setHAProxyUserPass() {
    user="$(ovf-rpctool get.ovf "loadbalance.haproxy_user")"
    pass="$(ovf-rpctool get.ovf "loadbalance.haproxy_pwd")"
    if [ "${user}" == "" ] || [ "${user}" == "null" ]; then
        user="admin"
    fi
    if [ "${pass}" == "" ] || [ "${pass}" == "null" ]; then
        pass="haproxy"
    fi
    pass="$(openssl passwd -1 "${pass}")"
    sed -i -e '/^userlist controller/a\  \user '"${user}"' password '"${pass}"'' /etc/haproxy/haproxy.cfg
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

# Returns the FQDN for the host.
getHostFQDN() {
    host_fqdn=$(ovf-rpctool get.ovf "${hostname_key}")
    if [ "${host_fqdn}" == "" ] || [ "${host_fqdn}" == "null" ]; then
        host_fqdn="haproxy.local"
    fi
    echo "${host_fqdn}"
}

permitRootViaSSH() {
    permit_root_login=$(ovf-rpctool get.ovf appliance.permit_root_login)
    # Force a lower-case comparison since the value is True on vCenter and true
    # when coming from ESX.
    if [ "${permit_root_login,,}" == "true" ]; then
        permit_root_login="yes"
    else
        permit_root_login="no"
    fi
    sed -i -e '/^PermitRootLogin/s/^.*$/PermitRootLogin '"${permit_root_login}"'/' /etc/ssh/sshd_config
}

# Produces the necessary metadata config for an interface
# Input values:
# - interface name
# - mac address
# - static IP (CIDR notation)
# If static IP is not defined, DHCP is assumed
getNetworkInterfaceYamlConfig () {
    cfg1="        $1:\n            match:\n                macaddress: $2\n            wakeonlan: true\n"
    cfg2=""
    if [ "$3" == "" ] || [ "$3" == "null" ]; then
        cfg2="            dhcp4: true"
    else
        cfg2="            dhcp4: false\n            addresses:\n            - "$3
    fi
    echo "$cfg1$cfg2"
}

# Given a network, find the mac address associated with it
getMacForNetwork () {
    if [ ! -f "/sys/class/net/$1/address" ]; then
        return 1
    fi
    cat "/sys/class/net/$1/address"
}

# Writes out the config for the management network
getManagementNetworkConfig () {
    mac=$(getMacForNetwork "$management_net_name")
    ip=$(ovf-rpctool get.ovf "$management_ip_key")
    config="$(getNetworkInterfaceYamlConfig "$management_net_name" "$mac" "$ip")"
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
    mac=$(getMacForNetwork "$workload_net_name")
    ip=$(ovf-rpctool get.ovf "$workload_ip_key")
    echo -e "$(escapeString "$(getNetworkInterfaceYamlConfig "$workload_net_name" "$mac" "$ip")")"
}

# Writes out the config for the frontend network
# Note that this is conditional on there being a third network device that is
# the device connected to the frontend network.
# If there is no third device, then this function returns gracefully with a
# successful return code.
getFrontendNetworkConfig () {
    if ! mac=$(getMacForNetwork "$frontend_net_name"); then
        return 0
    fi
    ip=$(ovf-rpctool get.ovf "$frontend_ip_key")
    echo -e "$(escapeString "$(getNetworkInterfaceYamlConfig "$frontend_net_name" "$mac" "$ip")")"
}

# Get all values from OVF and insert them into the userdata template
publishUserdata () {
    encoded_userdata=$(sed \
    -e 's/ROOT_PWD_FROM_OVFENV/'"$(getRootPwd)"'/' \
    -e 's/CREATE_DEFAULT_CA/'"$(getCreateDefaultCA)"'/' \
    userdata.txt | base64)

    echo "$encoded_userdata" > "$encoded_userdata_path"
    ovf-rpctool set userdata "$encoded_userdata"
    ovf-rpctool set userdata.encoding "base64"
}

# Generate entries for cloud-init metadata and append them to the template
publishMetadata () {
    encoded_metadata=$(sed \
    -e 's/HOSTNAME/'"$(getHostFQDN)"'/' \
    -e 's/MGMT_CONFIG/'"$(getManagementNetworkConfig)"'/' \
    -e 's/WORKLOAD_CONFIG/'"$(getWorkloadNetworkConfig)"'/' \
    -e 's/FRONTEND_CONFIG/'"$(getFrontendNetworkConfig)"'/' \
    metadata.txt | base64)

    echo "$encoded_metadata" > "$encoded_metadata_path"
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
        writeCertFile "$ca_cert" "$ca_crt_path" "644"
        writeCertFile "$ca_cert_key" "$ca_key_path" "644"
    fi
}

# Persist service CIDRs to a configuration file that's picked up by the anyip-routes service
writeAnyipConfig () {
    cidrs=$(ovf-rpctool get.ovf "loadbalance.service_ip_range")
    if [ "$cidrs" != "" ]; then
        echo -e "${cidrs//,/\\n}" >> "$anyip_cfg_path"
    fi
}

# If a network is DHCP, remove the default gateway for it
# Input values:
# - OVF key for the network IP
# - Interface name
disableDefaultRoute () {
    ip=$(ovf-rpctool get.ovf "$1")
    if [ "$ip" == "" ] || [ "$ip" == "null" ]; then
        echo "ip route del \$(ip route list | grep -E \"default.*$2.*dhcp\" | cut -d ' ' -f 1-5)" >>"${net_postconfig_path}"
    fi
}

# Appends an entry to the route-table service's config file if a gateway was
# specified for this network.
# Input values:
# - 1 Table ID
# - 2 Table Name
# - 3 IP Key
# - 4 Gateway Key
writeRouteTableConfig() {
    id="${1}"
    gateway=$(ovf-rpctool get.ovf "${4}")
    if [ "${gateway}" == "" ] || [ "${gateway}" == "null" ]; then
        return 0
    fi
    network="${2}"
    mac=$(getMacForNetwork "$network")
    ip=$(ovf-rpctool get.ovf "${3}")
    if [ "$ip" != "" ] && [ "$ip" != "null" ]; then
        echo "${id},${network},${mac},${ip},${gateway}" >> "/etc/vmware/route-tables.cfg"
    fi
}

# Write network postconfig actions to the script run by the net-postconfig service
writeNetPostConfig () {
    disableDefaultRoute "${workload_ip_key}" "${workload_net_name}"
    writeRouteTableConfig 2 "${workload_net_name}" "${workload_ip_key}" "${workload_gw_key}"
    if getMacForNetwork "${frontend_net_name}"; then
        disableDefaultRoute "${frontend_ip_key}" "${frontend_net_name}"
        writeRouteTableConfig 3 "${frontend_net_name}" "${frontend_ip_key}" "${frontend_gw_key}"
    fi
}

if [ ! -f "$first_boot_path" ]; then
    checkForExistingOvfenv      # Exit if there is no ovfenv to process
    touch "$first_boot_path"
    publishUserdata
    publishMetadata
    permitRootViaSSH
    bindServicesToManagementIP
    setHAProxyUserPass
    setDataPlaneAPIPort
    writeCAfiles
    writeAnyipConfig
    writeRouteTableConfig
    writeNetPostConfig
else
    ensureMetadata
fi
