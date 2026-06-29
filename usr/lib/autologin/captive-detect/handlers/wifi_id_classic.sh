#!/bin/sh
# Handler login wifi.id Classic

INPUT_JSON=$(cat)

FUNCTION="login"
URL=$(echo "$INPUT_JSON" | jsonfilter -e '@.url' 2>/dev/null)
USERNAME=$(echo "$INPUT_JSON" | jsonfilter -e '@.username' 2>/dev/null)
ORIGINAL_USERNAME=$(echo "$INPUT_JSON" | jsonfilter -e '@.original_username' 2>/dev/null)
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
COOKIE_JAR="/tmp/autologin_cookie_${LOGICAL}_wifi_id_classic"
TIMEOUT=10

PORTAL_FILE="/usr/lib/autologin/captive-detect/portal.json"
LP_HOST=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[@.type_key='WIFI_ID' && @.handler_script='wifi_id_classic.sh'].lp_host" 2>/dev/null)
if [ -z "$LP_HOST" ]; then
    log_error "wifi_id_classic.sh" "lp_host tidak ditemukan di portal.json untuk handler classic."
    echo '{"status":"error","message":"Konfigurasi portal tidak lengkap."}'
    exit 1
fi

. /usr/lib/autologin/logging.sh

get_ip() { grep -F "$1" "$BACKEND_FILE" 2>/dev/null | awk '{print $2}' | head -1; }

if [ -f /usr/lib/autologin/routing_lib.sh ]; then
    . /usr/lib/autologin/routing_lib.sh
else
    log_error "wifi_id_classic.sh" "Library routing_lib.sh tidak ditemukan."
    echo '{"status":"error","message":"Library routing_lib.sh tidak ditemukan."}'
    exit 1
fi

if [ -f "$PORTAL_FILE" ]; then
    UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.ua' 2>/dev/null)
    SEC_CH_UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua' 2>/dev/null)
    SEC_CH_UA_PLATFORM_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_platform' 2>/dev/null)
    SEC_CH_UA_MOBILE_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_mobile' 2>/dev/null)
fi

if [ -z "$UA_ANDROID" ]; then
    log_error "wifi_id_classic.sh" "Fingerprint Android tidak tersedia di portal.json."
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
url_encode_wlan() { echo "$1" | sed 's/ /%20/g'; }
MAC_ENCODED=$(echo "$MAC_CLEAN" | sed 's/:/%3A/g')

log_info "wifi_id_classic.sh" "Memulai login WiFi.id Klasik. Interface: $LOGICAL, Perangkat: $DEVICE."

if [ "$GW_ID" = "unknown" ] || [ "$WLAN" = "unknown" ] || [ "$SESSIONID" = "unknown" ]; then
    log_error "wifi_id_classic.sh" "Data sesi tidak lengkap. GW_ID, WLAN, atau SESSIONID tidak ditemukan."
    echo '{"status":"error","message":"Parameter session grid tidak lengkap."}'
    exit 1
fi

SERVER_ID=$(echo "$URL" | awk -F'[/:]' '{print $4}')
RESOLVE_IP=$(get_ip "$SERVER_ID")
if [ -z "$RESOLVE_IP" ]; then
    log_error "wifi_id_classic.sh" "IP untuk $SERVER_ID tidak ditemukan di backend_hosts.conf."
    echo '{"status":"error","message":"Resolusi IP server gagal."}'
    exit 1
fi

_if_ip="$IPC"
_if_gw=$(ip route show dev "$DEVICE" 2>/dev/null | awk '/default/{print $3; exit}')
[ -z "$_if_gw" ] && _if_gw=$(ip route show dev "$DEVICE" 2>/dev/null | grep 'scope link' | head -1 | awk '{print $1}' | sed 's/\.0\/.*$/.1/')

ROUTE_TABLE=$(get_free_route_table)
POLICY_PRIO=$(get_free_priority)
setup_dynamic_routing "$DEVICE" "$_if_ip" "$_if_gw" "$ROUTE_TABLE" "$POLICY_PRIO"

cleanup() { teardown_dynamic_routing "$ROUTE_TABLE" "$POLICY_PRIO"; rm -f "$COOKIE_JAR" 2>/dev/null; }
trap cleanup EXIT INT TERM HUP QUIT

LANDING_URL="https://${SERVER_ID}/loginocs/?gw_id=${GW_ID}&client_mac=${MAC_CLEAN}&wlan=$(url_encode_wlan "$WLAN")&sessionid=${SESSIONID}"

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
    echo "ORIGINAL_USERNAME=$ORIGINAL_USERNAME"
    echo "USERNAME=$USERNAME"
} > "$DEBUG_DIR/${DEVICE}.log"

