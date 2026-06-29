#!/bin/sh
# Auto TimeZone

. /usr/lib/autologin/logging.sh

TZ_CACHE="/etc/autologin/autologin_tz.cache"
TZ_API="http://ip-api.com/json?fields=status,timezone"
LOCK="/tmp/autologin_tz.lock"
TIMEOUT=5

get_posix_tz() {
    local iana_tz="$1"
    local tz_data
    local tz_name
    local tz_offset

    tz_data=$(TZ="$iana_tz" date +"%Z %z" 2>/dev/null)
    
    if [ -n "$tz_data" ]; then
        tz_name="${tz_data%% *}"
        tz_offset="${tz_data##* }"
        if [ "$tz_name" = "UTC" ] || [ "$tz_name" = "GMT" ]; then
            case "$iana_tz" in
                UTC|Etc/UTC|GMT) 
                    echo "UTC0"
                    return 0
                    ;;
                *)
                    log_error "auto_timezone.sh" "Gagal mengubah zona waktu. Paket 'zoneinfo-asia' belum terpasang. Silakan pasang paket tersebut."
                    echo ""
                    return 1
                    ;;
            esac
        fi

        local sign="${tz_offset%"${tz_offset#?}"}"
        local hours="${tz_offset#?}"
        hours="${hours%"${hours#??}"}"
        
        local hours_num="${hours#"${hours%%[!0]*}"}"
        [ -z "$hours_num" ] && hours_num=0
        
        local posix_sign
        if [ "$sign" = "+" ]; then
            posix_sign="-"
        else
            posix_sign="+"
        fi
        
        echo "${tz_name}${posix_sign}${hours_num}"
        return 0
    fi

    echo ""
    return 1
}

[ -e "$LOCK" ] && exit 0
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
mkdir -p /etc/autologin 2>/dev/null
NOW=$(date +%s)
CURRENT_TZ=$(uci get system.@system[0].zonename 2>/dev/null)

CACHE_TZ=""
if [ -f "$TZ_CACHE" ]; then
    CACHE_TZ=$(tail -1 "$TZ_CACHE" 2>/dev/null)
fi

if [ -n "$CURRENT_TZ" ] && [ "$CURRENT_TZ" != "UTC" ] && [ "$CURRENT_TZ" != "Etc/UTC" ] && [ "$CURRENT_TZ" = "$CACHE_TZ" ]; then
    log_info "auto_timezone.sh" "Zona waktu sudah benar ($CURRENT_TZ). Tidak perlu menyinkronkan ulang."
    exit 0
fi

PORTAL_JSON=$(/usr/lib/autologin/common.sh 2>/dev/null)

IFACE=$(echo "$PORTAL_JSON" | jsonfilter -e '@.interfaces[0].device' 2>/dev/null)
[ -z "$IFACE" ] && IFACE=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$IFACE" ]; then
    log_info "auto_timezone.sh" "Tidak ada jaringan yang terdeteksi. Menggunakan zona waktu bawaan sistem."
    exit 0
fi

RESP=$(curl --interface "$IFACE" -s -m $TIMEOUT "$TZ_API")

STATUS=$(echo "$RESP" | jsonfilter -e '@.status' 2>/dev/null)
[ -z "$STATUS" ] && STATUS=$(echo "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')

NEW_TZ=""

if [ "$STATUS" = "success" ]; then
    NEW_TZ=$(echo "$RESP" | jsonfilter -e '@.timezone' 2>/dev/null)
    [ -z "$NEW_TZ" ] && NEW_TZ=$(echo "$RESP" | sed -n 's/.*"timezone":"\([^"]*\)".*/\1/p')
fi

if printf '%s' "$NEW_TZ" | grep -qE '^[A-Za-z0-9/_+-]+$'; then
    FINAL_TZ="$NEW_TZ"
    SOURCE="api"
else
    if printf '%s' "$CACHE_TZ" | grep -qE '^[A-Za-z0-9/_+-]+$'; then
        FINAL_TZ="$CACHE_TZ"
        SOURCE="cache"
        log_info "auto_timezone.sh" "Tidak dapat menghubungi server zona waktu. Menggunakan data dari cache: $FINAL_TZ."
    else
        FINAL_TZ="$CURRENT_TZ"
        SOURCE="system"
        log_info "auto_timezone.sh" "Tidak dapat menghubungi server zona waktu dan cache kosong. Menggunakan zona waktu bawaan: $FINAL_TZ."
    fi
fi

if [ -n "$FINAL_TZ" ] && [ "$CURRENT_TZ" != "$FINAL_TZ" ]; then
    uci set system.@system[0].zonename="$FINAL_TZ"
    
    POSIX_TZ=$(get_posix_tz "$FINAL_TZ")
    if [ -n "$POSIX_TZ" ]; then
        uci set system.@system[0].timezone="$POSIX_TZ"
    else
        uci delete system.@system[0].timezone 2>/dev/null
    fi
    
    uci commit system
    /etc/init.d/sysntpd restart
    log_info "auto_timezone.sh" "Zona waktu berhasil diperbarui dari $CURRENT_TZ menjadi $FINAL_TZ (sumber: $SOURCE, interface: $IFACE)."
else
    log_info "auto_timezone.sh" "Zona waktu sudah sesuai: $CURRENT_TZ (sumber: $SOURCE)."
fi

if [ "$SOURCE" = "api" ]; then
    echo "$NOW" > "$TZ_CACHE"
    echo "$FINAL_TZ" >> "$TZ_CACHE"
fi

exit 0