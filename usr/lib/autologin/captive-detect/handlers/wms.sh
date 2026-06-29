#!/bin/sh
# Handler login WMS

INPUT_JSON=$(cat)

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
COOKIE_JAR="/tmp/autologin_cookie_${LOGICAL}_wms"
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
        if [ "$p_type" = "WMS" ] && [ "$p_handler" = "wms.sh" ]; then
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
    log_error "wms.sh" "Library routing_lib.sh tidak ditemukan."
    echo '{"status":"error","message":"Library routing_lib.sh tidak ditemukan."}'
    exit 1
fi

if [ -f "$PORTAL_FILE" ]; then
    UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.ua' 2>/dev/null)
    SEC_CH_UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua' 2>/dev/null)
    SEC_CH_UA_PLATFORM_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_platform' 2>/dev/null)
    SEC_CH_UA_MOBILE_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_mobile' 2>/dev/null)

    UA_DESKTOP=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.ua' 2>/dev/null)
    SEC_CH_UA_DESKTOP=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.sec_ch_ua' 2>/dev/null)
    SEC_CH_UA_PLATFORM_DESKTOP=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.sec_ch_ua_platform' 2>/dev/null)
    SEC_CH_UA_MOBILE_DESKTOP=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.sec_ch_ua_mobile' 2>/dev/null)
fi

if [ -z "$UA_ANDROID" ]; then
    log_error "wms.sh" "Fingerprint Android tidak tersedia di portal.json."
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

log_info "wms.sh" "Memulai login WMS. Interface: $LOGICAL, Perangkat: $DEVICE."

if [ "$GW_ID" = "unknown" ] || [ "$WLAN" = "unknown" ] || [ "$SESSIONID" = "unknown" ]; then
    log_error "wms.sh" "Data sesi tidak lengkap. GW_ID, WLAN, atau SESSIONID tidak ditemukan."
    echo '{"status":"error","message":"Parameter session grid tidak lengkap."}'
    exit 1
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

WELCOME_URL="https://${SERVER_ID}/wms/?gw_id=${GW_ID}&client_mac=${MAC_CLEAN}&wlan=$(url_encode "$WLAN")&sessionid=${SESSIONID}"
log_info "wms.sh" "Mengakses halaman landing WMS untuk mendapatkan data sesi..."

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
    echo "WELCOME URL: $WELCOME_URL"
} > "$DEBUG_DIR/${DEVICE}.log"

beforeloadwp=$(awk '{print $1}' < /proc/uptime)

HTTP_CODE_WELCOME=$(curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
    --connect-timeout 5 --max-time 8 -A "$UA_ANDROID" -c "$COOKIE_JAR" -o /dev/null -w "%{http_code}" \
    -H "accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
    -H "accept-language: id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7" \
    -H "cache-control: no-cache" \
    -H "pragma: no-cache" \
    -H "sec-ch-ua: $SEC_CH_UA_ANDROID" \
    -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_ANDROID" \
    -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_ANDROID\"" \
    -H "upgrade-insecure-requests: 1" \
    "$WELCOME_URL" 2>/dev/null)

if [ "$HTTP_CODE_WELCOME" != "200" ]; then
    log_error "wms.sh" "Halaman landing tidak dapat diakses (HTTP $HTTP_CODE_WELCOME)."
    echo '{"status":"error","message":"Halaman landing tidak dapat diakses."}'
    exit 1
fi

{
    echo ""
    echo "--- Landing Page ---"
    echo "RESPONSE HTTP CODE: $HTTP_CODE_WELCOME"
} >> "$DEBUG_DIR/${DEVICE}.log"

wp=$(curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
    --connect-timeout 5 --max-time 8 -A "$UA_ANDROID" -b "$COOKIE_JAR" \
    -H "accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
    -H "accept-language: id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7" \
    -H "cache-control: no-cache" \
    -H "pragma: no-cache" \
    -H "sec-ch-ua: $SEC_CH_UA_ANDROID" \
    -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_ANDROID" \
    -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_ANDROID\"" \
    -H "upgrade-insecure-requests: 1" \
    "$WELCOME_URL" 2>/dev/null)

afterloadwp=$(awk '{print $1}' < /proc/uptime)

CSRF_TOKEN=$(grep "csrf_token_wp" "$COOKIE_JAR" 2>/dev/null | awk '{print $NF}')
DEFAULT_WIFI=$(grep "default_wifi" "$COOKIE_JAR" 2>/dev/null | awk '{print $NF}')

SESSION_KEY=$(echo "$wp" | awk -F'\\\\+"session_key\\\\+":\\\\+"' 'NF>1{split($2,a,"\\\\\"");sub(/\\\\+$/,"",a[1]);print a[1];exit}')
WMS_SID=$(echo "$wp" | awk -F'\\\\+"SID\\\\+":\\\\+"' 'NF>1{split($2,a,"\\\\\"");sub(/\\\\+$/,"",a[1]);print a[1];exit}')