log_info "wifi_id_classic.sh" "Mengakses halaman awal untuk mendapatkan token keamanan..."
HTTP_CODE_LANDING=$(curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
    --connect-timeout 5 --max-time 8 -A "$UA_ANDROID" -c "$COOKIE_JAR" -o /dev/null -w "%{http_code}" \
    -H "accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    -H "sec-ch-ua: $SEC_CH_UA_ANDROID" \
    -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_ANDROID" \
    -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_ANDROID\"" \
    -H "upgrade-insecure-requests: 1" \
    "$LANDING_URL" 2>/dev/null)
if [ "$HTTP_CODE_LANDING" != "200" ]; then
    log_error "wifi_id_classic.sh" "Halaman landing tidak dapat diakses (HTTP $HTTP_CODE_LANDING)."
    echo '{"status":"error","message":"Halaman landing tidak dapat diakses."}'
    exit 1
fi
{
    echo ""
    echo "--- Landing Page ---"
    echo "ENDPOINT: $LANDING_URL"
    echo "RESPONSE HTTP CODE: $HTTP_CODE_LANDING"
} >> "$DEBUG_DIR/${DEVICE}.log"

CSRF_TOKEN=$(grep "csrf_token_wp" "$COOKIE_JAR" 2>/dev/null | awk '{print $NF}')
if [ -z "$CSRF_TOKEN" ]; then
    log_info "wifi_id_classic.sh" "Token tidak ditemukan, mencoba lagi dengan header tambahan..."
    HTTP_CODE_LANDING=$(curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
        --connect-timeout 5 --max-time 8 -A "$UA_ANDROID" -c "$COOKIE_JAR" -o /dev/null -w "%{http_code}" \
        -H "accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "sec-ch-ua: $SEC_CH_UA_ANDROID" \
        -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_ANDROID" \
        -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_ANDROID\"" \
        -H "upgrade-insecure-requests: 1" \
        -H "cache-control: no-cache" \
        -H "pragma: no-cache" \
        "$LANDING_URL" 2>/dev/null)
    CSRF_TOKEN=$(grep "csrf_token_wp" "$COOKIE_JAR" 2>/dev/null | awk '{print $NF}')
    {
        echo "--- Landing Page (Retry) ---"
        echo "RESPONSE HTTP CODE: $HTTP_CODE_LANDING"
    } >> "$DEBUG_DIR/${DEVICE}.log"
fi

{
    echo "CSRF_TOKEN: ${CSRF_TOKEN:-TIDAK DITEMUKAN}"
} >> "$DEBUG_DIR/${DEVICE}.log"

if [ -z "$CSRF_TOKEN" ]; then
    log_error "wifi_id_classic.sh" "Gagal mendapatkan token keamanan dari halaman awal."
    echo '{"status":"error","message":"Gagal mendapatkan token sesi dari portal."}'
    exit 1
fi

log_info "wifi_id_classic.sh" "Token keamanan berhasil didapatkan."

log_info "wifi_id_classic.sh" "Mengirim data login ke server..."

PASSWORD_RAW="$PASSWORD"
LOAD_WP=$(date +%s%3N 2>/dev/null || date +%s000)

if [ -n "$ORIGINAL_USERNAME" ] && [ "$LOGIN_METHOD" = "Komunitas" ] && [ "$SUB_METHOD" = "Kampus" ]; then
    DOMAIN_ASLI=$(echo "$ORIGINAL_USERNAME" | sed 's/.*@//')
    DOMAIN_TARGET=$(echo "$USERNAME" | sed 's/.*@//')
    LOCAL_PART=$(echo "$USERNAME" | sed 's/@.*//')
    FINAL_USERNAME="${LOCAL_PART}@${DOMAIN_ASLI}@${DOMAIN_TARGET}"
else
    FINAL_USERNAME="$USERNAME"
fi

CHECK_LOGIN_URL="https://${SERVER_ID}/authnew/login/check_login.php?ipc=${IPC}&gw_id=${GW_ID}&mac=${MAC_CLEAN}&redirect=&wlan=$(url_encode_wlan "$WLAN")&load_wp=${LOAD_WP}"
CHECK_LOGIN_PAYLOAD=$(printf 'username=%s&password=%s&landURL=' "$FINAL_USERNAME" "$PASSWORD_RAW")

