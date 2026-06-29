#!/bin/sh
# Handler login wifi.id Next.js

INPUT_JSON=$(cat)

FUNCTION="login"
URL=$(echo "$INPUT_JSON" | jsonfilter -e '@.url' 2>/dev/null)
USERNAME=$(echo "$INPUT_JSON" | jsonfilter -e '@.username' 2>/dev/null)
PASSWORD=$(echo "$INPUT_JSON" | jsonfilter -e '@.password' 2>/dev/null)
LOGICAL=$(echo "$INPUT_JSON" | jsonfilter -e '@.logical' 2>/dev/null)
DEVICE=$(echo "$INPUT_JSON" | jsonfilter -e '@.device' 2>/dev/null)
MAC=$(echo "$INPUT_JSON" | jsonfilter -e '@.mac' 2>/dev/null)
GW_ID=$(echo "$INPUT_JSON" | jsonfilter -e '@.gw_id' 2>/dev/null)
WLAN=$(echo "$INPUT_JSON" | jsonfilter -e '@.wlan' 2>/dev/null)
SESSIONID=$(echo "$INPUT_JSON" | jsonfilter -e '@.sessionid' 2>/dev/null)
IPC=$(echo "$INPUT_JSON" | jsonfilter -e '@.ipc' 2>/dev/null)
LOGIN_METHOD=$(echo "$INPUT_JSON" | jsonfilter -e '@.login_method' 2>/dev/null)
SUB_METHOD=$(echo "$INPUT_JSON" | jsonfilter -e '@.sub_method' 2>/dev/null)

BACKEND_FILE="/usr/lib/autologin/captive-detect/backend_hosts.conf"
DEBUG_DIR="/tmp/autologin/debug"
COOKIE_JAR="/tmp/autologin_cookie_${LOGICAL}_wifi_id"
TIMEOUT=10

PORTAL_FILE="/usr/lib/autologin/captive-detect/portal.json"
AUTH_SECRET=""
LOGIN_PATH=""
LP_HOST=""

if [ -f "$PORTAL_FILE" ]; then
    TOTAL_PATTERNS=$(jsonfilter -i "$PORTAL_FILE" -e '@.patterns[*].type_key' 2>/dev/null | wc -l)
    i=0
    while [ $i -lt $TOTAL_PATTERNS ]; do
        p_type=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].type_key" 2>/dev/null)
        p_handler=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].handler_script" 2>/dev/null)
        if [ "$p_type" = "WIFI_ID" ] && [ "$p_handler" = "wifi_id_nextjs.sh" ]; then
            AUTH_SECRET=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].auth_secret" 2>/dev/null)
            LOGIN_PATH=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].login_path" 2>/dev/null)
            LP_HOST=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$i].lp_host" 2>/dev/null)
            break
        fi
        i=$((i + 1))
    done
fi

. /usr/lib/autologin/logging.sh

get_ip() { grep -F "$1" "$BACKEND_FILE" 2>/dev/null | awk '{print $2}' | head -1; }
url_encode() { echo "$1" | sed 's/ /%20/g'; }

if [ -f /usr/lib/autologin/routing_lib.sh ]; then
    . /usr/lib/autologin/routing_lib.sh
else
    echo '{"status":"error","message":"Library routing_lib.sh tidak ditemukan."}'
    exit 1
fi

PORTAL_FILE="/usr/lib/autologin/captive-detect/portal.json"
if [ -f "$PORTAL_FILE" ]; then
    UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.ua' 2>/dev/null)
    SEC_CH_UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua' 2>/dev/null)
    SEC_CH_UA_PLATFORM_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_platform' 2>/dev/null)
    SEC_CH_UA_MOBILE_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_mobile' 2>/dev/null)
fi

if [ -z "$UA_ANDROID" ]; then
    echo '{"status":"error","message":"Fingerprint Android tidak tersedia di portal.json."}'
    exit 1
fi

[ -z "$GW_ID" ] && GW_ID="unknown"
[ -z "$WLAN" ] && WLAN="unknown"
[ -z "$SESSIONID" ] && SESSIONID="unknown"
[ -z "$LOGIN_METHOD" ] && LOGIN_METHOD=""
[ -z "$SUB_METHOD" ] && SUB_METHOD=""

