#!/bin/sh
# ============================================================================
# Autologin - Auto Update
# ============================================================================

_a1="https://raw.githubusercontent.com/creativy24/portal/main"
_b2="https://autologin.creativy24.workers.dev"
_d4="/usr/lib/autologin"
_e5="/etc/init.d/autologin"

_h8() { echo "[UPD] $1"; }
_i9() { echo "[WRN] $1"; }

_l12() {
    echo -n "$1" | openssl dgst -sha256 | awk '{print $2}'
}

LICENSE_KEY=$(cat "$_d4/.license_key" 2>/dev/null)
FINGERPRINT=$(cat "$_d4/.fingerprint" 2>/dev/null)

[ -z "$LICENSE_KEY" ] || [ -z "$FINGERPRINT" ] && { _i9 "0x01:META:MISSING"; exit 1; }

_h8 "0x01:INIT"
_r18=$(curl -sSL -X POST "$_b2/validate" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"request_type\": \"refresh\"}" 2>&1)

_s19=$(echo "$_r18" | jq -r '.success' 2>/dev/null)
if [ "$_s19" != "true" ]; then
    _i9 "0x01:FAIL"
    exit 1
fi

_t20=$(echo "$_r18" | jq -r '.decryption_key' 2>/dev/null)
_STATIC_SALT="autologin_secure_salt_v2.2"
DECRYPTION_KEY=$(_l12 "${_t20}:${_STATIC_SALT}")

_tg_status=$(echo "$_r18" | jq -r '.telegram_notification.sent' 2>/dev/null)
if [ "$_tg_status" = "true" ]; then
    _h8 "0x01:OK:NTF"
else
    _tg_reason=$(echo "$_r18" | jq -r '.telegram_notification.reason' 2>/dev/null || echo "N/A")
    _i9 "0x01:NTF:$_tg_reason"
fi

_h8 "0x01:OK"

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

_h8 "0x02:CORE"
_total=19
_current=0
for _w23 in 99-autologin autologin_init autologin_bin autologin.lua auto_timezone.sh daemon.sh heartbeat.sh health_check.sh logging.sh login_executor.sh mac_apply.sh mac_spoof.sh telegram_notify.sh update_json.lua backend_hosts.conf detection.conf endpoints.conf portal.json autologin.css; do
    _current=$((_current + 1))
    _x24=$(_u21 "$_w23")
    if [ -n "$_x24" ]; then
        _h8 "0x02:PROC:$_current/$_total"
        curl -sSL "${_a1}/framework/${_w23}" -o "$_x24" 2>&1 || {
            _i9 "0x02:FAIL:$_current"
            continue
        }
        chmod 0755 "$_x24"
    fi
done
_h8 "0x02:OK"

_h8 "0x03:SEC"

_z26=$(curl -sSL -X POST "$_b2/payload/get-session" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\"}" 2>&1)

_aa27=$(echo "$_z26" | jq -r '.success' 2>/dev/null)
if [ "$_aa27" = "true" ]; then
    SESSION_TOKEN=$(echo "$_z26" | jq -r '.session_token' 2>/dev/null)
    
    _ab28=$(curl -sSL -X POST "$_b2/payload/instructions" \
        -H "Content-Type: application/json" \
        -d "{\"session_token\": \"$SESSION_TOKEN\", \"fingerprint\": \"$FINGERPRINT\"}" 2>&1)
    
    echo "$_ab28" > /tmp/autologin_update_instructions.json
    
    jq -c '.instructions[]' /tmp/autologin_update_instructions.json 2>/dev/null | while read -r _inst; do
        _action=$(echo "$_inst" | jq -r '.action' 2>/dev/null)
        
        if [ "$_action" = "mkdir" ]; then
            _path=$(echo "$_inst" | jq -r '.path' 2>/dev/null)
            _h8 "0x03:MKDIR"
            mkdir -p "$_path" 2>&1 || _i9 "0x03:MKDIR:FAIL"
            
        elif [ "$_action" = "download_decrypt" ]; then
            _file=$(echo "$_inst" | jq -r '.file' 2>/dev/null)
            _target=$(echo "$_inst" | jq -r '.target' 2>/dev/null)
            _chmod=$(echo "$_inst" | jq -r '.chmod' 2>/dev/null)
            
            _pcount=${_pcount:-0}
            _pcount=$((_pcount + 1))
            _h8 "0x03:PROC:$_pcount/11"
            
            HTTP_CODE=$(curl -sSL -o "/tmp/$_file" -w "%{http_code}" -X POST "$_b2/payload/download" \
                -H "Content-Type: application/json" \
                -d "{\"session_token\": \"$SESSION_TOKEN\", \"file\": \"$_file\"}" 2>&1)
            
            if [ "$HTTP_CODE" = "200" ]; then
                _h8 "0x03:DEC"
                openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 \
                    -in "/tmp/$_file" -out "$_target" \
                    -pass pass:"$DECRYPTION_KEY" 2>&1
                
                _decrypt_status=$?
                if [ $_decrypt_status -eq 0 ]; then
                    [ -n "$_chmod" ] && chmod "$_chmod" "$_target"
                    _h8 "0x03:OK"
                else
                    _i9 "0x03:DEC:FAIL:$_pcount"
                fi
            else
                _i9 "0x03:DL:FAIL:$_pcount"
            fi
            
            rm -f "/tmp/$_file"
        fi
    done
    
    rm -f /tmp/autologin_update_instructions.json
    _h8 "0x03:OK"
else
    _i9 "0x03:SESS:FAIL"
fi

_h8 "0x04:VER"
REMOTE_VERSION=$(curl -sSL "${_a1}/version.txt" 2>/dev/null || echo "1.0.0")
echo "$REMOTE_VERSION" > "$_d4/.version"
_h8 "0x04:OK:$REMOTE_VERSION"

_h8 "0x05:SVC"
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache /tmp/luci-* 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
[ -f "$_e5" ] && "$_e5" restart 2>/dev/null || true
_h8 "0x05:OK"

_h8 "0xFF:COMPLETE"
