#!/usr/bin/env bash
# =============================================================================
# Fashion POS — Seed Product Catalogue
# =============================================================================
# Run this ONCE on an already-running Fashion POS installation to load:
#   • POS screen categories (Tops, Bottoms, Dresses, Shoes, Accessories, Underwear, SALE)
#   • 25 pre-built product templates with size + colour variants
#   • EAN-13 barcodes on every variant (ready to print and scan)
#   • A "Buy 3+ items → 10% off" loyalty promotion
#
# Usage (run from the server):
#   bash /opt/fashion-pos/deploy/seed_catalogue.sh
#
# You can safely re-run this script — existing products are skipped.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[seed]${NC} $*"; }
success() { echo -e "${GREEN}[seed]${NC} $*"; }
warn()    { echo -e "${YELLOW}[seed]${NC} $*"; }

# ── Detect environment ────────────────────────────────────────────────────────
ODOO_BIN="${ODOO_BIN:-/opt/fashion-pos/odoo-bin}"
ODOO_CONF="${ODOO_CONF:-/etc/odoo/odoo.conf}"

# If running inside Docker, delegate to the container
if [ -f /proc/1/cgroup ] && grep -qE "docker|containerd" /proc/1/cgroup 2>/dev/null; then
    # Already inside container — run directly
    :
elif command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "odoo"; then
    CONTAINER=$(docker ps --format '{{.Names}}' | grep odoo | head -1)
    info "Detected Docker container: ${CONTAINER}"
    info "Running seed inside container…"
    docker exec -i "${CONTAINER}" bash /opt/odoo/deploy/seed_catalogue.sh
    exit $?
fi

# ── Resolve database name ─────────────────────────────────────────────────────
if [ -f "${ODOO_CONF}" ]; then
    DB_NAME=$(grep -E "^db_name\s*=" "${ODOO_CONF}" | awk -F'=' '{print $2}' | tr -d ' ')
fi
DB_NAME="${DB_NAME:-${ODOO_DB:-fashion_pos}}"

info "Database : ${DB_NAME}"
info "Odoo bin : ${ODOO_BIN}"
info "Config   : ${ODOO_CONF}"
echo ""

# ── Run the seed via odoo-bin shell ──────────────────────────────────────────
info "Seeding catalogue — this may take 1-2 minutes…"

python3 "${ODOO_BIN}" shell \
    --config "${ODOO_CONF}" \
    --database "${DB_NAME}" \
    --no-http \
    --stop-after-init <<'PYTHON'
import logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s %(name)s: %(message)s')

from odoo.addons.fashion_pos.hooks import post_init_hook
post_init_hook(env)
env.cr.commit()
print("\n✓ Catalogue seeded successfully.")
PYTHON

echo ""
success "Done! Open your POS and the products will be ready."
success "Tip: To print barcodes → Inventory → Products → select all fashion products → Print Labels."