if [ -z "$IPC" ] || ! echo "$IPC" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    IPC=$(ip -4 addr show dev "$DEVICE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
fi

MAC_CLEAN=$(echo "$MAC" | tr -d '\r\n\t ' | tr 'ABCDEF' 'abcdef')

log_info "wifi_id_nextjs.sh" "Memulai login WiFi.id Next.js. Interface: $LOGICAL, Perangkat: $DEVICE."

if [ "$GW_ID" = "unknown" ] || [ "$WLAN" = "unknown" ] || [ "$SESSIONID" = "unknown" ]; then
    log_error "wifi_id_nextjs.sh" "Data sesi tidak lengkap. GW_ID, WLAN, atau SESSIONID tidak ditemukan."
    echo '{"status":"error","message":"Parameter session grid tidak lengkap."}'
    exit 1
fi

if ! type get_free_route_table >/dev/null 2>&1; then
    get_free_route_table() { echo 200; }
    get_free_priority() { echo 1000; }
    setup_dynamic_routing() {
        _dev="$1"; _ip="$2"; _gw="$3"; _table="$4"; _prio="$5"
        ip rule add from "$_ip" lookup "$_table" priority "$_prio" 2>/dev/null
        if [ -n "$_gw" ]; then ip route add default via "$_gw" dev "$_dev" table "$_table" 2>/dev/null
        else ip route add default dev "$_dev" table "$_table" 2>/dev/null; fi
    }
    teardown_dynamic_routing() {
        _table="$1"; _prio="$2"
        ip rule del priority "$_prio" 2>/dev/null
        ip route flush table "$_table" 2>/dev/null
    }
fi

SERVER_ID=$(echo "$URL" | awk -F'[/:]' '{print $4}')
BACKEND_SERVER="americano2.wifi.id"
if echo "$SERVER_ID" | grep -qi "welcome3"; then
    BACKEND_SERVER="americano.wifi.id"
fi

RESOLVE_IP=$(get_ip "$SERVER_ID")
BACKEND_IP=$(get_ip "$BACKEND_SERVER")
[ -z "$RESOLVE_IP" ] && RESOLVE_IP="10.233.16.13"
[ -z "$BACKEND_IP" ] && BACKEND_IP="10.233.16.51"

_if_ip="$IPC"
_if_gw=$(ip route show dev "$DEVICE" 2>/dev/null | awk '/default/{print $3; exit}')
[ -z "$_if_gw" ] && _if_gw=$(ip route show dev "$DEVICE" 2>/dev/null | grep 'scope link' | head -1 | awk '{print $1}' | sed 's/\.0\/.*$/.1/')

ROUTE_TABLE=$(get_free_route_table)
POLICY_PRIO=$(get_free_priority)
setup_dynamic_routing "$DEVICE" "$_if_ip" "$_if_gw" "$ROUTE_TABLE" "$POLICY_PRIO"

cleanup() { teardown_dynamic_routing "$ROUTE_TABLE" "$POLICY_PRIO"; rm -f "$COOKIE_JAR" 2>/dev/null; }
trap cleanup EXIT INT TERM HUP QUIT

WELCOME_URL="https://${SERVER_ID}/loginjs/?gw_id=${GW_ID}&client_mac=$(url_encode "$MAC_CLEAN")&wlan=$(url_encode "$WLAN")&sessionid=${SESSIONID}&ipc=${IPC}"
log_info "wifi_id_nextjs.sh" "Mengakses halaman selamat datang untuk mendapatkan kuki sesi..."
curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
    --connect-timeout 5 --max-time 8 -A "$UA_ANDROID" -c "$COOKIE_JAR" -o /dev/null "$WELCOME_URL" >/dev/null 2>&1

PROTECTED_WIFIID=$(grep "protected-wifiid" "$COOKIE_JAR" 2>/dev/null | awk '{print $NF}')
if [ -z "$PROTECTED_WIFIID" ]; then
    curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
        --connect-timeout 5 --max-time 8 -A "$UA_ANDROID" \
        -H "accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -c "$COOKIE_JAR" -o /dev/null "$WELCOME_URL" >/dev/null 2>&1
fi

AUTH_TIME=$(TZ=WIB-7 date '+%Y-%m-%d %H:%M:%S')
AUTH_TOKEN=$(printf '%s' "${AUTH_SECRET}${AUTH_TIME}${UA_ANDROID}" | md5sum | awk '{print $1}')

LOGIN_ENDPOINT="https://${BACKEND_SERVER}${LOGIN_PATH}"
PAYLOAD_URL="https://${BACKEND_SERVER}/luwak_wifi/?gw_id=${GW_ID}&client_mac=$(url_encode "$MAC_CLEAN")&wlan=$(url_encode "$WLAN")&sessionid=${SESSIONID}"

_apname=$(echo "$WLAN" | awk -F':' '{print $1}')
_ssid=$(echo "$WLAN" | awk -F':' '{print $2}')
[ -z "$_ssid" ] && _ssid="$WLAN"

JSON_PAYLOAD=$(printf '{"username":"%s","password":"%s","gw_id":"%s","ipc":"%s","url":"%s","useragent":"%s","ssid":"%s","mac":"%s","apname":"%s","wlan":"%s"}' \
    "$USERNAME" "$PASSWORD" "$GW_ID" "$IPC" "$PAYLOAD_URL" "$UA_ANDROID" "$_ssid" "$MAC_CLEAN" "$_apname" "$WLAN")

mkdir -p "$DEBUG_DIR"
{
    echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
    echo "PARAMETER:"
    echo "GW_ID=$GW_ID"
    echo "WLAN=$WLAN"
    echo "SESSIONID=$SESSIONID"
    echo "IPC=$IPC"
    echo "MAC=$MAC_CLEAN"
    echo "LOGIN_METHOD=$LOGIN_METHOD"
    echo "SUB_METHOD=$SUB_METHOD"
    echo ""
    echo "ENDPOINT: $LOGIN_ENDPOINT"
    echo "PAYLOAD: $JSON_PAYLOAD"
} > "$DEBUG_DIR/${DEVICE}.log"

log_info "wifi_id_nextjs.sh" "Mengirim data login ke server..."
LOGIN_RESPONSE_RAW=$(curl -s -k --interface "$DEVICE" --resolve "${BACKEND_SERVER}:443:${BACKEND_IP}" \
    --connect-timeout 8 --max-time 15 -X POST \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H "accept: application/json, text/plain, */*" \
    -H "accept-language: id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7" \
    -H "cache-control: no-cache" -H "content-type: application/json" -H "dnt: 1" \
    -H "origin: https://${SERVER_ID}" -H "pragma: no-cache" -H "priority: u=1, i" \
    -H "referer: https://${SERVER_ID}/" \
    -H "sec-ch-ua: $SEC_CH_UA_ANDROID" -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_ANDROID" \
    -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_ANDROID\"" \
    -H "sec-fetch-dest: empty" -H "sec-fetch-mode: cors" -H "sec-fetch-site: same-site" \
    -H "user-agent: $UA_ANDROID" \
    -H "x-authorization-time: $AUTH_TIME" -H "x-authorization-token: $AUTH_TOKEN" \
    --data-raw "$JSON_PAYLOAD" -w "\n%{http_code}" "$LOGIN_ENDPOINT" 2>/dev/null)

CURL_EXIT=$?
LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE_RAW" | tail -1)
RESPONSE=$(echo "$LOGIN_RESPONSE_RAW" | sed '$d')

if [ $CURL_EXIT -ne 0 ]; then
    log_error "wifi_id_nextjs.sh" "Gagal menghubungi server login. Tidak ada respons."
    echo '{"status":"error","message":"Gagal menghubungi server login."}'
    exit 1
fi

if [ "$LOGIN_HTTP_CODE" != "200" ]; then
    log_error "wifi_id_nextjs.sh" "Server login mengembalikan HTTP $LOGIN_HTTP_CODE."
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: error"
        echo "MESSAGE: Server login mengembalikan HTTP $LOGIN_HTTP_CODE"
    } >> "$DEBUG_DIR/${DEVICE}.log"
    echo "{\"status\":\"error\",\"message\":\"Server login mengembalikan HTTP $LOGIN_HTTP_CODE\"}"
    exit 1
