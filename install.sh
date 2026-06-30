#!/bin/sh
# ============================================================================
# Autologin OpenWrt Installer
# ============================================================================
set -e

_a1="https://raw.githubusercontent.com/creativy24/portal/main"
_b2="https://autologin.creativy24.workers.dev"
_c3="autologin"
_d4="/usr/lib/autologin"
_e5="/etc/init.d/autologin"
_f6="/etc/hotplug.d/iface/99-autologin"
_g7="/usr/bin/autologin"

_h8() { echo "[INFO] $1"; }
_i9() { echo "[WARN] $1"; }
_j10() { echo "[ERROR] $1"; exit 1; }
_k11() { echo "[STEP] $1"; }

_l12() {
    echo -n "$1" | openssl dgst -sha256 | awk '{print $2}'
}

_m13() {
    _k11 "Mendeteksi IP ROUTER..."
    LAN_IP=$(ip route show 2>/dev/null | grep 'src 192' | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    [ -z "$LAN_IP" ] && LAN_IP=$(ifconfig 2>/dev/null | grep -A1 "br-lan" | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
    [ -z "$LAN_IP" ] && LAN_IP="192.168.1.1"
    _h8 "IP ROUTER: $LAN_IP"
}

_n14() {
    _k11 "Memeriksa dependensi..."
    for pkg in openssl curl; do
        command -v $pkg >/dev/null 2>&1 || { opkg update >/dev/null 2>&1 && opkg install $pkg >/dev/null 2>&1; }
    done
    _h8 "Dependensi siap."
}

_o15() {
    _k11 "Data Device..."
    MAC_ADDR=$(cat /sys/class/net/br-lan/address 2>/dev/null || ifconfig br-lan 2>/dev/null | grep 'HWaddr' | awk '{print $5}')
    BOARD_ID=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
    MTD_HASH=$(cat /dev/mtd$(cat /proc/mtd 2>/dev/null | grep 'Config' | cut -d: -f1 | tr -d 'mtd') 2>/dev/null | openssl dgst -sha256 | awk '{print $2}' || echo "default")
    FINGERPRINT=$(_l12 "${MAC_ADDR}:${BOARD_ID}:${MTD_HASH}")
    _h8 "Data: $FINGERPRINT"
}

_p16() {
    LICENSE_KEY="$1"
    [ -z "$LICENSE_KEY" ] && _j10 "License key tidak diberikan. Usage: $0 <license_key>"
    _h8 "License key diterima: $LICENSE_KEY"
}

_q17() {
    _k11 "Memvalidasi license key..."
    _r18=$(curl -sSL -X POST "$_b2/validate" \
        -H "Content-Type: application/json" \
        -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"mac_address\": \"$MAC_ADDR\", \"board_id\": \"$BOARD_ID\"}" 2>/dev/null)
    
    _s19=$(echo "$_r18" | grep -o '"success":true' || true)
    [ -z "$_s19" ] && _j10 "Validasi gagal: $(echo "$_r18" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)"
    
    _t20=$(echo "$_r18" | grep -o '"decryption_key":"[^"]*"' | cut -d'"' -f4)
    DECRYPTION_KEY=$(_l12 "${_t20}:${FINGERPRINT}")
    
    _h8 "License valid! Dynamic key generated."
}

_u21() {
    case "$1" in
        99-autologin) echo "$_f6" ;;
        autologin_init) echo "$_e5" ;;
        autologin_bin) echo "$_g7" ;;
        autologin.lua) echo "/usr/lib/lua/luci/controller/autologin.lua" ;;
        auto_timezone.sh) echo "$_d4/auto_timezone.sh" ;;
        daemon.sh) echo "$_d4/daemon.sh" ;;
        heartbeat.sh) echo "$_d4/heartbeat.sh" ;;
        health_check.sh) echo "$_d4/health_check.sh" ;;
        logging.sh) echo "$_d4/logging.sh" ;;
        login_executor.sh) echo "$_d4/login_executor.sh" ;;
        mac_apply.sh) echo "$_d4/mac_apply.sh" ;;
        mac_spoof.sh) echo "$_d4/mac_spoof.sh" ;;
        telegram_notify.sh) echo "$_d4/telegram_notify.sh" ;;
        update_json.lua) echo "$_d4/update_json.lua" ;;
        backend_hosts.conf) echo "$_d4/captive-detect/backend_hosts.conf" ;;
        detection.conf) echo "$_d4/captive-detect/detection.conf" ;;
        endpoints.conf) echo "$_d4/captive-detect/endpoints.conf" ;;
        portal.json) echo "$_d4/captive-detect/portal.json" ;;
        autologin.css) echo "/www/luci-static/resources/autologin.css" ;;
        *) echo "" ;;
    esac
}

_v22() {
    _k11 "Downloading framework..."
    mkdir -p "$_d4/captive-detect/handlers" /usr/lib/lua/luci/controller /usr/lib/lua/luci/view/autologin /www/luci-static/resources /etc/hotplug.d/iface /etc/init.d /usr/bin
    
    for _w23 in 99-autologin autologin_init autologin_bin autologin.lua auto_timezone.sh daemon.sh heartbeat.sh health_check.sh logging.sh login_executor.sh mac_apply.sh mac_spoof.sh telegram_notify.sh update_json.lua backend_hosts.conf detection.conf endpoints.conf portal.json autologin.css; do
        _x24=$(_u21 "$_w23")
        if [ -n "$_x24" ]; then
            curl -sSL "${_a1}/framework/${_w23}" -o "$_x24" 2>/dev/null || continue
            chmod 0755 "$_x24"
        fi
    done
    _h8 "Framework berhasil diinstall."
}

