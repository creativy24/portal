#!/bin/sh
# Universal Force Logout Handler

. /usr/lib/autologin/logging.sh
PORTAL_TYPE="$1"
URL="$2"
DEVICE="$3"
LOGICAL="$4"
MAC="$5"

PORTAL_FILE="/usr/lib/autologin/captive-detect/portal.json"

if [ -f /usr/lib/autologin/routing_lib.sh ]; then
    . /usr/lib/autologin/routing_lib.sh
fi

if [ -f "$PORTAL_FILE" ]; then
    UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.ua' 2>/dev/null)
    SEC_CH_UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua' 2>/dev/null)
    SEC_CH_UA_PLATFORM_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_platform' 2>/dev/null)
    SEC_CH_UA_MOBILE_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_mobile' 2>/dev/null)
fi

get_portal_prop() {
    jsonfilter -i "$PORTAL_FILE" -e "@.patterns[@.type_key='$PORTAL_TYPE'].$1" 2>/dev/null
}

clean_local_state() {
    log_info "logout.sh" "Membersihkan data koneksi sementara (conntrack dan ARP)..."
    conntrack -D -i "$DEVICE" >/dev/null 2>&1 || conntrack -F >/dev/null 2>&1 || true
    ip neigh flush dev "$DEVICE" >/dev/null 2>&1
    log_info "logout.sh" "Data koneksi sementara sudah dibersihkan."
}

restart_interface() {
    log_info "logout.sh" "Merestart interaface $LOGICAL..."
    ubus call network.interface."$LOGICAL" down >/dev/null 2>&1
    sleep 2
    ubus call network.interface."$LOGICAL" up >/dev/null 2>&1
    log_info "logout.sh" "Interface $LOGICAL sudah direstart."
}

LOGOUT_API=$(get_portal_prop logout_api)
LOGOUT_PAGE=$(get_portal_prop logout_page)
LOGOUT_PAGE_ALT=$(get_portal_prop logout_page_alt)
LOGOUT_AUTH_SECRET=$(get_portal_prop logout_auth_secret)

if [ -n "$LOGOUT_API" ]; then
    AUTH_TIME=$(TZ=WIB-7 date '+%Y-%m-%d %H:%M:%S')
    AUTH_TOKEN=$(printf '%s' "${LOGOUT_AUTH_SECRET}${AUTH_TIME}${UA_ANDROID}" | md5sum | awk '{print $1}')

    log_info "logout.sh" "Mengirim permintaan logout ke server portal..."

    RESP=$(curl -s -k --interface "$DEVICE" --connect-timeout 5 --max-time 10 \
        -X POST \
        -A "$UA_ANDROID" \
        -H "accept: application/json, text/javascript, */*; q=0.01" \
        -H "accept-language: id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7" \
        -H "origin: https://welcome2.wifi.id" \
        -H "referer: https://welcome2.wifi.id/" \
        -H "X-Authorization-Token: $AUTH_TOKEN" \
        -H "X-Authorization-Time: $AUTH_TIME" \
        -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_ANDROID\"" \
        -H "sec-ch-ua: $SEC_CH_UA_ANDROID" \
        -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_ANDROID" \
        -H "sec-fetch-dest: empty" \
        -H "sec-fetch-mode: cors" \
        -H "sec-fetch-site: same-site" \
        -H "cache-control: no-cache" \
        -H "pragma: no-cache" \
        -H "dnt: 1" \
        "$LOGOUT_API" 2>/dev/null)

    [ -n "$RESP" ] && log_info "logout.sh" "Server portal memberikan respons."
    
    if [ -n "$LOGOUT_PAGE" ]; then
        log_info "logout.sh" "Mengakses halaman logout..."
        curl -s -k --interface "$DEVICE" --connect-timeout 5 --max-time 10 "$LOGOUT_PAGE" >/dev/null 2>&1
    fi
    if [ -n "$LOGOUT_PAGE_ALT" ]; then
        log_info "logout.sh" "Mengakses halaman logout alternatif..."
        curl -s -k --interface "$DEVICE" --connect-timeout 5 --max-time 10 "$LOGOUT_PAGE_ALT" >/dev/null 2>&1
    fi

elif [ -n "$(get_portal_prop logout_path)" ]; then
    _logout_path=$(get_portal_prop logout_path)
    _logout_query=$(get_portal_prop logout_query)
    _host=$(printf '%s' "$URL" | awk -F'[/:]' '{print $4}')
    _logout_url="http://${_host}${_logout_path}"
    [ -n "$_logout_query" ] && _logout_url="${_logout_url}?${_logout_query}"
    
    log_info "logout.sh" "Mengakses halaman logout: $_logout_url"
    curl -s --interface "$DEVICE" --connect-timeout 5 --max-time 10 \
        -A "$UA_ANDROID" \
        "$_logout_url" >/dev/null 2>&1

else
    log_error "logout.sh" "Tipe portal $PORTAL_TYPE belum didukung untuk logout."
fi

clean_local_state

log_info "logout.sh" "Membersihkan berkas sementara..."
rm -f /tmp/autologin_cookie_${LOGICAL}_* 2>/dev/null
rm -f /tmp/autologin/debug/${DEVICE}.log 2>/dev/null
log_info "logout.sh" "Berkas sementara sudah dibersihkan."

restart_interface

set_mwan3_state "$LOGICAL" disabled
echo '{"status":"success","message":"Logout berhasil."}'
exit 0