fi

if ! echo "$RESPONSE" | grep -qE '^\s*\{.*\}\s*$'; then
    log_error "wifi_id_nextjs.sh" "Respons dari server bukan JSON yang valid."
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: bug"
        echo "MESSAGE: Respons server tidak valid (bukan JSON)."
    } >> "$DEBUG_DIR/${DEVICE}.log"
    echo '{"status":"bug","message":"Respons server tidak valid."}'
    exit 1
fi

{
    echo ""
    echo "RESPONSE HTTP CODE: $LOGIN_HTTP_CODE"
    echo "RESPONSE: $RESPONSE"
    echo "====================================="
} >> "$DEBUG_DIR/${DEVICE}.log"

SUCCESS_MSG=$(echo "$RESPONSE" | grep -o '"reply_message":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SUCCESS_MSG" ] && SUCCESS_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)

if echo "$SUCCESS_MSG" | grep -qiE "parameter not completed|parameter tidak lengkap"; then
    log_error "wifi_id_nextjs.sh" "Parameter tidak lengkap: $SUCCESS_MSG"
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: error"
        echo "MESSAGE: Parameter tidak lengkap: $SUCCESS_MSG"
    } >> "$DEBUG_DIR/${DEVICE}.log"
    echo "{\"status\":\"error\",\"message\":\"Parameter tidak lengkap: $SUCCESS_MSG\",\"server_message\":\"$SUCCESS_MSG\"}"
    exit 1
