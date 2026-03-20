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
# You can safely re-run — existing products are skipped.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[seed]${NC} $*"; }
success() { echo -e "${GREEN}[seed]${NC} $*"; }
die()     { echo -e "${YELLOW}[seed] ERROR:${NC} $*" >&2; exit 1; }

# ── Load .env for DB credentials ──────────────────────────────────────────────
ENV_FILE="/opt/fashion-pos/.env"
if [ -f "${ENV_FILE}" ]; then
    # Export only the variables we need (avoid exporting everything blindly)
    DB_USER=$(grep -E "^DB_USER=" "${ENV_FILE}"     | cut -d= -f2- | tr -d '"' || echo "odoo")
    DB_PASSWORD=$(grep -E "^DB_PASSWORD=" "${ENV_FILE}" | cut -d= -f2- | tr -d '"' || echo "")
    DB_NAME=$(grep -E "^DB_NAME=" "${ENV_FILE}"     | cut -d= -f2- | tr -d '"' || echo "fashion_gambia")
else
    DB_USER="${DB_USER:-odoo}"
    DB_PASSWORD="${DB_PASSWORD:-}"
    DB_NAME="${DB_NAME:-fashion_gambia}"
fi

# Python snippet that calls the hook inside odoo-bin shell
SEED_PY="
import logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s %(name)s: %(message)s')
from odoo.addons.fashion_pos.hooks import post_init_hook
post_init_hook(env)
env.cr.commit()
print('\n[seed] Catalogue seeded successfully.')
"

# ── Docker path ───────────────────────────────────────────────────────────────
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "odoo"; then
    CONTAINER=$(docker ps --format '{{.Names}}' | grep odoo | head -1)
    info "Container : ${CONTAINER}"
    info "Database  : ${DB_NAME}"
    info "DB host   : fashion_db (inter-container)"
    info "Seeding catalogue — this may take 1-2 minutes…"
    echo ""

    # Pass DB connection explicitly so odoo shell can reach fashion_db container
    docker exec -i "${CONTAINER}" \
        python3 /usr/bin/odoo shell \
            --config=/etc/odoo/odoo.conf \
            --db_host=db \
            --db_port=5432 \
            --db_user="${DB_USER}" \
            --db_password="${DB_PASSWORD}" \
            --database="${DB_NAME}" \
            --no-http \
            --stop-after-init \
        <<< "${SEED_PY}"

    echo ""
    success "Done! Open your POS — products are ready."
    success "Print barcodes: Inventory → Products → select all → Print Labels."
    exit 0
fi

# ── Bare-metal / non-Docker path ──────────────────────────────────────────────
ODOO_BIN="${ODOO_BIN:-$(command -v odoo 2>/dev/null || echo /usr/bin/odoo)}"
ODOO_CONF="${ODOO_CONF:-/etc/odoo/odoo.conf}"

info "Odoo bin : ${ODOO_BIN}"
info "Config   : ${ODOO_CONF}"
info "Seeding catalogue — this may take 1-2 minutes…"
echo ""

python3 "${ODOO_BIN}" shell \
    --config "${ODOO_CONF}" \
    --database "${DB_NAME}" \
    --no-http \
    --stop-after-init \
    <<< "${SEED_PY}"

echo ""
success "Done! Open your POS — products are ready."
success "Print barcodes: Inventory → Products → select all → Print Labels."
