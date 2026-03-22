#!/usr/bin/env bash
# =============================================================================
# Fashion Shop POS — Enable HTTPS on VPN (self-signed certificate)
# =============================================================================
# Generates a self-signed TLS certificate for 10.0.0.1 and reconfigures
# Nginx to serve the POS over HTTPS. Clients on VPN will see a browser
# warning on first visit (expected for self-signed) — click "Advanced →
# Proceed" once and the browser will remember it.
#
# Usage:
#   sudo bash /opt/fashion-pos/deploy/enable-https.sh
#
# To revert to HTTP:
#   sudo cp /etc/nginx/sites-available/fashion-pos-http \
#            /etc/nginx/sites-enabled/fashion-pos
#   sudo nginx -s reload
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

REPO_DIR="${REPO_DIR:-/opt/fashion-pos}"
VPN_IP="10.0.0.1"
CERT_DIR="/etc/nginx/ssl/fashion-pos"
CERT_FILE="${CERT_DIR}/cert.pem"
KEY_FILE="${CERT_DIR}/key.pem"

[[ $EUID -ne 0 ]] && die "Run as root: sudo bash deploy/enable-https.sh"
command -v openssl &>/dev/null || { apt-get install -y -qq openssl; }

echo -e "\n${BOLD}${CYAN}==================================${NC}"
echo -e "${BOLD}${CYAN}  Fashion POS — Enable HTTPS      ${NC}"
echo -e "${BOLD}${CYAN}==================================${NC}\n"

# =============================================================================
# STEP 1 — Generate self-signed certificate (valid 10 years)
# =============================================================================
info "Step 1/3 — Generating self-signed TLS certificate for ${VPN_IP}..."
mkdir -p "${CERT_DIR}"
chmod 700 "${CERT_DIR}"

openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "/CN=${VPN_IP}/O=Fashion Shop POS/C=GM" \
    -addext "subjectAltName=IP:${VPN_IP}" \
    2>/dev/null

chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"
success "Certificate created (valid 10 years): ${CERT_FILE}"

# =============================================================================
# STEP 2 — Install HTTPS Nginx config
# =============================================================================
info "Step 2/3 — Installing HTTPS Nginx configuration..."

# Back up the current HTTP config
cp /etc/nginx/sites-available/fashion-pos \
   /etc/nginx/sites-available/fashion-pos-http 2>/dev/null || true

# Install HTTPS config
cp "${REPO_DIR}/deploy/nginx-https.conf" /etc/nginx/sites-available/fashion-pos

nginx -t || die "Nginx config test failed — check ${REPO_DIR}/deploy/nginx-https.conf"
systemctl reload nginx
success "Nginx reloaded with HTTPS."

# =============================================================================
# STEP 3 — Update UFW to allow HTTPS from VPN
# =============================================================================
info "Step 3/3 — Opening HTTPS port on firewall..."
ufw allow in on wg0 to any port 443 proto tcp 2>/dev/null || true
success "Port 443 allowed from VPN."

echo ""
echo -e "${BOLD}${GREEN}HTTPS enabled!${NC}"
echo ""
echo -e "${BOLD}Access the POS:${NC}"
echo -e "  URL:  ${CYAN}https://10.0.0.1${NC}  (VPN required)"
echo ""
echo -e "${YELLOW}First visit:${NC} Your browser will warn about the self-signed certificate."
echo -e "Click ${BOLD}Advanced → Proceed to 10.0.0.1${NC} — this only happens once."
echo ""
echo -e "${BOLD}To install certificate on devices (optional — removes browser warning):${NC}"
echo -e "  Copy ${CYAN}${CERT_FILE}${NC} to the device and add to trusted certificates."
echo ""
echo -e "${BOLD}To revert to HTTP:${NC}"
echo -e "  ${CYAN}sudo cp /etc/nginx/sites-available/fashion-pos-http /etc/nginx/sites-enabled/fashion-pos${NC}"
echo -e "  ${CYAN}sudo nginx -s reload${NC}"
echo ""
