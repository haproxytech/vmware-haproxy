#!/bin/bash
set -x

# Network post-configuration actions that should be run on every boot should be appended here
# Used by net-postconfig systemd service

route_table_cfg_file="/etc/vmware/route-tables.cfg"

# Appends an entry to the route-table service's config file.
# Input values:
# - 1 Routing Table ID
# - 2 Routing Table Name = Network/Interface Name
# - 3 Interface MAC
# - 4 Gateway IP (If unset, assumes acquired using DHCP)
writeRouteTableConfig() {
    id="${1}"
    network="${2}"
    mac="${3}"
    gateway="${4}"
    if [ "${gateway}" == "" ] || [ "${gateway}" == "null" ]; then
        # Assume DHCP. Get it from DHCP lease file.
        ifindex=$(cat "/sys/class/net/${network}/ifindex")
        gateway=$(grep ROUTER "/var/run/systemd/netif/leases/${ifindex}" | cut -d= -f2)
        if [ "${gateway}" == "" ] || [ "${gateway}" == "null" ]; then
            return 0
        fi
    fi
    ip=$(ip -4 address show "${network}" | grep 'scope global' | awk '{print $2}')
    # Set default gateway route if not already set in route-tables.cfg.
    default_gw_route="${id},${network},${mac},${ip},${gateway}"
    if ! grep -Fxq "$default_gw_route" "$route_table_cfg_file"; then
        echo "$default_gw_route" >> "$route_table_cfg_file"
    fi

    # Set linked scope route if not already set in route-tables.cfg.
    linked_scoped_route="${id},${network},${mac},${ip}"
    if ! grep -Fxq "$linked_scoped_route" "$route_table_cfg_file"; then
        echo "$linked_scoped_route" >> "$route_table_cfg_file"
    fi
}
