#!/usr/bin/env bash
# =============================================================================
# Fashion Shop POS — Module Update Script
# =============================================================================
# Pull latest code and upgrade the fashion_pos module without touching data.
#
# Usage:
#   bash /opt/fashion-pos/deploy/update.sh
#
# What this does:
#   1. Pulls latest code from git
#   2. Rebuilds the Docker image
#   3. Runs odoo --update=fashion_pos (preserves all data)
#   4. Restarts the live Odoo container
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

REPO_DIR="${REPO_DIR:-/opt/fashion-pos}"
ENV_FILE="${REPO_DIR}/.env"

[[ -f "${ENV_FILE}" ]] || die "No .env found at ${ENV_FILE}. Run install.sh first."

echo -e "\n${BOLD}${CYAN}=============================${NC}"
echo -e "${BOLD}${CYAN}  Fashion POS — Update       ${NC}"
echo -e "${BOLD}${CYAN}=============================${NC}\n"

# =============================================================================
# STEP 1 — Pull latest code
# =============================================================================
info "Step 1/4 — Pulling latest code..."
if [[ -L "${REPO_DIR}" ]]; then
    # Symlinked to a local dev copy — skip git pull
    ACTUAL_DIR=$(readlink -f "${REPO_DIR}")
    info "Repo is a symlink to ${ACTUAL_DIR} — skipping git pull."
else
    git -C "${REPO_DIR}" pull origin claude/customize-pos-fashion-3k0pn --ff-only
fi
success "Code up to date."

# =============================================================================
# STEP 2 — Rebuild Docker image
# =============================================================================
info "Step 2/4 — Rebuilding Docker image..."
cd "${REPO_DIR}"
docker compose build --quiet
success "Image rebuilt."

# =============================================================================
# STEP 3 — Run module upgrade (--update preserves all data)
# =============================================================================
info "Step 3/4 — Upgrading fashion_pos module..."
source "${ENV_FILE}"

# Ensure db is running
docker compose up -d db
info "Waiting for PostgreSQL..."
for i in $(seq 1 15); do
    docker compose exec -T db pg_isready -U "${DB_USER}" -q 2>/dev/null && break
    sleep 2
    [[ $i -eq 15 ]] && die "PostgreSQL not ready."
done

# Resolve image name
ODOO_IMAGE=""
for candidate in "fashion-pos-odoo" "fashion_pos-odoo" "fashionpos-odoo"; do
    if docker image inspect "${candidate}" &>/dev/null; then
        ODOO_IMAGE="${candidate}"
        break
    fi
done
[[ -n "${ODOO_IMAGE}" ]] || die "Could not find built Odoo image. Run: docker images | grep odoo"

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
    --update=fashion_pos --without-demo=all --stop-after-init \
    2>&1 | tee /tmp/odoo-update.log
UPDATE_RC=${PIPESTATUS[0]}
set -e
[[ ${UPDATE_RC} -eq 0 ]] || die "Module upgrade failed (exit ${UPDATE_RC}) — see /tmp/odoo-update.log"
success "fashion_pos module upgraded."

# =============================================================================
# STEP 4 — Restart live Odoo container
# =============================================================================
info "Step 4/4 — Restarting Odoo..."
docker compose restart odoo
success "Odoo restarted."

echo ""
echo -e "${BOLD}${GREEN}Update complete!${NC}"
echo -e "  View logs: ${CYAN}docker compose -f ${REPO_DIR}/docker-compose.yml logs -f odoo${NC}"
echo ""
