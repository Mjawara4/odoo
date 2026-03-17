#!/usr/bin/env bash
# =============================================================================
# Add a Staff Device to the WireGuard VPN
# =============================================================================
# Usage:
#   sudo bash deploy/add_vpn_client.sh <device-name>
#
# Examples:
#   sudo bash deploy/add_vpn_client.sh cashier1-tablet
#   sudo bash deploy/add_vpn_client.sh manager-phone
#   sudo bash deploy/add_vpn_client.sh backoffice-laptop
#
# This script will:
#   1. Generate a key pair for the device
#   2. Assign the next available IP (10.0.0.X)
#   3. Add the device as a peer to the WireGuard server
#   4. Print a config the user copies to their device
#   5. Print a QR code they can scan with the WireGuard mobile app
# =============================================================================

set -euo pipefail

DEVICE_NAME="${1:-}"
[[ -z "${DEVICE_NAME}" ]] && { echo "Usage: $0 <device-name>"; exit 1; }

VPN_SUBNET="10.0.0"
VPN_SERVER_IP="${VPN_SUBNET}.1"
VPN_PORT="51820"
DNS_SERVER="1.1.1.1"          # Cloudflare DNS — change if you have a local DNS
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENTS_DIR="${WG_DIR}/clients"

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo $0 $*"; exit 1; }

mkdir -p "${CLIENTS_DIR}"

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ ! -f "${WG_DIR}/server_public.key" ]] && {
    echo "WireGuard server not set up. Run deploy/wireguard.sh first."
    exit 1
}

SERVER_PUBLIC_KEY=$(cat "${WG_DIR}/server_public.key")
SERVER_PUBLIC_IP=$(curl -4sf https://api.ipify.org 2>/dev/null || echo "YOUR_VPS_IP")

# ── Find next available IP ────────────────────────────────────────────────────
USED_IPS=$(grep -h "AllowedIPs" "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null \
           | grep -oP "10\.0\.0\.\K[0-9]+" || true)
NEXT_IP=2
for ip in $(seq 2 254); do
    if ! echo "${USED_IPS}" | grep -q "^${ip}$"; then
        NEXT_IP=$ip
        break
    fi
done
CLIENT_IP="${VPN_SUBNET}.${NEXT_IP}"

# ── Generate client keys ──────────────────────────────────────────────────────
CLIENT_DIR="${CLIENTS_DIR}/${DEVICE_NAME}"
mkdir -p "${CLIENT_DIR}"
chmod 700 "${CLIENT_DIR}"

wg genkey | tee "${CLIENT_DIR}/private.key" | wg pubkey > "${CLIENT_DIR}/public.key"
chmod 600 "${CLIENT_DIR}/private.key"

CLIENT_PRIVATE_KEY=$(cat "${CLIENT_DIR}/private.key")
CLIENT_PUBLIC_KEY=$(cat "${CLIENT_DIR}/public.key")

# ── Write the client config file ─────────────────────────────────────────────
CLIENT_CONF="${CLIENT_DIR}/wg-${DEVICE_NAME}.conf"
cat > "${CLIENT_CONF}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address    = ${CLIENT_IP}/24
DNS        = ${DNS_SERVER}

[Peer]
PublicKey  = ${SERVER_PUBLIC_KEY}
Endpoint   = ${SERVER_PUBLIC_IP}:${VPN_PORT}
# AllowedIPs = 0.0.0.0/0   ← full tunnel (all traffic through VPN)
# AllowedIPs = 10.0.0.0/24 ← split tunnel (only POS traffic through VPN) ← recommended
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF
chmod 600 "${CLIENT_CONF}"

# ── Register device as a peer on the server ──────────────────────────────────
# Add to live WireGuard (takes effect immediately, no restart needed)
wg set "${WG_INTERFACE}" peer "${CLIENT_PUBLIC_KEY}" allowed-ips "${CLIENT_IP}/32"

# Also persist to the config file so it survives a server reboot
cat >> "${WG_DIR}/${WG_INTERFACE}.conf" <<EOF

# Peer: ${DEVICE_NAME}  (added $(date +%Y-%m-%d))
[Peer]
PublicKey  = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF

# ── Print the config ──────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  VPN config for: ${DEVICE_NAME}"
echo "  Assigned IP:    ${CLIENT_IP}"
echo "============================================================"
echo ""
cat "${CLIENT_CONF}"
echo ""
echo "------------------------------------------------------------"
echo "  QR Code (scan with WireGuard mobile app):"
echo "------------------------------------------------------------"

# Print QR code if qrencode is available
if command -v qrencode &>/dev/null; then
    qrencode -t ANSIUTF8 < "${CLIENT_CONF}"
else
    apt-get install -y -qq qrencode &>/dev/null
    qrencode -t ANSIUTF8 < "${CLIENT_CONF}"
fi

echo ""
echo "------------------------------------------------------------"
echo "  Config file saved to: ${CLIENT_CONF}"
echo "  Copy it to the device or scan the QR code above."
echo ""
echo "  How to install WireGuard on devices:"
echo "    Android/iOS : Install 'WireGuard' app → scan QR code"
echo "    Windows     : Download from wireguard.com → import .conf file"
echo "    Linux       : sudo apt install wireguard → cp ${CLIENT_CONF} /etc/wireguard/"
echo ""
echo "  After connecting, open the POS at: http://10.0.0.1"
echo "------------------------------------------------------------"
