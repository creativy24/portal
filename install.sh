#!/bin/sh
# ============================================================================
# Autologin OpenWrt Installer
# ============================================================================
set -e

GITHUB_USER="creativy24"
GITHUB_REPO="portal"
GITHUB_BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
WORKER_URL="https://autologin.creativy24.workers.dev"

log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; exit 1; }
log_step() { echo "[STEP] $1"; }

detect_lan_ip() {
    log_step "Mendeteksi IP LAN..."
    LAN_IP=$(uci -q get network.lan.ipaddr 2>/dev/null)
    LAN_IP=${LAN_IP:-192.168.1.1}
    log_info "IP LAN: $LAN_IP"
}

install_dependencies() {
    log_step "Memeriksa dependensi..."
    for pkg in curl ca-certificates openssl-util; do
        if ! opkg list-installed 2>/dev/null | grep -q "^$pkg "; then
            opkg update >/dev/null 2>&1
            opkg install "$pkg" >/dev/null 2>&1 || log_warn "Gagal install $pkg"
        fi
    done
    log_info "Dependensi siap."
}

collect_fingerprint() {
    log_step "Mengumpulkan device fingerprint..."
    MAC_ADDR=$(cat /sys/class/net/eth0.2/address 2>/dev/null || cat /sys/class/net/wan/address 2>/dev/null || echo "unknown")
    BOARD_ID=$(cat /tmp/sysinfo/model 2>/dev/null | tr ' ' '_' | tr -cd '[:alnum:]_' || echo "unknown")
    MTD_HASH=$(cat /proc/mtd 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}' | cut -c1-16 || echo "nomtd")
    FINGERPRINT=$(echo -n "${MAC_ADDR}|${BOARD_ID}|${MTD_HASH}" | openssl dgst -sha256 2>/dev/null | awk '{print $2}')
    log_info "Fingerprint: $FINGERPRINT"
}

get_license_key() {
    echo "============================================================================"
    echo "Masukkan License Key Anda (Key Universal Gratis: autologin)"
    echo "============================================================================"
    printf "License Key: "
    read LICENSE_KEY
    [ -z "$LICENSE_KEY" ] && log_error "License key kosong!"
}

validate_license() {
    log_step "Memvalidasi license key..."
    RESPONSE=$(curl -sSL -X POST "$WORKER_URL/validate" \
        -H "Content-Type: application/json" \
        -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"mac_address\": \"$MAC_ADDR\", \"board_id\": \"$BOARD_ID\"}" 2>/dev/null)
    
    SUCCESS=$(echo "$RESPONSE" | grep -o '"success":true' || true)
    [ -z "$SUCCESS" ] && log_error "Validasi gagal: $(echo "$RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)"
    
    DECRYPTION_KEY=$(echo "$RESPONSE" | grep -o '"decryption_key":"[^"]*"' | cut -d'"' -f4)
    log_info "License valid! Decryption key diterima."
}

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

download_framework() {
    log_step "Downloading framework (18 files)..."
    mkdir -p /etc/hotplug.d/iface /etc/init.d /usr/bin /usr/lib/lua/luci/controller /usr/lib/lua/luci/view/autologin /usr/lib/autologin/captive-detect/handlers /www/luci-static/resources
    
    for gh_file in 99-autologin autologin_init autologin_bin autologin.lua auto_timezone.sh daemon.sh health_check.sh logging.sh login_executor.sh mac_apply.sh mac_spoof.sh telegram_notify.sh update_json.lua backend_hosts.conf detection.conf endpoints.conf portal.json autologin.css; do
        target=$(get_framework_target "$gh_file")
        if [ -n "$target" ]; then
            curl -sSL "${BASE_URL}/framework/${gh_file}" -o "$target" 2>/dev/null || log_warn "Gagal download $gh_file"
            chmod 0755 "$target"
        fi
    done
    log_info "Framework berhasil diinstall."
}

download_and_decrypt_payload() {
    log_step "Downloading & decrypting payload premium (11 files)..."
    
    for file in index.htm common.sh anti_blocking.sh routing_lib.sh hotspot_mikrotik.sh wifi_id_classic.sh wifi_id_nextjs.sh wms.sh autologin.js donate.png logout.sh; do
        target=$(get_payload_target "$file")
        if [ -n "$target" ]; then
            curl -sSL "${BASE_URL}/payload/${file}.enc" -o "/tmp/${file}.enc" 2>/dev/null || continue
            openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "/tmp/${file}.enc" -out "$target" -pass pass:"$DECRYPTION_KEY" 2>/dev/null || { log_warn "Decrypt gagal: $file"; rm -f "/tmp/${file}.enc"; continue; }
            chmod 0755 "$target"
            rm -f "/tmp/${file}.enc"
        fi
    done
    log_info "Payload premium berhasil diinstall."
}

save_metadata_and_cron() {
    log_step "Menyimpan metadata & setup cron..."
    mkdir -p /usr/lib/autologin
    echo "$LICENSE_KEY" > /usr/lib/autologin/.license_key
    echo "$FINGERPRINT" > /usr/lib/autologin/.fingerprint
    echo "1.0.0" > /usr/lib/autologin/.version
    echo "active" > /usr/lib/autologin/.license_status
    chmod 600 /usr/lib/autologin/.license_key /usr/lib/autologin/.fingerprint

    sed -i '/autologin-heartbeat/d' /etc/crontabs/root 2>/dev/null || true
    echo "0 */6 * * * /usr/lib/autologin/heartbeat.sh >/dev/null 2>&1" >> /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
}

restart_services() {
    log_step "Restarting services..."
    rm -rf /tmp/luci-modulecache /tmp/luci-indexcache /tmp/luci-* 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true
    /etc/init.d/autologin enable 2>/dev/null || true
    /etc/init.d/autologin start 2>/dev/null || true
}

main() {
    echo "============================================================================"
    echo "Autologin OpenWrt Installer (Encrypted Payload)"
    echo "============================================================================"
    detect_lan_ip
    install_dependencies
    collect_fingerprint
    get_license_key
    validate_license
    download_framework
    download_and_decrypt_payload
    save_metadata_and_cron
    restart_services
    
    echo "============================================================================"
    log_info "INSTALASI BERHASIL!"
    echo "Akses panel: http://${LAN_IP}/cgi-bin/luci/admin/autologin/konfigurasi"
    echo "============================================================================"
}

main
