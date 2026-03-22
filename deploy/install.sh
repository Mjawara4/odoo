#!/usr/bin/env bash
# =============================================================================
# Fashion Shop POS — Idempotent VPS Installer
# =============================================================================
# Replaces setup.sh for safe deployments. Can be re-run without wiping data.
#
# Usage (fresh VPS):
#   git clone -b claude/customize-pos-fashion-3k0pn \
#       https://github.com/Mjawara4/odoo /opt/fashion-pos \
#   && bash /opt/fashion-pos/deploy/install.sh
#
# Re-running on an existing install: safe — data is never wiped.
# To update module code after changes, use:  bash deploy/update.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

REPO_DIR="${REPO_DIR:-/opt/fashion-pos}"
DB_NAME="fashion_gambia"
DB_USER="odoo"
VPN_SUBNET="10.0.0"
VPN_SERVER_IP="${VPN_SUBNET}.1"
VPN_PORT="51820"

[[ $EUID -ne 0 ]] && die "Run as root: sudo bash deploy/install.sh"

echo -e "\n${BOLD}${CYAN}==============================${NC}"
echo -e "${BOLD}${CYAN}  Fashion POS — Installer     ${NC}"
echo -e "${BOLD}${CYAN}==============================${NC}\n"

# =============================================================================
# STEP 1 — System update
# =============================================================================
info "Step 1/11 — Updating system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip gnupg2 ca-certificates \
    lsb-release apt-transport-https software-properties-common \
    ufw fail2ban
success "System updated."

# =============================================================================
# STEP 2 — Swap (prevents OOM crashes on low-RAM VPS)
# =============================================================================
info "Step 2/11 — Checking swap..."
if [[ $(swapon --show | wc -l) -eq 0 ]]; then
    info "No swap found — creating 2 GB swapfile..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    # Tune swappiness: only use swap under real memory pressure
    echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf -q
    success "2 GB swap created."
else
    success "Swap already configured — skipping."
fi

# =============================================================================
# STEP 3 — Docker & Docker Compose
# =============================================================================
info "Step 3/11 — Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    success "Docker installed."
else
    success "Docker already installed — skipping."
fi

if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin
fi
success "Docker Compose ready."

# =============================================================================
# STEP 4 — Clone / update the repo
# =============================================================================
info "Step 4/11 — Setting up code repository at ${REPO_DIR}..."
if [[ -d "${REPO_DIR}/.git" ]]; then
    git -C "${REPO_DIR}" pull origin claude/customize-pos-fashion-3k0pn --ff-only
    success "Repository updated."
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    if [[ -f "${PARENT_DIR}/docker-compose.yml" ]]; then
        info "Detected local repo at ${PARENT_DIR} — linking to ${REPO_DIR}"
        ln -sfn "${PARENT_DIR}" "${REPO_DIR}"
        success "Repository linked."
    else
        git clone -b claude/customize-pos-fashion-3k0pn \
            https://github.com/Mjawara4/odoo "${REPO_DIR}"
        success "Repository cloned."
    fi
fi

# =============================================================================
# STEP 5 — Generate .env file with secrets
# =============================================================================
info "Step 5/11 — Generating secure configuration..."
ENV_FILE="${REPO_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    warn ".env already exists — keeping existing passwords. Add TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID if needed."
else
    DB_PASS=$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 32 || true)
    cat > "${ENV_FILE}" <<EOF
# Fashion POS — Environment Configuration
# KEEP THIS FILE SECRET — never commit it to git

DB_USER=${DB_USER}
DB_PASSWORD="${DB_PASS}"
DB_NAME=${DB_NAME}

# Optional: Telegram alerting for health checks
# Get token from @BotFather, chat_id from @userinfobot
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
EOF
    chmod 600 "${ENV_FILE}"
    success ".env created with a strong random password."
fi

# =============================================================================
# STEP 6 — WireGuard VPN
# =============================================================================
info "Step 6/11 — Setting up WireGuard VPN..."
bash "${REPO_DIR}/deploy/wireguard.sh"
success "WireGuard VPN configured."

# =============================================================================
# STEP 7 — Build image and start database
# =============================================================================
info "Step 7/11 — Building image and starting database..."
cd "${REPO_DIR}"

# SAFE: only stop containers (never -v which would wipe the database)
docker compose down --remove-orphans 2>/dev/null || true
docker compose build --quiet
docker compose up -d db
success "Database container started."

info "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
    if docker compose exec -T db pg_isready -U "${DB_USER}" -q 2>/dev/null; then
        success "PostgreSQL is ready."
        break
    fi
    sleep 2
    [[ $i -eq 30 ]] && warn "PostgreSQL not ready after 60s, trying anyway..."
done

# =============================================================================
# STEP 8 — Install fashion_pos module (skipped if DB already initialised)
# =============================================================================
info "Step 8/11 — Installing fashion_pos module..."
source "${ENV_FILE}"

# Check if DB already exists and has Odoo tables
DB_EXISTS=$(docker compose exec -T db \
    psql -U "${DB_USER}" -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null || echo "")
TABLES_EXIST=""
if [[ "${DB_EXISTS}" == "1" ]]; then
    TABLES_EXIST=$(docker compose exec -T db \
        psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
        "SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module' LIMIT 1" 2>/dev/null || echo "")
fi

if [[ "${TABLES_EXIST}" == "1" ]]; then
    warn "Database already initialised — skipping --init. Use 'bash deploy/update.sh' to upgrade the module."