_y25() {
    _k11 "Mengunduh payload..."
    
    _z26=$(curl -sSL -X POST "$_b2/payload/get-session" \
        -H "Content-Type: application/json" \
        -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\"}" 2>/dev/null)
    
    _aa27=$(echo "$_z26" | grep -o '"success":true' || true)
    [ -z "$_aa27" ] && _j10 "Gagal membuat sesi download: $(echo "$_z26" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)"
    
    SESSION_TOKEN=$(echo "$_z26" | grep -o '"session_token":"[^"]*"' | cut -d'"' -f4)
    _h8 "Sesi download dibuat."
    
    _ab28=$(curl -sSL -X POST "$_b2/payload/instructions" \
        -H "Content-Type: application/json" \
        -d "{\"session_token\": \"$SESSION_TOKEN\", \"fingerprint\": \"$FINGERPRINT\"}" 2>/dev/null)
    
    _ac29=$(echo "$_ab28" | grep -o '"success":true' || true)
    [ -z "$_ac29" ] && _j10 "Gagal mendapatkan instructions"
    
    _ad30=$(echo "$_ab28" | grep -o '"total_files":[0-9]*' | cut -d: -f2)
    _h8 "Menerima $_ad30 instructions dari server."
    
    echo "$_ab28" | grep -o '"file":"[^"]*"' | cut -d'"' -f4 | while read _ae31; do
        _af32=$(echo "$_ab28" | grep -o "\"file\":\"$_ae31\"[^}]*" | grep -o '"target":"[^"]*"' | cut -d'"' -f4)
        _ag33=$(echo "$_ab28" | grep -o "\"file\":\"$_ae31\"[^}]*" | grep -o '"chmod":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$_af32" ]; then
            _h8 "Mengunduh $_ae31..."
            
            HTTP_CODE=$(curl -sSL -o "/tmp/$_ae31" -w "%{http_code}" -X POST "$_b2/payload/download" \
                -H "Content-Type: application/json" \
                -d "{\"session_token\": \"$SESSION_TOKEN\", \"file\": \"$_ae31\"}" 2>/dev/null)
            
            if [ "$HTTP_CODE" != "200" ]; then
                _i9 "Gagal mengunduh $_ae31 (HTTP $HTTP_CODE)"
                rm -f "/tmp/$_ae31"
                continue
            fi
            
            openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 \
                -in "/tmp/$_ae31" -out "$_af32" \
                -pass pass:"$DECRYPTION_KEY" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                [ -n "$_ag33" ] && chmod "$_ag33" "$_af32"
                _h8 "$_ae31 berhasil."
            else
                _i9 "Decrypt gagal: $_ae31"
            fi
            
            rm -f "/tmp/$_ae31"
        fi
    done
    
    _h8 "Payload premium berhasil diinstall."
}

_ah34() {
    _k11 "Menghitung integrity hash..."
    HASH_FILE="$_d4/.file_hashes"
    > "$HASH_FILE"
    
    find "$_d4" -type f -name "*.sh" -o -name "*.lua" -o -name "*.conf" -o -name "*.json" 2>/dev/null | while read _ai35; do
        hash=$(sha256sum "$_ai35" 2>/dev/null | awk '{print $1}')
        [ -n "$hash" ] && echo "$hash  $_ai35" >> "$HASH_FILE"
    done
    
    find /usr/lib/lua/luci/view/autologin /www/luci-static/resources -type f 2>/dev/null | while read _ai35; do
        hash=$(sha256sum "$_ai35" 2>/dev/null | awk '{print $1}')
        [ -n "$hash" ] && echo "$hash  $_ai35" >> "$HASH_FILE"
    done
    
    chmod 600 "$HASH_FILE"
    _h8 "Integrity hash disimpan."
}

_aj36() {
    _k11 "Setup cron..."
    mkdir -p "$_d4"
    echo "$LICENSE_KEY" > "$_d4/.license_key"
    echo "$FINGERPRINT" > "$_d4/.fingerprint"
    echo "2.0.0" > "$_d4/.version"
    echo "active" > "$_d4/.license_status"
    chmod 600 "$_d4/.license_key" "$_d4/.fingerprint"
    
    sed -i '/autologin/d' /etc/crontabs/root 2>/dev/null || true
    echo "0 */6 * * * $_d4/heartbeat.sh >/dev/null 2>&1" >> /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
    
    _h8 "Cron job ditambahkan."
}

_ak37() {
    _k11 "Restarting services..."
    /etc/init.d/uhttpd restart 2>/dev/null || true
    [ -f "$_e5" ] && "$_e5" start 2>/dev/null || true
}

echo "============================================================================"
echo "Autologin Installer v1.0"
echo "============================================================================"
_m13
_n14
_o15
_p16 "$1"
_q17
_v22
_y25
_ah34
_aj36
_ak37

echo "============================================================================"
_h8 "INSTALASI BERHASIL!"
echo "Akses panel: http://${LAN_IP}/cgi-bin/luci/admin/autologin/konfigurasi"
echo "============================================================================"
