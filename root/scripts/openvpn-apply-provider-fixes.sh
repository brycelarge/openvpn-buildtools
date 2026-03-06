#!/usr/bin/env bash
# shellcheck shell=bash
#
# Apply VPN config provider-specific fixes
# Usage: /scripts/openvpn-apply-provider-fixes.sh <config_file> [provider]
#
# This script applies provider-specific fixes to OpenVPN config files:
# - Cleans Windows line endings
# - Updates cipher settings (NordVPN)
# - Sets auth-user-pass paths
# - Provider-specific tweaks (PIA, Surfshark, etc.)

set -euo pipefail

CONFIG_FILE="${1:-}"
PROVIDER="${2:-${OPENVPN_PROVIDER:-nordvpn}}"
VPN_DIR="${VPN_DIR:-/data/config/openvpn}"

if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "Usage: $0 <config_file> [provider]" >&2
    exit 1
fi

# shellcheck source=/scripts/logging.sh
source /scripts/logging.sh 2>/dev/null || true

# Lowercase provider
provider_lc="$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')"

# Clean Windows line endings
if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$CONFIG_FILE" 2>/dev/null || true
else
    sed -i 's/\r$//' "$CONFIG_FILE" 2>/dev/null || true
fi

# Determine credentials file path
case "$provider_lc" in
    custom)
        cred_file="${VPN_DIR}/custom-openvpn-credentials.txt"
        ;;
    *)
        cred_file="${VPN_DIR}/${provider_lc}/${provider_lc}-openvpn-credentials.txt"
        ;;
esac

# Apply provider-specific fixes
case "$provider_lc" in
    nordvpn)
        # Update cipher from AES-256-CBC to AES-256-GCM
        if grep -q '^cipher AES-256-CBC' "$CONFIG_FILE" 2>/dev/null; then
            # Replace cipher line and add data-ciphers after it
            sed -i 's/^cipher AES-256-CBC$/cipher AES-256-GCM/' "$CONFIG_FILE" || true
            # Add data-ciphers line after cipher line
            sed -i '/^cipher AES-256-GCM$/a data-ciphers AES-256-GCM' "$CONFIG_FILE" || true
            debug_log "[OpenVPN] updated cipher from AES-256-CBC to AES-256-GCM" 2>/dev/null || true
        fi
        # Set auth-user-pass
        sed -i "s|^auth-user-pass.*|auth-user-pass ${cred_file}|" "$CONFIG_FILE" || true
        ;;

    surfshark)
        # Update cipher
        sed -i "s/AES-256-CBC/AES-128-GCM/g" "$CONFIG_FILE" || true
        # Set auth-user-pass
        sed -i "s|auth-user-pass.*|auth-user-pass ${cred_file}|g" "$CONFIG_FILE" || true
        ;;

    pia)
        # Set auth-user-pass
        sed -i "s|auth-user-pass.*|auth-user-pass ${cred_file}|g" "$CONFIG_FILE" || true
        # Fix CA and CRL paths
        sed -i "s|ca ca\.rsa\.\([0-9]*\)\.crt|ca ${VPN_DIR}/pia/ca.rsa.\1.crt|g" "$CONFIG_FILE" || true
        sed -i "s|crl-verify crl\.rsa\.\([0-9]*\)\.pem|crl-verify ${VPN_DIR}/pia/crl.rsa.\1.pem|g" "$CONFIG_FILE" || true
        ;;

    ipvanish|vyprvpn|protonvpn)
        # Set auth-user-pass
        sed -i "s|auth-user-pass.*|auth-user-pass ${cred_file}|g" "$CONFIG_FILE" || true
        ;;

    custom)
        # Just set auth-user-pass for custom configs
        if [ -f "$cred_file" ]; then
            sed -i "s|auth-user-pass.*|auth-user-pass ${cred_file}|g" "$CONFIG_FILE" || true
        fi
        ;;
esac

log "[OpenVPN] Applied ${provider_lc} fixes to ${CONFIG_FILE}" 2>/dev/null || true
exit 0
