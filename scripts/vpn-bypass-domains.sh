#!/usr/bin/env bash
# VPN Domain Bypass - Resolve domains and add routes via physical gateway
# Used by init-openvpn-config and up.sh to bypass VPN for specific domains

# shellcheck source=/scripts/logging.sh
source /scripts/logging.sh

# Function to add bypass routes for domains
# Args: $1 = comma-separated list of domains
add_bypass_routes() {
    local domains="$1"
    
    if [ -z "${domains}" ]; then
        return 0
    fi
    
    # Find the physical gateway, explicitly excluding tun0
    local gw
    local intf
    gw="$(ip route list match 0.0.0.0/0 | awk '$5 != "tun0" {print $3; exit}')"
    intf="$(ip route list match 0.0.0.0/0 | awk '$5 != "tun0" {print $5; exit}')"
    
    if [ -z "${gw}" ] || [ -z "${intf}" ]; then
        log "[OpenVPN] vpn-bypass-domains: could not determine physical gateway, skipping bypass routes"
        return 0
    fi
    
    # Process each domain
    IFS=',' read -ra domain_array <<< "${domains}"
    for domain in "${domain_array[@]}"; do
        # Trim whitespace
        domain="$(echo "${domain}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')"
        [ -n "${domain}" ] || continue
        
        log "[OpenVPN] resolving bypass domain: ${domain}"
        
        # Resolve domain to IPv4 addresses only
        # getent ahosts returns multiple lines per IP (STREAM, DGRAM, RAW)
        # We use awk to get unique IPs and grep to filter IPv4 only
        local ips
        ips="$(getent ahosts "${domain}" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)"
        
        if [ -z "${ips}" ]; then
            log "[OpenVPN] WARNING: failed to resolve ${domain}, skipping"
            continue
        fi
        
        # Add route for each resolved IP
        while IFS= read -r ip; do
            [ -n "${ip}" ] || continue
            
            # Check if route already exists
            if ip route show "${ip}/32" 2>/dev/null | grep -q "${ip}"; then
                debug_log "[OpenVPN] bypass route already exists: ${ip} (${domain})"
            else
                log "[OpenVPN] bypass route: ${ip} via ${gw} dev ${intf} (${domain})"
                ip route add "${ip}/32" via "${gw}" dev "${intf}" 2>/dev/null || true
            fi
        done <<< "${ips}"
    done
}

# If script is executed directly (not sourced), run the function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    add_bypass_routes "${OPENVPN_BYPASS_DOMAINS:-}"
fi
