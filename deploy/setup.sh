#!/usr/bin/env bash
# =============================================================================
# Fashion Shop POS — One-command VPS Setup
# =============================================================================
# Run this ONCE on a fresh Ubuntu 22.04 VPS.  SSH in as root, then paste:
#
#   git clone -b claude/customize-pos-fashion-3k0pn \
#       https://github.com/Mjawara4/odoo /opt/fashion-pos \
#   && bash /opt/fashion-pos/deploy/setup.sh
#
# That single command clones your repo and fully deploys the Fashion POS.
#
# What this script does:
#   1. Updates the system
#   2. Installs Docker + Docker Compose
#   3. Installs WireGuard VPN
#   4. Installs Nginx
#   5. Creates a secure .env file (generates a strong DB password)
#   6. Starts Odoo + PostgreSQL in Docker
#   7. Installs the fashion_pos module automatically
#   8. Configures Nginx as reverse proxy (VPN-only access)
#   9. Sets up automatic daily database backups
#  10. Sets up automatic security updates
# =============================================================================

set -euo pipefail

# ── Colour output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────────
REPO_DIR="${REPO_DIR:-/opt/fashion-pos}"
DB_NAME="fashion_gambia"
DB_USER="odoo"
SHOP_NAME="Fashion Shop"
VPN_SUBNET="10.0.0"          # VPN range: 10.0.0.0/24
VPN_SERVER_IP="${VPN_SUBNET}.1"
VPN_PORT="51820"

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Run as root: sudo bash deploy/setup.sh"

echo -e "\n${BOLD}${CYAN}==============================${NC}"
echo -e "${BOLD}${CYAN}  Fashion POS — VPS Setup     ${NC}"
echo -e "${BOLD}${CYAN}==============================${NC}\n"

# =============================================================================
# STEP 1 — System update
# =============================================================================
info "Step 1/10 — Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip gnupg2 ca-certificates \
    lsb-release apt-transport-https software-properties-common \
    ufw fail2ban
success "System updated."

# =============================================================================
# STEP 2 — Docker & Docker Compose
# =============================================================================
info "Step 2/10 — Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    success "Docker installed."
else
    success "Docker already installed — skipping."
fi

if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin
fi
success "Docker Compose ready."

# =============================================================================
# STEP 3 — Clone / update the repo
# =============================================================================
info "Step 3/10 — Setting up code repository at ${REPO_DIR}..."
if [[ -d "${REPO_DIR}/.git" ]]; then
    git -C "${REPO_DIR}" pull origin claude/customize-pos-fashion-3k0pn --ff-only
    success "Repository updated."
else
    # If running from inside the repo already, just symlink
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    if [[ -f "${PARENT_DIR}/docker-compose.yml" ]]; then
        info "Detected local repo at ${PARENT_DIR} — creating symlink to ${REPO_DIR}"
        ln -sfn "${PARENT_DIR}" "${REPO_DIR}"
        success "Repository linked."
    else
        # Fresh VPS — clone the repo automatically
        info "Cloning repository from GitHub..."
        git clone -b claude/customize-pos-fashion-3k0pn \
            https://github.com/Mjawara4/odoo "${REPO_DIR}"
        success "Repository cloned."
    fi
fi

# =============================================================================
# STEP 4 — Generate .env file with secrets
# =============================================================================
info "Step 4/10 — Generating secure configuration..."
ENV_FILE="${REPO_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    warn ".env already exists — keeping existing passwords."
else
    # Generate a random 32-char password
    DB_PASS=$(tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c 32)
    cat > "${ENV_FILE}" <<EOF
# Fashion POS — Environment Configuration
# KEEP THIS FILE SECRET — never commit it to git

DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}
DB_NAME=${DB_NAME}
EOF
    chmod 600 "${ENV_FILE}"
    success ".env created with a strong random password."
fi

# =============================================================================
# STEP 5 — WireGuard VPN
# =============================================================================
info "Step 5/10 — Setting up WireGuard VPN..."
bash "${REPO_DIR}/deploy/wireguard.sh"
success "WireGuard VPN configured."

# =============================================================================
# STEP 6 — Start Odoo + PostgreSQL
# =============================================================================
info "Step 6/10 — Building and starting Docker containers..."
cd "${REPO_DIR}"
docker compose down --remove-orphans 2>/dev/null || true
docker compose build --quiet
docker compose up -d
success "Containers started."

# Wait for Odoo to be ready
info "Waiting for Odoo to initialise (up to 3 minutes)..."
for i in $(seq 1 36); do
    if docker compose exec -T odoo curl -sf http://localhost:8069/web/database/selector &>/dev/null; then
        break
    fi
    sleep 5
done

