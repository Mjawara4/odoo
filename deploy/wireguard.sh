#!/usr/bin/env bash
# =============================================================================
# WireGuard VPN Setup — Fashion POS Private Network
# =============================================================================
# Creates a WireGuard server on the VPS so that:
#   - All POS devices connect to the VPN before accessing Odoo
#   - Odoo is NOT reachable from the public internet
#   - Each device (tablet, laptop, phone) gets its own VPN config file
#
# VPN subnet: 10.0.0.0/24
#   10.0.0.1  = VPS server
#   10.0.0.2  = Device 1 (add with add_vpn_client.sh)
#   10.0.0.3  = Device 2
#   ...etc
# =============================================================================

set -euo pipefail

VPN_SUBNET="10.0.0"
VPN_SERVER_IP="${VPN_SUBNET}.1"
VPN_PORT="51820"
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENTS_DIR="${WG_DIR}/clients"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[WG]${NC} $*"; }
success() { echo -e "${GREEN}[WG]${NC} $*"; }

# ── Install WireGuard ─────────────────────────────────────────────────────────
if ! command -v wg &>/dev/null; then
    info "Installing WireGuard..."
    apt-get update -qq
    apt-get install -y -qq wireguard wireguard-tools
    success "WireGuard installed."
fi

# ── Enable IP forwarding (required for VPN routing) ───────────────────────────
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p &>/dev/null
    success "IP forwarding enabled."
fi

mkdir -p "${CLIENTS_DIR}"
chmod 700 "${WG_DIR}"

# ── Generate server keys (only if not already created) ────────────────────────
SERVER_PRIVATE_KEY_FILE="${WG_DIR}/server_private.key"
SERVER_PUBLIC_KEY_FILE="${WG_DIR}/server_public.key"

if [[ ! -f "${SERVER_PRIVATE_KEY_FILE}" ]]; then
    info "Generating server key pair..."
    wg genkey | tee "${SERVER_PRIVATE_KEY_FILE}" | wg pubkey > "${SERVER_PUBLIC_KEY_FILE}"
    chmod 600 "${SERVER_PRIVATE_KEY_FILE}"
    success "Server keys generated."
else
    success "Server keys already exist — skipping."
fi

SERVER_PRIVATE_KEY=$(cat "${SERVER_PRIVATE_KEY_FILE}")
SERVER_PUBLIC_KEY=$(cat "${SERVER_PUBLIC_KEY_FILE}")

# ── Detect the main network interface ────────────────────────────────────────
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
info "Detected main network interface: ${MAIN_IFACE}"

# ── Write the WireGuard server config ────────────────────────────────────────
WG_CONF="${WG_DIR}/${WG_INTERFACE}.conf"

if [[ ! -f "${WG_CONF}" ]]; then
    info "Writing WireGuard server config..."
    cat > "${WG_CONF}" <<EOF
[Interface]
Address    = ${VPN_SERVER_IP}/24
ListenPort = ${VPN_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}

# NAT: allows VPN clients to reach the server's internal services
PostUp   = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${MAIN_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${MAIN_IFACE} -j MASQUERADE

# ── Client peers are added below by add_vpn_client.sh ──
EOF
    chmod 600 "${WG_CONF}"
    success "WireGuard server config written."
else
    success "WireGuard config already exists — skipping."
fi

# ── Enable and start WireGuard ────────────────────────────────────────────────
systemctl enable "wg-quick@${WG_INTERFACE}"
systemctl restart "wg-quick@${WG_INTERFACE}"
success "WireGuard VPN started on ${VPN_SERVER_IP}:${VPN_PORT}/udp"

# ── Store server public key for client scripts ───────────────────────────────
echo "${SERVER_PUBLIC_KEY}" > "${WG_DIR}/server_public.key"

# ── Add a management device automatically (device #2) ────────────────────────
# The owner's phone/laptop gets a config generated straight away.
if [[ ! -f "${CLIENTS_DIR}/owner.conf" ]]; then
    info "Generating VPN config for owner device..."
    bash "$(dirname "$0")/add_vpn_client.sh" owner 2>/dev/null || true
fi

# ── Get server's public IP ────────────────────────────────────────────────────
SERVER_PUBLIC_IP=$(curl -4sf https://api.ipify.org 2>/dev/null || echo "YOUR_VPS_IP")

echo ""
echo -e "${GREEN}WireGuard VPN is running!${NC}"
echo -e "  Server:    ${CYAN}${SERVER_PUBLIC_IP}:${VPN_PORT}${NC}"
echo -e "  VPN range: ${CYAN}10.0.0.0/24${NC}"
echo -e "  Config:    ${CYAN}${WG_CONF}${NC}"
echo ""
echo "Add a staff device:  sudo bash deploy/add_vpn_client.sh <name>"
echo ""
