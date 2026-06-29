#!/bin/sh
# Anti Blokir

. /usr/lib/autologin/logging.sh
if [ -f /usr/lib/autologin/routing_lib.sh ]; then
    . /usr/lib/autologin/routing_lib.sh
fi

PROFILE_ID="$1"
CONFIG_FILE="/etc/autologin/profiles.json"
LOCK_FILE="/var/run/autologin_antiblocking_${PROFILE_ID}.lock"

LOGICAL=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].logical" 2>/dev/null)

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log_info "anti_blocking.sh" "Proses anti-blokir untuk interface $LOGICAL sedang berjalan. Tidak perlu dijalankan ulang."
    exit 1
fi
trap 'flock -u 200 2>/dev/null; rm -f "$LOCK_FILE"' EXIT

DEVICE=$(jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$PROFILE_ID'].device" 2>/dev/null)

log_info "anti_blocking.sh" "Memulai prosedur anti-blokir untuk interface $LOGICAL (perangkat: $DEVICE)."

IFACE_STATUS=$(ip link show "$DEVICE" 2>/dev/null | grep -o 'state [A-Z]*' | awk '{print $2}')

log_info "anti_blocking.sh" "Merestart total interface $LOGICAL untuk mendapatkan sesi baru..."

RANDOM_HEX=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
NEW_HOSTNAME="android-${RANDOM_HEX}"
log_info "anti_blocking.sh" "Mengganti nama perangkat menjadi $NEW_HOSTNAME supaya tidak dikenali server."
uci set network."$LOGICAL".hostname="$NEW_HOSTNAME"
uci commit network

ifdown "$LOGICAL" >/dev/null 2>&1
sleep 2
ifup "$LOGICAL" >/dev/null 2>&1

log_info "anti_blocking.sh" "Menunggu interface $LOGICAL mendapatkan IP..."
for i in 1 2 3 4 5; do
    sleep 3
    NEW_IP=$(ip -4 addr show dev "$DEVICE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if [ -n "$NEW_IP" ]; then
        log_info "anti_blocking.sh" "Interface $LOGICAL mendapatkan IP: $NEW_IP (percobaan ke-$i)."
        break
    fi
    log_info "anti_blocking.sh" "IP belum tersedia, menunggu... (percobaan $i dari 5)"
done

if [ -z "$NEW_IP" ]; then
    log_error "anti_blocking.sh" "Interface $LOGICAL tidak mendapatkan IP setelah menunggu 15 detik. Prosedur anti-blokir gagal."
    exit 1
fi

SCAN_OUTPUT=$(/usr/lib/autologin/common.sh "$DEVICE" 2>/dev/null)

NEW_URL=$(echo "$SCAN_OUTPUT" | jsonfilter -e "@.interfaces[@.interface='$LOGICAL'].portal_url" 2>/dev/null)

if [ -n "$NEW_URL" ]; then
    log_info "anti_blocking.sh" "Berhasil menemukan halaman login baru. Memperbarui data profil..."
    lua /usr/lib/autologin/update_json.lua "$PROFILE_ID" "$NEW_URL" "$NEW_IP"
else
    log_error "anti_blocking.sh" "Tidak dapat menemukan halaman login untuk interface $LOGICAL. Prosedur anti-blokir gagal."
fi

set_mwan3_state "$LOGICAL" disabled
log_info "anti_blocking.sh" "Prosedur anti-blokir selesai. interface $LOGICAL sudah pulih dan siap digunakan."
exit 0