{
    echo "CSRF_TOKEN: ${CSRF_TOKEN:-TIDAK DITEMUKAN}"
    echo "DEFAULT_WIFI: ${DEFAULT_WIFI:-TIDAK DITEMUKAN}"
    echo "SESSION_KEY: ${SESSION_KEY:-TIDAK DITEMUKAN}"
    echo "WMS_SID: ${WMS_SID:-TIDAK DITEMUKAN}"
} >> "$DEBUG_DIR/${DEVICE}.log"

if [ -z "$SESSION_KEY" ]; then
    log_error "wms.sh" "Gagal mendapatkan session_key dari halaman landing."
    echo '{"status":"error","message":"Gagal mendapatkan session key dari portal."}'
    exit 1
fi

AUTH_TIME=$(TZ=WIB-7 date '+%Y-%m-%d %H:%M:%S')
AUTH_TOKEN=$(printf '%s' "${AUTH_SECRET}${AUTH_TIME}${UA_ANDROID}" | md5sum | awk '{print $1}')

LOGIN_ENDPOINT="https://${BACKEND_SERVER}${LOGIN_PATH}"
PAYLOAD_URL="https://${BACKEND_SERVER}/luwak_wifi/?gw_id=${GW_ID}&client_mac=$(url_encode "$MAC_CLEAN")&wlan=$(url_encode "$WLAN")&sessionid=${SESSIONID}"

_apname=$(echo "$WLAN" | awk -F':' '{print $1}')
_ssid=$(echo "$WLAN" | awk -F':' '{print $2}')
[ -z "$_ssid" ] && _ssid="$WLAN"

LOAD_TIME=$(awk 'BEGIN {print ("'"$afterloadwp"'"-"'"$beforeloadwp"'") * 100 + int(rand()*15000) }')

JSON_PAYLOAD=$(printf '{"username":"%s","password":"%s","gw_id":"%s","ipc":"%s","url":"%s","useragent":"%s","key":"","otp":"","ssid":"%s","mac":"%s","apname":"%s","wlan":"%s","sessionid":"%s","session_key":"%s","load_time":%s,"latitude":null,"longitude":null}' \
    "$USERNAME" "$PASSWORD" "$GW_ID" "$IPC" "$PAYLOAD_URL" "$UA_ANDROID" "$_ssid" "$MAC_CLEAN" "$_apname" "$WLAN" "$SESSIONID" "$SESSION_KEY" "$LOAD_TIME")

log_info "wms.sh" "Mengirim data login ke server..."

LOGIN_RESPONSE_RAW=$(curl -s -k --interface "$DEVICE" --resolve "${BACKEND_SERVER}:443:${BACKEND_IP}" \
    --connect-timeout 8 --max-time 15 -X POST \
    -b "$COOKIE_JAR" \
    -H "accept: application/json, text/plain, */*" \
    -H "accept-language: id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7" \
    -H "cache-control: no-cache" \
    -H "content-type: application/json" \
    -H "dnt: 1" \
    -H "origin: https://${SERVER_ID}" \
    -H "pragma: no-cache" \
    -H "priority: u=1, i" \
    -H "referer: https://${SERVER_ID}/" \
    -H "sec-ch-ua: $SEC_CH_UA_DESKTOP" \
    -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_DESKTOP" \
    -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_DESKTOP\"" \
    -H "sec-fetch-dest: empty" \
    -H "sec-fetch-mode: cors" \
    -H "sec-fetch-site: same-site" \
    -H "user-agent: $UA_ANDROID" \
    -H "x-authorization-time: $AUTH_TIME" \
    -H "x-authorization-token: $AUTH_TOKEN" \
    -H "Cookie: csrf_token_wp=$CSRF_TOKEN; default_wifi=$DEFAULT_WIFI" \
    --data-raw "$JSON_PAYLOAD" -w "\n%{http_code}" "$LOGIN_ENDPOINT" 2>/dev/null)

CURL_EXIT=$?
LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE_RAW" | tail -1)
RESPONSE=$(echo "$LOGIN_RESPONSE_RAW" | sed '$d')

{
    echo ""
    echo "--- Login ---"
    echo "ENDPOINT: $LOGIN_ENDPOINT"
    echo "PAYLOAD: $JSON_PAYLOAD"
    echo "RESPONSE HTTP CODE: $LOGIN_HTTP_CODE"
    echo "RESPONSE: $RESPONSE"
} >> "$DEBUG_DIR/${DEVICE}.log"

if [ $CURL_EXIT -ne 0 ]; then
    log_error "wms.sh" "Gagal menghubungi server login."
    echo '{"status":"error","message":"Gagal menghubungi server login."}'
    exit 1
