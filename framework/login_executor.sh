#!/bin/sh
# Login Executor

. /usr/lib/autologin/logging.sh
PROFILE_ID="$1"
CONFIG_FILE="/etc/autologin/profiles.json"
PORTAL_FILE="/usr/lib/autologin/captive-detect/portal.json"
HANDLER_DIR="/usr/lib/autologin/captive-detect/handlers"

get_field() { jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].$1" 2>/dev/null; }
get_rule()   { jsonfilter -i "$PORTAL_FILE" -e "@.patterns[@.type_key='$PORTAL_TYPE'].$1" 2>/dev/null; }

PORTAL_TYPE=$(get_field portal_type)
DEVICE=$(get_field device)
LOGICAL=$(get_field logical)
MAC=$(get_field mac)
USER=$(get_field username)
PASS=$(get_field password)
URL=$(get_field url)
ORIG_USER=$(get_field original_username)

if [ -z "$PORTAL_TYPE" ] || [ -z "$DEVICE" ] || [ -z "$LOGICAL" ] || [ -z "$USER" ] || [ -z "$PASS" ] || [ -z "$URL" ]; then
    log_error "login_executor.sh" "Data profil $PROFILE_ID tidak lengkap. Tidak dapat melanjutkan login."
    echo '{"status":"error","message":"Data profil tidak lengkap."}'
    exit 1
fi

HANDLER_SCRIPT=""
TOTAL_PATTERNS=$(jsonfilter -i "$PORTAL_FILE" -e '@.patterns[*].type_key' 2>/dev/null | wc -l)
i=0
while [ $i -lt $TOTAL_PATTERNS ]; do
    p_type=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].type_key" 2>/dev/null)
    if [ "$p_type" = "$PORTAL_TYPE" ]; then
        p_key=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].path_key" 2>/dev/null)
        if [ -n "$p_key" ] && echo "$URL" | grep -qF "$p_key"; then
            HANDLER_SCRIPT=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].handler_script" 2>/dev/null)
            break
        fi
    fi
    i=$((i + 1))
done

if [ -z "$HANDLER_SCRIPT" ]; then
    HANDLER_SCRIPT=$(get_rule handler_script | head -1)
fi
HAS_SESSION_GRID=$(get_rule has_session_grid | head -1)

if [ -z "$HANDLER_SCRIPT" ]; then
    log_error "login_executor.sh" "Tidak dapat menemukan handler yang cocok untuk profil $PROFILE_ID (tipe: $PORTAL_TYPE)."
    echo "{\"status\":\"error\",\"message\":\"Handler tidak ditemukan di portal_rules.json.\"}"
    exit 1
fi

HANDLER_PATH="$HANDLER_DIR/$HANDLER_SCRIPT"
if [ ! -f "$HANDLER_PATH" ]; then
    log_error "login_executor.sh" "File handler $HANDLER_SCRIPT tidak ditemukan di sistem."
    echo "{\"status\":\"error\",\"message\":\"Handler script tidak ditemukan di sistem.\"}"
    exit 1
fi

JSON_PAYLOAD=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID']" 2>/dev/null)

if [ -z "$JSON_PAYLOAD" ]; then
    JSON_PAYLOAD=$(printf '{"url":"%s","username":"%s","original_username":"%s","password":"%s","logical":"%s","device":"%s","mac":"%s","portal_type":"%s","login_method":"%s","sub_method":"%s","gw_id":"%s","wlan":"%s","sessionid":"%s","ipc":"%s"}' \
        "$URL" "$USER" "$ORIG_USER" "$PASS" "$LOGICAL" "$DEVICE" "$MAC" "$PORTAL_TYPE" "${LOGIN_METHOD:-}" "${SUB_METHOD:-}" "${GW_ID:-}" "${WLAN:-}" "${SID:-}" "${IPC:-}")
fi

log_info "login_executor.sh" "Menjalankan handler $HANDLER_SCRIPT untuk profil $PROFILE_ID."

{
    echo "===== DEBUG $(date) ====="
    echo "Profile: $PROFILE_ID"
    echo "Handler: $HANDLER_PATH"
    echo "Payload JSON:"
    echo "$JSON_PAYLOAD"
    echo "====================================="
} > /tmp/autologin/debug/login_executor_debug.log

echo "$JSON_PAYLOAD" | sh "$HANDLER_PATH"
exit $?