fi

if echo "$SUCCESS_MSG" | grep -qiE "unauthorized|token tidak valid|token invalid|not authorized"; then
    log_error "wifi_id_nextjs.sh" "Token authorization tidak valid: $SUCCESS_MSG"
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: error"
        echo "MESSAGE: Token authorization tidak valid: $SUCCESS_MSG"
    } >> "$DEBUG_DIR/${DEVICE}.log"
    echo "{\"status\":\"error\",\"message\":\"Token authorization tidak valid. Periksa auth_secret dan waktu sistem.\",\"server_message\":\"$SUCCESS_MSG\"}"
    exit 1
fi
if echo "$SUCCESS_MSG" | grep -qiE "sukses|success|berhasil"; then
    log_info "wifi_id_nextjs.sh" "Login berhasil! Mengalihkan ke halaman akhir..."
    REDIRECT_D=$(printf 'gw_id=%s&client_mac=%s&wlan=%s&sessionid=%s&ipc=%s' \
        "$GW_ID" "$MAC_CLEAN" "$WLAN" "$SESSIONID" "$IPC" | base64 -w 0 2>/dev/null || \
        echo -n "gw_id=$GW_ID&client_mac=$MAC_CLEAN&wlan=$WLAN&sessionid=$SESSIONID&ipc=$IPC" | base64 | tr -d '\n')
    curl -s -k --interface "$DEVICE" --connect-timeout 5 --max-time 8 -A "$UA_ANDROID" -b "$COOKIE_JAR" \
        -o /dev/null "https://${LP_HOST}/?d=${REDIRECT_D}" >/dev/null 2>&1

    INTERNET_OK=0
    ping -I "$DEVICE" -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && INTERNET_OK=1
    if [ $INTERNET_OK -eq 0 ]; then
        CHECK=$(curl -s -k -o /dev/null -w "%{http_code}" --interface "$DEVICE" --connect-timeout 5 --max-time 8 \
            "https://www.google.com/generate_204" 2>/dev/null)
        [ "$CHECK" = "204" ] && INTERNET_OK=1
    fi

    if [ $INTERNET_OK -eq 1 ]; then
        log_info "wifi_id_nextjs.sh" "Koneksi internet sudah aktif."
        echo "{\"status\":\"success\",\"message\":\"Login berhasil! Koneksi internet aktif.\",\"server_message\":\"$SUCCESS_MSG\"}"
    else
        log_info "wifi_id_nextjs.sh" "Login berhasil tapi internet belum terdeteksi. Mungkin perlu waktu."
        echo "{\"status\":\"success\",\"message\":\"Login berhasil, internet belum terdeteksi (mungkin perlu waktu).\",\"server_message\":\"$SUCCESS_MSG\"}"
    fi
else
    ERR_MSG=$(echo "$SUCCESS_MSG" | head -1)
    [ -z "$ERR_MSG" ] && ERR_MSG="Respons tidak dikenali."
    log_error "wifi_id_nextjs.sh" "Login gagal: $ERR_MSG"
    echo "{\"status\":\"error\",\"message\":\"Login gagal: $ERR_MSG\",\"server_message\":\"$ERR_MSG\"}"
fi