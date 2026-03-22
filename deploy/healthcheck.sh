#!/usr/bin/env bash
# =============================================================================
# Fashion Shop POS — Health Check + Telegram Alerting
# =============================================================================
# Called by cron every 5 minutes (installed by install.sh).
# Checks Nginx /health endpoint → auto-restarts Odoo if down → Telegram alert.
#
# Manual run:
#   bash /opt/fashion-pos/deploy/healthcheck.sh
#
# To enable Telegram alerts, add to /opt/fashion-pos/.env:
#   TELEGRAM_BOT_TOKEN=<your-bot-token>     # from @BotFather
#   TELEGRAM_CHAT_ID=<your-chat-id>         # from @userinfobot
# =============================================================================

set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/fashion-pos}"
ENV_FILE="${REPO_DIR}/.env"
LOG="/var/log/fashion-pos-health.log"
HEALTH_URL="http://10.0.0.1/health"
LOCK_FILE="/tmp/fashion-pos-healthcheck.lock"

# Load env vars (for Telegram credentials and DB info)
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}" || true

# ── Prevent concurrent runs ───────────────────────────────────────────────────
exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0  # Another instance is running — exit quietly

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${LOG}"; }

# ── Telegram alert helper ─────────────────────────────────────────────────────
send_telegram() {
    local message="$1"
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        curl -sf \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${message}" \
            > /dev/null 2>&1 || true
    fi
}

# ── Health check ──────────────────────────────────────────────────────────────
if curl -sf --max-time 10 "${HEALTH_URL}" > /dev/null 2>&1; then
    # All good — silent exit (no log spam on success)
    exit 0
fi

# ── Odoo is down ──────────────────────────────────────────────────────────────
HOSTNAME_STR=$(hostname -f 2>/dev/null || hostname)
log "ALERT: Health check FAILED (${HEALTH_URL} unreachable)"

# Check if the container itself is running
ODOO_STATUS=$(docker inspect --format='{{.State.Status}}' fashion_odoo 2>/dev/null || echo "missing")

if [[ "${ODOO_STATUS}" != "running" ]]; then
    log "Odoo container status: ${ODOO_STATUS} — attempting restart..."
    cd "${REPO_DIR}" && docker compose up -d 2>&1 | tee -a "${LOG}"
    sleep 15

    # Re-check after restart
    if curl -sf --max-time 20 "${HEALTH_URL}" > /dev/null 2>&1; then
        log "Odoo recovered after restart."
        send_telegram "✅ Fashion POS RECOVERED on ${HOSTNAME_STR}
Container was ${ODOO_STATUS} — auto-restarted successfully."
    else
        log "ERROR: Odoo still not responding after restart."
        send_telegram "🚨 Fashion POS DOWN on ${HOSTNAME_STR}
Container restarted but still not responding.
Manual intervention required.
Check logs: docker compose -f ${REPO_DIR}/docker-compose.yml logs --tail=50 odoo"
    fi
else
    # Container is running but Nginx can't reach it (maybe Odoo is starting up)
    log "Odoo container is running but /health returned no response — may be starting up."
    send_telegram "⚠️ Fashion POS UNHEALTHY on ${HOSTNAME_STR}
Container is running but /health endpoint is unreachable.
Odoo may still be starting. Will recheck in 5 minutes."
fi
