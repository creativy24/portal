#!/bin/sh
# Telegram Notification untuk AutoLogin

PROFILE_ID="$1"
EVENT="$2"
MESSAGE="$3"
CONFIG_FILE="/etc/autologin/profiles.json"

. /usr/lib/autologin/logging.sh

[ -n "$OVR_TOKEN" ] && TOKEN="$OVR_TOKEN"
[ -n "$OVR_CHAT_ID" ] && CHAT_ID="$OVR_CHAT_ID"
[ -n "$OVR_ENABLED" ] && ENABLED="$OVR_ENABLED"
[ -n "$OVR_LOGICAL" ] && LOGICAL="$OVR_LOGICAL"
[ -n "$OVR_DEVICE" ] && DEVICE="$OVR_DEVICE"
[ -n "$OVR_MAC" ] && MAC="$OVR_MAC"
[ -n "$OVR_IPC" ] && IPC="$OVR_IPC"
[ -n "$OVR_PORTAL_TYPE" ] && PORTAL_TYPE="$OVR_PORTAL_TYPE"
[ -n "$OVR_STATUS" ] && STATUS="$OVR_STATUS"

if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ] || [ -z "$ENABLED" ]; then
    TOKEN=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].telegram_token")
    CHAT_ID=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].telegram_chat_id")
    ENABLED=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].telegram_enabled")
fi

if [ "$ENABLED" != "true" ] || [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
    log_info "telegram_notify.sh" "Notifikasi Telegram tidak dikirim untuk profil $PROFILE_ID. (aktif=$ENABLED, token=$( [ -n "$TOKEN" ] && echo ada || echo tidak ada ), chat_id=$( [ -n "$CHAT_ID" ] && echo ada || echo tidak ada ))"
    exit 0
fi

[ -z "$LOGICAL" ] && LOGICAL=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].logical" 2>/dev/null)
[ -z "$DEVICE" ] && DEVICE=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].device" 2>/dev/null)
[ -z "$MAC" ] && MAC=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].mac" 2>/dev/null)
[ -z "$IPC" ] && IPC=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].ipc" 2>/dev/null)
[ -z "$PORTAL_TYPE" ] && PORTAL_TYPE=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].portal_type" 2>/dev/null)

if [ -z "$STATUS" ]; then
    STATE_FILE="/tmp/autologin/state/${PROFILE_ID}.state"
    if [ -f "$STATE_FILE" ]; then
        STATUS=$(jsonfilter -i "$STATE_FILE" -e '@.status' 2>/dev/null)
    fi
    [ -z "$STATUS" ] && STATUS="UNKNOWN"
fi

case "$EVENT" in
    success)
        ICON="\xE2\x9C\x85"
        TITLE="Login Berhasil"
        STATUS_ICON="\xF0\x9F\x9F\xA2"
        ;;
    error)
        ICON="\xE2\x9D\x8C"
        TITLE="Login Gagal Permanen"
        STATUS_ICON="\xF0\x9F\x94\xB4"
        ;;
    fail)
        ICON="\xE2\x9A\xA0\xEF\xB8\x8F"
        TITLE="Login Gagal"
        STATUS_ICON="\xF0\x9F\x9F\xA1"
        ;;
    reconnect)
        ICON="\xF0\x9F\x94\x84"
        TITLE="Koneksi Pulih"
        STATUS_ICON="\xF0\x9F\x9F\xA2"
        ;;
    initial)
        ICON="\xF0\x9F\x9A\x80"
        TITLE="Status Awal Terdeteksi"
        STATUS_ICON="\xF0\x9F\x9F\xA2"
        ;;
    antiblocking)
        ICON="\xF0\x9F\x9B\xA1\xEF\xB8\x8F"
        TITLE="Anti-Blokir Diaktifkan"
        STATUS_ICON="\xF0\x9F\x9F\xA0"
        ;;
    bug)
        ICON="\xF0\x9F\x90\x9B"
        TITLE="Kesalahan Sistem"
        STATUS_ICON="\xF0\x9F\x94\xB4"
        ;;
    *)
        ICON="\xF0\x9F\x93\xA2"
        TITLE="Notifikasi AutoLogin"
        STATUS_ICON="\xE2\x9A\xAA"
        ;;
esac

case "$STATUS" in
    CONNECTED) STATUS_TEXT="Terhubung" ;;
    PORTAL_DETECTED) STATUS_TEXT="Terdeteksi Portal" ;;
    DISCONNECTED) STATUS_TEXT="Terputus" ;;
    NO_IP) STATUS_TEXT="Tidak Ada IP" ;;
    IDLE) STATUS_TEXT="Menunggu" ;;
    PERMANENT_ERROR) STATUS_TEXT="Galat Permanen" ;;
    *) STATUS_TEXT="$STATUS" ;;
esac

TEMP_MSG="/tmp/telegram_msg_$$.txt"
printf "<b>${ICON} ${TITLE}</b>\n\n<b>\xF0\x9F\x93\x8B Profil:</b> <code>%s</code>\n<b>\xF0\x9F\x93\xA1 Interface:</b> %s (%s)\n<b>\xF0\x9F\x94\x97 MAC:</b> <code>%s</code>\n<b>\xF0\x9F\x8C\x90 IP:</b> %s\n<b>\xF0\x9F\x8F\xB7\xEF\xB8\x8F Tipe Portal:</b> %s\n<b>${STATUS_ICON} Status:</b> %s\n<b>\xF0\x9F\x95\x90 Waktu:</b> %s\n\n<b>\xF0\x9F\x94\x91 PESAN:</b>\n%s\n\n<em>Sistem AutoLogin dibuat oleh TMC</em>" \
    "${PROFILE_ID}" "${LOGICAL:-?}" "${DEVICE:-?}" "${MAC:-?}" "${IPC:-?}" "${PORTAL_TYPE:-?}" "${STATUS_TEXT}" "$(TZ=WIB-7 date '+%d %b %Y, %H:%M WITA')" "${MESSAGE}" > "$TEMP_MSG"

log_info "telegram_notify.sh" "Mengirim notifikasi Telegram ($EVENT) untuk profil $PROFILE_ID..."

RESP=$(curl -s -w "\n%{http_code}" -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text@${TEMP_MSG}" \
    -d "parse_mode=HTML" \
    --max-time 10 2>/dev/null)

HTTP_CODE=$(echo "$RESP" | tail -1)
rm -f "$TEMP_MSG" >/dev/null 2>&1

if [ "$HTTP_CODE" = "200" ]; then
    log_info "telegram_notify.sh" "Notifikasi Telegram berhasil dikirim."
else
    log_error "telegram_notify.sh" "Gagal mengirim notifikasi Telegram. Kode HTTP: $HTTP_CODE."
fi