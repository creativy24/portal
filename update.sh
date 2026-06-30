#!/bin/sh
# ============================================================================
# Autologin - Update
# ============================================================================
set -e

_a1="https://raw.githubusercontent.com/creativy24/portal/main"
_b2="https://autologin.creativy24.workers.dev"
_d4="/usr/lib/autologin"
_e5="/etc/init.d/autologin"

_h8() { echo "[UPDATE] $1"; }
_i9() { echo "[UPDATE WARN] $1"; }

_l12() {
    echo -n "$1" | openssl dgst -sha256 | awk '{print $2}'
}

LICENSE_KEY=$(cat "$_d4/.license_key" 2>/dev/null)
FINGERPRINT=$(cat "$_d4/.fingerprint" 2>/dev/null)

[ -z "$LICENSE_KEY" ] || [ -z "$FINGERPRINT" ] && { _i9 "Metadata tidak ditemukan."; exit 1; }

_h8 "Memvalidasi license..."
_r18=$(curl -sSL -X POST "$_b2/validate" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"request_type\": \"refresh\"}" 2>/dev/null)

_s19=$(echo "$_r18" | grep -o '"success":true' || true)
[ -z "$_s19" ] && { _i9 "Validasi gagal."; exit 1; }

_t20=$(echo "$_r18" | grep -o '"decryption_key":"[^"]*"' | cut -d'"' -f4)
DECRYPTION_KEY=$(_l12 "${_t20}:${FINGERPRINT}")

_u21() {
    case "$1" in
        99-autologin) echo "/etc/hotplug.d/iface/99-autologin" ;;
        autologin_init) echo "$_e5" ;;
        autologin_bin) echo "/usr/bin/autologin" ;;
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

_h8 "Memulai update framework..."
for _w23 in 99-autologin autologin_init autologin_bin autologin.lua auto_timezone.sh daemon.sh heartbeat.sh health_check.sh logging.sh login_executor.sh mac_apply.sh mac_spoof.sh telegram_notify.sh update_json.lua backend_hosts.conf detection.conf endpoints.conf portal.json autologin.css; do
    _x24=$(_u21 "$_w23")
    if [ -n "$_x24" ]; then
        curl -sSL "${_a1}/framework/${_w23}" -o "$_x24" 2>/dev/null || _i9 "Gagal download $_w23"
        chmod 0755 "$_x24"
    fi
done

_h8 "Mengunduh payload..."

_z26=$(curl -sSL -X POST "$_b2/payload/get-session" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\"}" 2>/dev/null)

_aa27=$(echo "$_z26" | grep -o '"success":true' || true)
if [ -n "$_aa27" ]; then
    SESSION_TOKEN=$(echo "$_z26" | grep -o '"session_token":"[^"]*"' | cut -d'"' -f4)
    
    _ab28=$(curl -sSL -X POST "$_b2/payload/instructions" \
        -H "Content-Type: application/json" \
        -d "{\"session_token\": \"$SESSION_TOKEN\", \"fingerprint\": \"$FINGERPRINT\"}" 2>/dev/null)
    
    echo "$_ab28" | grep -o '"file":"[^"]*"' | cut -d'"' -f4 | while read _ae31; do
        _af32=$(echo "$_ab28" | grep -o "\"file\":\"$_ae31\"[^}]*" | grep -o '"target":"[^"]*"' | cut -d'"' -f4)
        _ag33=$(echo "$_ab28" | grep -o "\"file\":\"$_ae31\"[^}]*" | grep -o '"chmod":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$_af32" ]; then
            HTTP_CODE=$(curl -sSL -o "/tmp/$_ae31" -w "%{http_code}" -X POST "$_b2/payload/download" \
                -H "Content-Type: application/json" \
                -d "{\"session_token\": \"$SESSION_TOKEN\", \"file\": \"$_ae31\"}" 2>/dev/null)
            
            if [ "$HTTP_CODE" = "200" ]; then
                openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 \
                    -in "/tmp/$_ae31" -out "$_af32" \
                    -pass pass:"$DECRYPTION_KEY" 2>/dev/null && {
                    [ -n "$_ag33" ] && chmod "$_ag33" "$_af32"
                } || _i9 "Decrypt gagal: $_ae31"
            fi
            
            rm -f "/tmp/$_ae31"
        fi
    done
else
    _i9 "Gagal membuat sesi download."
fi

REMOTE_VERSION=$(curl -sSL "${_a1}/version.txt" 2>/dev/null || echo "2.0.0")
echo "$REMOTE_VERSION" > "$_d4/.version"
_h8 "Versi diupdate ke: $REMOTE_VERSION"

_h8 "Membersihkan cache dan restarting services..."
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache /tmp/luci-* 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
[ -f "$_e5" ] && "$_e5" restart 2>/dev/null || true

_h8 "Update berhasil."