else
    # Resolve the built image name
    ODOO_IMAGE=""
    for candidate in "fashion-pos-odoo" "fashion_pos-odoo" "fashionpos-odoo"; do
        if docker image inspect "${candidate}" &>/dev/null; then
            ODOO_IMAGE="${candidate}"
            break
        fi
    done
    [[ -n "${ODOO_IMAGE}" ]] || die "Could not find built Odoo image. Run: docker images | grep odoo"
    info "Using image: ${ODOO_IMAGE}"
    info "Running Odoo database initialisation (this takes 5-10 minutes)..."

    set +e
    docker run --rm \
        --network fashion_internal \
        -v "${REPO_DIR}/addons/fashion_pos:/mnt/extra-addons/fashion_pos:ro" \
        -v "${REPO_DIR}/deploy/odoo.conf:/etc/odoo/odoo.conf:ro" \
        -e HOST="fashion_db" -e PORT=5432 \
        -e USER="${DB_USER}" -e PASSWORD="${DB_PASSWORD}" \
        "${ODOO_IMAGE}" \
        odoo \
        --logfile=/dev/stdout --log-level=info \
        --db_host=fashion_db --db_port=5432 \
        --db_user="${DB_USER}" --db_password="${DB_PASSWORD}" \
        --database="${DB_NAME}" \
        --init=fashion_pos --without-demo=all --stop-after-init \
        2>&1 | tee /tmp/odoo-init.log
    INIT_RC=${PIPESTATUS[0]}
    set -e
    [[ ${INIT_RC} -eq 0 ]] || die "Odoo init failed (exit ${INIT_RC}) — see /tmp/odoo-init.log"
    success "fashion_pos module installed."
fi

docker compose up -d
success "All services started."

# =============================================================================
# STEP 9 — Nginx reverse proxy (VPN-only)
# =============================================================================
info "Step 9/11 — Configuring Nginx..."
apt-get install -y -qq nginx
cp "${REPO_DIR}/deploy/nginx.conf" /etc/nginx/sites-available/fashion-pos
ln -sf /etc/nginx/sites-available/fashion-pos /etc/nginx/sites-enabled/fashion-pos
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx && systemctl enable nginx
success "Nginx configured — POS accessible at http://10.0.0.1 (VPN required)"

# =============================================================================
# STEP 10 — Automated daily database backups
# =============================================================================
info "Step 10/11 — Setting up daily database backups..."
BACKUP_DIR="/opt/fashion-pos-backups"
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

cat > /etc/cron.daily/fashion-pos-backup <<'CRON'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="/opt/fashion-pos-backups"
REPO_DIR="/opt/fashion-pos"
source "${REPO_DIR}/.env"
DATE=$(date +%Y-%m-%d_%H-%M)
BACKUP_FILE="${BACKUP_DIR}/fashion_gambia_${DATE}.dump"
docker compose -f "${REPO_DIR}/docker-compose.yml" exec -T db \
    pg_dump -U "${DB_USER}" "${DB_NAME}" -Fc > "${BACKUP_FILE}"
find "${BACKUP_DIR}" -name "*.dump" -mtime +30 -delete
echo "Backup completed: ${BACKUP_FILE}"
CRON
chmod +x /etc/cron.daily/fashion-pos-backup
success "Daily backups configured → ${BACKUP_DIR}"

# =============================================================================
# STEP 11 — Health check cron + firewall
# =============================================================================
info "Step 11/11 — Configuring health monitoring and firewall..."

# Install health check cron (every 5 minutes)
cp "${REPO_DIR}/deploy/healthcheck.sh" /usr/local/bin/fashion-pos-healthcheck
chmod +x /usr/local/bin/fashion-pos-healthcheck
# Add to cron if not already there
if ! crontab -l 2>/dev/null | grep -q fashion-pos-healthcheck; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/fashion-pos-healthcheck") | crontab -
fi
success "Health check cron installed (every 5 minutes)."

# Firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow "${VPN_PORT}/udp"
ufw allow in on wg0 to any port 80 proto tcp
ufw --force enable
success "Firewall configured."

systemctl enable --now fail2ban
success "fail2ban enabled."

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades
success "Automatic security updates enabled."

# =============================================================================
# DONE
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
echo -e "${BOLD}Optional next steps:${NC}"
echo -e "  • Add Telegram alerts: edit ${YELLOW}${ENV_FILE}${NC} → set TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID"
echo -e "  • Enable HTTPS:        ${CYAN}sudo bash ${REPO_DIR}/deploy/enable-https.sh${NC}"
echo -e "  • Add VPN clients:     ${CYAN}sudo bash ${REPO_DIR}/deploy/add_vpn_client.sh <device-name>${NC}"
echo ""
echo -e "${BOLD}Useful commands:${NC}"
echo -e "  Update module:  ${CYAN}bash ${REPO_DIR}/deploy/update.sh${NC}"
echo -e "  View logs:      ${CYAN}docker compose -f ${REPO_DIR}/docker-compose.yml logs -f odoo${NC}"
echo -e "  Run backup:     ${CYAN}bash /etc/cron.daily/fashion-pos-backup${NC}"
echo ""
echo -e "${BOLD}DB password saved in:${NC} ${YELLOW}${REPO_DIR}/.env${NC} (keep this secret!)"
echo ""
