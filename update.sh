#!/bin/sh
# ============================================================================
# Autologin Auto-Update Script
# ============================================================================
set -e

BASE_URL="https://raw.githubusercontent.com/creativy24/portal/main"
WORKER_URL="https://autologin.creativy24.workers.dev"

log_info() { echo "[UPDATE] $1"; }
log_warn() { echo "[UPDATE WARN] $1"; }

LICENSE_KEY=$(cat /usr/lib/autologin/.license_key 2>/dev/null)
FINGERPRINT=$(cat /usr/lib/autologin/.fingerprint 2>/dev/null)

if [ -z "$LICENSE_KEY" ] || [ -z "$FINGERPRINT" ]; then
    log_warn "Metadata tidak ditemukan. Membatalkan update."
    exit 1
fi

log_info "Memvalidasi license untuk update..."
RESPONSE=$(curl -sSL -X POST "$WORKER_URL/validate" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"request_type\": \"refresh\"}" 2>/dev/null)

SUCCESS=$(echo "$RESPONSE" | grep -o '"success":true' || true)
if [ -z "$SUCCESS" ]; then
    log_warn "Validasi gagal. Membatalkan update."
    exit 1
fi

DECRYPTION_KEY=$(echo "$RESPONSE" | grep -o '"decryption_key":"[^"]*"' | cut -d'"' -f4)

get_framework_target() {
    case "$1" in
        99-autologin) echo "/etc/hotplug.d/iface/99-autologin" ;;
        autologin_init) echo "/etc/init.d/autologin" ;;
        autologin_bin) echo "/usr/bin/autologin" ;;
        autologin.lua) echo "/usr/lib/lua/luci/controller/autologin.lua" ;;
        auto_timezone.sh) echo "/usr/lib/autologin/auto_timezone.sh" ;;
        daemon.sh) echo "/usr/lib/autologin/daemon.sh" ;;
        health_check.sh) echo "/usr/lib/autologin/health_check.sh" ;;
        logging.sh) echo "/usr/lib/autologin/logging.sh" ;;
        login_executor.sh) echo "/usr/lib/autologin/login_executor.sh" ;;
        mac_apply.sh) echo "/usr/lib/autologin/mac_apply.sh" ;;
        mac_spoof.sh) echo "/usr/lib/autologin/mac_spoof.sh" ;;
        telegram_notify.sh) echo "/usr/lib/autologin/telegram_notify.sh" ;;
        update_json.lua) echo "/usr/lib/autologin/update_json.lua" ;;
        backend_hosts.conf) echo "/usr/lib/autologin/captive-detect/backend_hosts.conf" ;;
        detection.conf) echo "/usr/lib/autologin/captive-detect/detection.conf" ;;
        endpoints.conf) echo "/usr/lib/autologin/captive-detect/endpoints.conf" ;;
        portal.json) echo "/usr/lib/autologin/captive-detect/portal.json" ;;
        autologin.css) echo "/www/luci-static/resources/autologin.css" ;;
        *) echo "" ;;
    esac
}

get_payload_target() {
    case "$1" in
        index.htm) echo "/usr/lib/lua/luci/view/autologin/index.htm" ;;
        common.sh) echo "/usr/lib/autologin/common.sh" ;;
        anti_blocking.sh) echo "/usr/lib/autologin/anti_blocking.sh" ;;
        routing_lib.sh) echo "/usr/lib/autologin/routing_lib.sh" ;;
        hotspot_mikrotik.sh) echo "/usr/lib/autologin/captive-detect/handlers/hotspot_mikrotik.sh" ;;
        wifi_id_classic.sh) echo "/usr/lib/autologin/captive-detect/handlers/wifi_id_classic.sh" ;;
        wifi_id_nextjs.sh) echo "/usr/lib/autologin/captive-detect/handlers/wifi_id_nextjs.sh" ;;
        wms.sh) echo "/usr/lib/autologin/captive-detect/handlers/wms.sh" ;;
        autologin.js) echo "/www/luci-static/resources/autologin.js" ;;
        donate.png) echo "/www/luci-static/resources/donate.png" ;;
        logout.sh) echo "/usr/lib/autologin/logout.sh" ;;
        *) echo "" ;;
    esac
}

log_info "Memulai update framework..."
for gh_file in 99-autologin autologin_init autologin_bin autologin.lua auto_timezone.sh daemon.sh health_check.sh logging.sh login_executor.sh mac_apply.sh mac_spoof.sh telegram_notify.sh update_json.lua backend_hosts.conf detection.conf endpoints.conf portal.json autologin.css; do
    target=$(get_framework_target "$gh_file")
    if [ -n "$target" ]; then
        curl -sSL "${BASE_URL}/framework/${gh_file}" -o "$target" 2>/dev/null || log_warn "Gagal download $gh_file"
        chmod 0755 "$target"
    fi
done

log_info "Memulai update payload premium..."
for file in index.htm common.sh anti_blocking.sh routing_lib.sh hotspot_mikrotik.sh wifi_id_classic.sh wifi_id_nextjs.sh wms.sh autologin.js donate.png logout.sh; do
    target=$(get_payload_target "$file")
    if [ -n "$target" ]; then
        curl -sSL "${BASE_URL}/payload/${file}.enc" -o "/tmp/${file}.enc" 2>/dev/null || continue
        openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "/tmp/${file}.enc" -out "$target" -pass pass:"$DECRYPTION_KEY" 2>/dev/null || continue
            -pass pass:"$DECRYPTION_KEY" 2>/dev/null || { log_warn "Decrypt gagal: $file"; rm -f "/tmp/${file}.enc"; continue; }
        chmod 0755 "$target"
        rm -f "/tmp/${file}.enc"
    fi
done

REMOTE_VERSION=$(curl -sSL "${BASE_URL}/version.txt" 2>/dev/null || echo "1.0.0")
echo "$REMOTE_VERSION" > /usr/lib/autologin/.version
log_info "Versi diupdate ke: $REMOTE_VERSION"

log_info "Update selesai. Membersihkan cache dan restarting services..."
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache /tmp/luci-* 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/autologin restart 2>/dev/null || true

log_info "Proses update berhasil diselesaikan."