RESPONSE=$(curl -s -k --interface "$DEVICE" --resolve "${SERVER_ID}:443:${RESOLVE_IP}" \
    --connect-timeout 8 --max-time 15 -X POST \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H "accept: application/json, text/javascript, */*; q=0.01" \
    -H "accept-language: id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7" \
    -H "cache-control: no-cache" -H "content-type: application/x-www-form-urlencoded; charset=UTF-8" \
    -H "dnt: 1" -H "origin: https://${SERVER_ID}" -H "pragma: no-cache" \
    -H "referer: ${LANDING_URL}" \
    -H "sec-ch-ua: $SEC_CH_UA_ANDROID" -H "sec-ch-ua-mobile: $SEC_CH_UA_MOBILE_ANDROID" \
    -H "sec-ch-ua-platform: \"$SEC_CH_UA_PLATFORM_ANDROID\"" \
    -H "sec-fetch-dest: empty" -H "sec-fetch-mode: cors" -H "sec-fetch-site: same-origin" \
    -H "user-agent: $UA_ANDROID" \
    -H "x-requested-with: XMLHttpRequest" \
    --data-raw "$CHECK_LOGIN_PAYLOAD" "$CHECK_LOGIN_URL" 2>/dev/null)

CURL_EXIT=$?

{
    echo ""
    echo "--- check_login ---"
    echo "ENDPOINT: $CHECK_LOGIN_URL"
    echo "PAYLOAD: $CHECK_LOGIN_PAYLOAD"
    echo "RESPONSE: $RESPONSE"
} >> "$DEBUG_DIR/${DEVICE}.log"

if [ $CURL_EXIT -ne 0 ]; then
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: error"
        echo "MESSAGE: Gagal menghubungi server login (curl exit code: $CURL_EXIT)"
    } >> "$DEBUG_DIR/${DEVICE}.log"
    log_error "wifi_id_classic.sh" "Gagal menghubungi server login. Tidak ada respons."
    echo '{"status":"error","message":"Gagal menghubungi server login."}'
    exit 1
fi
if ! echo "$RESPONSE" | grep -qE '^\s*\{.*\}\s*$'; then
    log_error "wifi_id_classic.sh" "Respons dari server bukan JSON yang valid."
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: bug"
        echo "MESSAGE: Respons server tidak valid (bukan JSON)."
    } >> "$DEBUG_DIR/${DEVICE}.log"
    echo '{"status":"bug","message":"Respons server tidak valid."}'
    exit 1
fi
SUCCESS_MSG=$(echo "$RESPONSE" | grep -o '"reply_message":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SUCCESS_MSG" ] && SUCCESS_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)

if echo "$SUCCESS_MSG" | grep -qiE "parameter not completed|parameter tidak lengkap"; then
    log_error "wifi_id_classic.sh" "Parameter tidak lengkap: $SUCCESS_MSG"
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: error"
        echo "MESSAGE: Parameter tidak lengkap: $SUCCESS_MSG"
    } >> "$DEBUG_DIR/${DEVICE}.log"
    echo "{\"status\":\"error\",\"message\":\"Parameter tidak lengkap: $SUCCESS_MSG\",\"server_message\":\"$SUCCESS_MSG\"}"
    exit 1
fi
if echo "$SUCCESS_MSG" | grep -qiE "sukses|success|berhasil"; then
    log_info "wifi_id_classic.sh" "LOGIN BERHASIL"
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
        log_info "wifi_id_classic.sh" "Koneksi internet sudah aktif."
        echo "{\"status\":\"success\",\"message\":\"Login berhasil! Koneksi internet aktif.\",\"server_message\":\"$SUCCESS_MSG\"}"
    else
        log_info "wifi_id_classic.sh" "Login berhasil tapi internet belum terdeteksi. Mungkin perlu waktu."
        echo "{\"status\":\"success\",\"message\":\"Login berhasil, internet belum terdeteksi (mungkin perlu waktu).\",\"server_message\":\"$SUCCESS_MSG\"}"
    fi
else
    ERR_MSG=$(echo "$SUCCESS_MSG" | head -1)
    [ -z "$ERR_MSG" ] && ERR_MSG="Respons tidak dikenali."
    {
        echo ""
        echo "--- Hasil Akhir ---"
        echo "STATUS: error"
        echo "MESSAGE: Login gagal: $ERR_MSG"
    } >> "$DEBUG_DIR/${DEVICE}.log"
    log_error "wifi_id_classic.sh" "Login gagal: $ERR_MSG"
    echo "{\"status\":\"error\",\"message\":\"Login gagal: $ERR_MSG\",\"server_message\":\"$ERR_MSG\"}"
fi