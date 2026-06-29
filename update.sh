#!/bin/sh
# ============================================================================
# Autologin Auto-Update Script
# ============================================================================

set -e

BASE_URL="https://raw.githubusercontent.com/creativy24/portal/main"
WORKER_URL="https://autologin.creativy24.workers.dev"

log_info() { echo "[UPDATE] $1"; }

LICENSE_KEY=$(cat /usr/lib/autologin/.license_key 2>/dev/null)
FINGERPRINT=$(cat /usr/lib/autologin/.fingerprint 2>/dev/null)
[ -z "$LICENSE_KEY" ] || [ -z "$FINGERPRINT" ] && exit 1

RESPONSE=$(curl -sSL -X POST "$WORKER_URL/validate" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"request_type\": \"refresh\"}" 2>/dev/null)

SUCCESS=$(echo "$RESPONSE" | grep -o '"success":true' || true)
[ -z "$SUCCESS" ] && exit 1

DECRYPTION_KEY=$(echo "$RESPONSE" | grep -o '"decryption_key":"[^"]*"' | cut -d'"' -f4)

log_info "Memulai update framework..."
declare -A MAP=(
    ["99-autologin"]="/etc/hotplug.d/iface/99-autologin"
    ["autologin_init"]="/etc/init.d/autologin"
    ["autologin_bin"]="/usr/bin/autologin"
    ["autologin.lua"]="/usr/lib/lua/luci/controller/autologin.lua"
    ["auto_timezone.sh"]="/usr/lib/autologin/auto_timezone.sh"
    ["daemon.sh"]="/usr/lib/autologin/daemon.sh"
    ["health_check.sh"]="/usr/lib/autologin/health_check.sh"
    ["logging.sh"]="/usr/lib/autologin/logging.sh"
    ["login_executor.sh"]="/usr/lib/autologin/login_executor.sh"
    ["mac_apply.sh"]="/usr/lib/autologin/mac_apply.sh"
    ["mac_spoof.sh"]="/usr/lib/autologin/mac_spoof.sh"
    ["telegram_notify.sh"]="/usr/lib/autologin/telegram_notify.sh"
    ["update_json.lua"]="/usr/lib/autologin/update_json.lua"
    ["backend_hosts.conf"]="/usr/lib/autologin/captive-detect/backend_hosts.conf"
    ["detection.conf"]="/usr/lib/autologin/captive-detect/detection.conf"
    ["endpoints.conf"]="/usr/lib/autologin/captive-detect/endpoints.conf"
    ["portal.json"]="/usr/lib/autologin/captive-detect/portal.json"
    ["autologin.css"]="/www/luci-static/resources/autologin.css"
)
for gh_file in "${!MAP[@]}"; do
    curl -sSL "${BASE_URL}/framework/${gh_file}" -o "${MAP[$gh_file]}" 2>/dev/null || true
    chmod 0755 "${MAP[$gh_file]}"
done

log_info "Memulai update payload premium..."
declare -A PAYLOAD_MAP=(
    ["index.htm"]="/usr/lib/lua/luci/view/autologin/index.htm"
    ["common.sh"]="/usr/lib/autologin/common.sh"
    ["anti_blocking.sh"]="/usr/lib/autologin/anti_blocking.sh"
    ["routing_lib.sh"]="/usr/lib/autologin/routing_lib.sh"
    ["hotspot_mikrotik.sh"]="/usr/lib/autologin/captive-detect/handlers/hotspot_mikrotik.sh"
    ["wifi_id_classic.sh"]="/usr/lib/autologin/captive-detect/handlers/wifi_id_classic.sh"
    ["wifi_id_nextjs.sh"]="/usr/lib/autologin/captive-detect/handlers/wifi_id_nextjs.sh"
    ["wms.sh"]="/usr/lib/autologin/captive-detect/handlers/wms.sh"
    ["autologin.js"]="/www/luci-static/resources/autologin.js"
    ["donate.png"]="/www/luci-static/resources/donate.png"
    ["logout.sh"]="/usr/lib/autologin/logout.sh"
)
for file in "${!PAYLOAD_MAP[@]}"; do
    target="${PAYLOAD_MAP[$file]}"
    curl -sSL "${BASE_URL}/payload/${file}.enc" -o "/tmp/${file}.enc" 2>/dev/null || continue
    openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "/tmp/${file}.enc" -out "$target" \
        -pass pass:"$DECRYPTION_KEY" 2>/dev/null || continue
    chmod 0755 "$target"
    rm -f "/tmp/${file}.enc"
done

REMOTE_VERSION=$(curl -sSL "${BASE_URL}/version.txt" 2>/dev/null || echo "1.0.0")
echo "$REMOTE_VERSION" > /usr/lib/autologin/.version

log_info "Update selesai. Restarting services..."
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache /tmp/luci-* 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/autologin restart 2>/dev/null || true