fi

if [ "$LOGIN_HTTP_CODE" != "200" ]; then
    log_error "wms.sh" "Server login mengembalikan HTTP $LOGIN_HTTP_CODE."
    echo "{\"status\":\"error\",\"message\":\"Server login mengembalikan HTTP $LOGIN_HTTP_CODE\"}"
    exit 1
fi

if ! echo "$RESPONSE" | grep -qE '^\s*\{.*\}\s*$'; then
    log_error "wms.sh" "Respons dari server bukan JSON yang valid."
    echo '{"status":"bug","message":"Respons server tidak valid."}'
    exit 1
fi

SUCCESS_MSG=$(echo "$RESPONSE" | grep -o '"reply_message":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SUCCESS_MSG" ] && SUCCESS_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)

if echo "$SUCCESS_MSG" | grep -qiE "parameter not completed|parameter tidak lengkap"; then
    log_error "wms.sh" "Parameter tidak lengkap: $SUCCESS_MSG"
    echo "{\"status\":\"error\",\"message\":\"Parameter tidak lengkap: $SUCCESS_MSG\",\"server_message\":\"$SUCCESS_MSG\"}"
    exit 1
fi

if echo "$SUCCESS_MSG" | grep -qiE "sukses|success|berhasil"; then
    log_info "wms.sh" "Login berhasil. Menyimpan autologin ke server..."

    STORE_URL="https://${SERVER_ID}/wmsjs/api/store-autologin/"

    STORE_INNER_PAYLOAD=$(printf '{"wlan":"%s","client_mac":"%s","gw_id":"%s","sessionid":"%s","ipc":"%s","session_key":"%s","username":"%s","password":"%s","useragent":"%s","sid":"%s","autologin":"%s","pageLoadTime":%s,"latitude":null,"longitude":null}' \
        "$WLAN" "$MAC_CLEAN" "$GW_ID" "$SESSIONID" "$IPC" "$SESSION_KEY" "$USERNAME" "$PASSWORD" "$UA_ANDROID" "$WMS_SID" "yes" "$LOAD_TIME")

    STORE_OUTER_PAYLOAD=$(printf '{"client_mac":"%s","autologin_time":%s,"payload":%s}' \
        "$MAC_CLEAN" "86400" "$STORE_INNER_PAYLOAD")

    STORE_RESPONSE=$(curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
        --connect-timeout 5 --max-time 10 -X POST \
        -H "accept: application/json, text/plain, */*" \
        -H "content-type: application/json" \
        -H "origin: https://${SERVER_ID}" \
        -H "referer: https://${SERVER_ID}/" \
        -H "user-agent: $UA_ANDROID" \
        -H "x-authorization-time: $AUTH_TIME" \
        -H "x-authorization-token: $AUTH_TOKEN" \
        -H "Cookie: csrf_token_wp=$CSRF_TOKEN; default_wifi=$DEFAULT_WIFI" \
        --data-raw "$STORE_OUTER_PAYLOAD" "$STORE_URL" 2>/dev/null)

    {
        echo ""
        echo "--- Store Autologin ---"
        echo "ENDPOINT: $STORE_URL"
        echo "PAYLOAD: $STORE_OUTER_PAYLOAD"
        echo "RESPONSE: $STORE_RESPONSE"
    } >> "$DEBUG_DIR/${DEVICE}.log"

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

    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: success"
        echo "MESSAGE: Login berhasil! Koneksi internet aktif."
        echo "INTERNET_CHECK: ping=$([ $INTERNET_OK -eq 1 ] && echo 'OK' || echo 'FAIL'), google_204=$([ "$CHECK" = "204" ] && echo 'OK' || echo 'FAIL')"
    } >> "$DEBUG_DIR/${DEVICE}.log"

    if [ $INTERNET_OK -eq 1 ]; then
        log_info "wms.sh" "Koneksi internet sudah aktif."
        echo "{\"status\":\"success\",\"message\":\"Login berhasil! Koneksi internet aktif.\",\"server_message\":\"$SUCCESS_MSG\"}"
    else
        log_info "wms.sh" "Login berhasil tapi internet belum terdeteksi. Mungkin perlu waktu."
        echo "{\"status\":\"success\",\"message\":\"Login berhasil, internet belum terdeteksi (mungkin perlu waktu).\",\"server_message\":\"$SUCCESS_MSG\"}"
    fi
else
    ERR_MSG=$(echo "$SUCCESS_MSG" | head -1)
    [ -z "$ERR_MSG" ] && ERR_MSG="Respons tidak dikenali."
    log_error "wms.sh" "Login gagal: $ERR_MSG"
    echo "{\"status\":\"error\",\"message\":\"Login gagal: $ERR_MSG\",\"server_message\":\"$ERR_MSG\"}"
fi