# =============================================================================
# STEP 7 — Install fashion_pos module
# =============================================================================
info "Step 7/10 — Installing fashion_pos module and setting up database..."
source "${ENV_FILE}"
docker compose exec -T odoo odoo \
    --config=/etc/odoo/odoo.conf \
    --db_host=db \
    --db_user="${DB_USER}" \
    --db_password="${DB_PASSWORD}" \
    --database="${DB_NAME}" \
    --init=fashion_pos \
    --without-demo=all \
    --stop-after-init
success "fashion_pos module installed."

# Restart Odoo in server mode after init
docker compose up -d
success "Odoo restarted."

# =============================================================================
# STEP 8 — Nginx reverse proxy (VPN-only)
# =============================================================================
info "Step 8/10 — Configuring Nginx..."
apt-get install -y -qq nginx
cp "${REPO_DIR}/deploy/nginx.conf" /etc/nginx/sites-available/fashion-pos
ln -sf /etc/nginx/sites-available/fashion-pos /etc/nginx/sites-enabled/fashion-pos
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx && systemctl enable nginx
success "Nginx configured — POS accessible on VPN at http://10.0.0.1"

# =============================================================================
# STEP 9 — Automated daily database backups
# =============================================================================
info "Step 9/10 — Setting up daily database backups..."
BACKUP_DIR="/opt/fashion-pos-backups"
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

cat > /etc/cron.daily/fashion-pos-backup <<'CRON'
#!/usr/bin/env bash
# Daily Odoo database backup — keeps last 30 days
set -euo pipefail
BACKUP_DIR="/opt/fashion-pos-backups"
REPO_DIR="/opt/fashion-pos"
source "${REPO_DIR}/.env"
DATE=$(date +%Y-%m-%d_%H-%M)
BACKUP_FILE="${BACKUP_DIR}/fashion_gambia_${DATE}.dump"

docker compose -f "${REPO_DIR}/docker-compose.yml" exec -T db \
    pg_dump -U "${DB_USER}" "${DB_NAME}" -Fc > "${BACKUP_FILE}"

# Remove backups older than 30 days
find "${BACKUP_DIR}" -name "*.dump" -mtime +30 -delete

echo "Backup completed: ${BACKUP_FILE}"
CRON
chmod +x /etc/cron.daily/fashion-pos-backup
success "Daily backups configured → ${BACKUP_DIR}"

# =============================================================================
# STEP 10 — Firewall & security hardening
# =============================================================================
info "Step 10/10 — Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh                       # keep SSH access
ufw allow "${VPN_PORT}/udp"         # WireGuard VPN
# Odoo is ONLY accessible on the VPN interface — no public HTTP/HTTPS
# Nginx listens only on 10.0.0.1 (set in nginx.conf)
ufw --force enable
success "Firewall configured."

# Enable fail2ban to block brute-force SSH attacks
systemctl enable --now fail2ban
success "fail2ban enabled."

# Auto security updates
apt-get install -y -qq unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades
success "Automatic security updates enabled."

# =============================================================================
# DONE — Print summary
# =============================================================================
source "${ENV_FILE}"

echo ""
echo -e "${BOLD}${GREEN}============================================${NC}"
echo -e "${BOLD}${GREEN}  Fashion POS deployment complete!         ${NC}"
echo -e "${BOLD}${GREEN}============================================${NC}"
echo ""
echo -e "${BOLD}Access the POS:${NC}"
echo -e "  URL:      ${CYAN}http://10.0.0.1${NC}  (VPN required)"
echo -e "  Database: ${CYAN}${DB_NAME}${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo -e "  1. Set company currency to ${YELLOW}GMD (Gambian Dalasi)${NC} in Settings → Companies"
echo -e "  2. Add staff employees with PIN codes in HR → Employees"
echo -e "  3. Set up loyalty program in POS → Configuration → Loyalty"
echo -e "  4. Configure replenishment rules: Inventory → Replenishment"
echo -e "  5. Add staff devices to VPN:"
echo -e "     ${CYAN}sudo bash ${REPO_DIR}/deploy/add_vpn_client.sh <device-name>${NC}"
echo ""
echo -e "${BOLD}Useful commands:${NC}"
echo -e "  View logs:    ${CYAN}docker compose -f ${REPO_DIR}/docker-compose.yml logs -f odoo${NC}"
echo -e "  Restart POS:  ${CYAN}docker compose -f ${REPO_DIR}/docker-compose.yml restart odoo${NC}"
echo -e "  Run backup:   ${CYAN}bash /etc/cron.daily/fashion-pos-backup${NC}"
echo ""
echo -e "${BOLD}DB password saved in:${NC} ${YELLOW}${REPO_DIR}/.env${NC} (keep this secret!)"
echo ""
