#!/bin/sh
# Handler login Hotspot MikroTik (CHAP/PAP)

INPUT_JSON=$(cat)

FUNCTION="login"
URL=$(echo "$INPUT_JSON" | jsonfilter -e '@.url' 2>/dev/null)
USERNAME=$(echo "$INPUT_JSON" | jsonfilter -e '@.username' 2>/dev/null)
PASSWORD=$(echo "$INPUT_JSON" | jsonfilter -e '@.password' 2>/dev/null)
LOGICAL=$(echo "$INPUT_JSON" | jsonfilter -e '@.logical' 2>/dev/null)
DEVICE=$(echo "$INPUT_JSON" | jsonfilter -e '@.device' 2>/dev/null)
MAC=$(echo "$INPUT_JSON" | jsonfilter -e '@.mac' 2>/dev/null)

. /usr/lib/autologin/logging.sh

if [ -z "$URL" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$DEVICE" ]; then
    log_error "hotspot_mikrotik.sh" "Data tidak lengkap. URL, nama pengguna, kata sandi, dan interface wajib diisi."
    echo '{"status":"error","message":"Parameter wajib tidak lengkap."}'
    exit 1
fi

if [ -f /usr/lib/autologin/routing_lib.sh ]; then
    . /usr/lib/autologin/routing_lib.sh
fi

PORTAL_FILE="/usr/lib/autologin/captive-detect/portal.json"
if [ -f "$PORTAL_FILE" ]; then
    UA="${UA:-$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.ua' 2>/dev/null)}"
fi
[ -z "$UA" ] && UA="Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36"

COOKIE_FILE="/tmp/autologin_cookie_${LOGICAL}_mikrotik"
HTML_FILE="/tmp/autologin_html_${LOGICAL}_mikrotik.txt"
DEBUG_DIR="/tmp/autologin/debug"
mkdir -p "$DEBUG_DIR"

ROUTE_TABLE=$(get_free_route_table 2>/dev/null || echo 200)
POLICY_PRIO=$(get_free_priority 2>/dev/null || echo 1000)

cleanup() {
    ip rule del priority $POLICY_PRIO 2>/dev/null
    ip route del default table $ROUTE_TABLE 2>/dev/null
    ip route flush table $ROUTE_TABLE 2>/dev/null
    rm -f "$COOKIE_FILE" "$HTML_FILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

IPC=$(echo "$INPUT_JSON" | jsonfilter -e '@.ipc' 2>/dev/null)
_if_ip="$IPC"
if [ -z "$_if_ip" ] || ! echo "$_if_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    _if_ip=$(ip -4 addr show dev "$DEVICE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
fi

if [ -z "$_if_ip" ]; then
    log_error "hotspot_mikrotik.sh" "Tidak dapat menemukan alamat IP pada interface $DEVICE."
    echo '{"status":"bug","message":"Gagal mendapatkan IP untuk interface fisik.","device":"'"$DEVICE"'"}'
    exit 1
fi

_if_gw=$(ip route show dev "$DEVICE" 2>/dev/null | awk '/default/{print $3; exit}')
if [ -z "$_if_gw" ]; then
    _subnet=$(ip route show dev "$DEVICE" 2>/dev/null | grep 'scope link' | head -1 | awk '{print $1}')
    _if_gw=$(echo "$_subnet" | sed 's/\.0\/.*$/.1/')
fi

log_info "hotspot_mikrotik.sh" "Interface: $DEVICE, IP: $_if_ip, Gateway: $_if_gw."

ip rule del priority $POLICY_PRIO 2>/dev/null
ip route del default table $ROUTE_TABLE 2>/dev/null
ip route flush table $ROUTE_TABLE 2>/dev/null

if [ -n "$_if_gw" ]; then
    ip route add default via "$_if_gw" dev "$DEVICE" table $ROUTE_TABLE 2>/dev/null
else
    ip route add default dev "$DEVICE" table $ROUTE_TABLE 2>/dev/null
fi
ip rule add from "$_if_ip" lookup $ROUTE_TABLE priority $POLICY_PRIO 2>/dev/null

log_info "hotspot_mikrotik.sh" "Routing khusus dipasang (tabel=$ROUTE_TABLE, prioritas=$POLICY_PRIO)."

_scheme=$(printf '%s' "$URL" | awk -F'://' '{print $1}')
_host=$(printf '%s' "$URL" | awk -F'[/:]' '{print $4}')
_port_raw=$(printf '%s' "$URL" | awk -F'[/:]' '{print $5}')

case "$_port_raw" in
    ''|*[!0-9]*) 
        if [ "$_scheme" = "https" ]; then _port=443; else _port=80; fi
        ;;
    *) _port="$_port_raw" ;;
esac

log_info "hotspot_mikrotik.sh" "Host: $_host, Port: $_port, Scheme: $_scheme"

_resolve_arg=""
if [ -n "$_host" ] && [ -n "$_if_gw" ]; then
    _resolve_arg="--resolve ${_host}:${_port}:${_if_gw}"
    log_info "hotspot_mikrotik.sh" "Menggunakan --resolve ${_host}:${_port}:${_if_gw}"
fi

_dst=$(printf '%s' "$URL" | sed -n 's/.*[?&]dst=\([^&]*\).*/\1/p')
[ -z "$_dst" ] && _dst="http://generate_204"

log_info "hotspot_mikrotik.sh" "Mengakses halaman login: $URL"
_http_code=$(curl -s -w "%{http_code}" -o "$HTML_FILE" \
    -c "$COOKIE_FILE" --interface "$DEVICE" $_resolve_arg --connect-timeout 5 --max-time 10 \
    -A "$UA" "$URL" 2>/dev/null)
_curl_exit=$?

if [ "$_curl_exit" -ne 0 ] || [ "$_http_code" = "000" ]; then
    log_error "hotspot_mikrotik.sh" "Gagal mengakses halaman login. Kode HTTP: $_http_code."
    echo "{\"status\":\"error\",\"message\":\"Gagal mengakses halaman login (HTTP $_http_code).\"}"
    exit 1
fi

log_info "hotspot_mikrotik.sh" "Halaman login berhasil diunduh (kode HTTP $_http_code)."

_html=$(cat "$HTML_FILE" 2>/dev/null)

_chap_id=$(printf '%s' "$_html" | grep -oE "name=['\"]chap-id['\"][[:space:]]+value=['\"][^'\"]+['\"]" | head -1 | sed "s/.*value=['\"]//;s/['\"].*//")
_chap_challenge=$(printf '%s' "$_html" | grep -oE "name=['\"]chap-challenge['\"][[:space:]]+value=['\"][^'\"]+['\"]" | head -1 | sed "s/.*value=['\"]//;s/['\"].*//")

if [ -z "$_chap_id" ] || [ -z "$_chap_challenge" ]; then
    _md5_args=$(printf '%s' "$_html" | grep -oE "hexMD5\([^)]+\)" | head -1)
    if [ -n "$_md5_args" ]; then
        [ -z "$_chap_id" ] && _chap_id=$(printf '%s' "$_md5_args" | sed -n "s/.*hexMD5(['\"\`]\([^'\"\`]*\)['\"\`].*/\1/p")
        [ -z "$_chap_challenge" ] && _chap_challenge=$(printf '%s' "$_md5_args" | sed -n "s/.*+[[:space:]]*['\"\`]\([^'\"\`]*\)['\"\`].*/\1/p")
    fi
fi

_final_password="$PASSWORD"
if [ -n "$_chap_id" ] && [ -n "$_chap_challenge" ]; then
    log_info "hotspot_mikrotik.sh" "Metode CHAP terdeteksi. Membuat kata sandi terenkripsi..."
    
    _chap_id_byte=$(printf "%b" "$_chap_id"; echo x)
    _chap_id_byte="${_chap_id_byte%x}"
    
    _chap_challenge_byte=$(printf "%b" "$_chap_challenge"; echo x)
    _chap_challenge_byte="${_chap_challenge_byte%x}"
    
    _hash_input="${_chap_id_byte}${PASSWORD}${_chap_challenge_byte}"
    
    if command -v md5sum >/dev/null 2>&1; then
        _final_password=$(printf '%s' "$_hash_input" | md5sum | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        _final_password=$(printf '%s' "$_hash_input" | openssl md5 | awk '{print $NF}')
    else
        log_error "hotspot_mikrotik.sh" "Alat enkripsi MD5 tidak ditemukan di sistem."
        echo '{"status":"bug","message":"Sistem tidak memiliki alat MD5."}'
        exit 1
    fi
else
    if command -v md5sum >/dev/null 2>&1; then
        _final_password=$(printf '%s' "$PASSWORD" | md5sum | awk '{print $1}')
    fi
    log_info "hotspot_mikrotik.sh" "Metode CHAP tidak ditemukan. Menggunakan kata sandi standar."
fi

log_info "hotspot_mikrotik.sh" "Mengirim data login ke server..."
_http_code_post=$(curl -s -w "%{http_code}" -o "$HTML_FILE" \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE" --interface "$DEVICE" $_resolve_arg --connect-timeout 5 --max-time 10 \
    -A "$UA" \
    --data-urlencode "username=${USERNAME}" \
    --data-urlencode "password=${_final_password}" \
    --data-urlencode "dst=${_dst}" \
    -d "popup=true" \
    "$URL" 2>/dev/null)
_curl_exit_post=$?

_resp=$(cat "$HTML_FILE" 2>/dev/null)

log_info "hotspot_mikrotik.sh" "Kode respons dari server: $_http_code_post."

{
    echo "===== [$(date '+%Y-%m-%d %H:%M:%S')] HOTSPOT LOGIN ====="
    echo "URL: $URL"
    echo "USERNAME: $USERNAME"
    echo "PASSWORD_MD5: $_final_password"
    echo "DST: $_dst"
    echo "HTTP_CODE: $_http_code_post"
    echo "RESPONSE: $_resp"
    echo "======================================================"
} > "$DEBUG_DIR/${DEVICE}.log"

if [ "$_http_code_post" = "302" ] || [ "$_http_code_post" = "301" ]; then
    log_info "hotspot_mikrotik.sh" "Login berhasil! Terjadi pengalihan (kode $_http_code_post)."
    echo "{\"status\":\"success\",\"message\":\"Login berhasil! Anda sekarang terhubung ke internet.\",\"http_code\":\"$_http_code_post\"}"
    exit 0
fi

if [ "$_http_code_post" = "200" ]; then
    if printf '%s' "$_resp" | grep -qiE '<form[^>]*name=["\x27]login["\x27]|<input[^>]*name=["\x27]password["\x27]'; then
        if printf '%s' "$_resp" | grep -qiE 'invalid username or password|user.*is not allowed|session limit reached'; then
            log_error "hotspot_mikrotik.sh" "Login gagal: Nama pengguna atau kata sandi salah, atau batas sesi tercapai."
            echo "{\"status\":\"error\",\"message\":\"Login Gagal: Username/Password salah atau sesi sudah mencapai batas.\",\"http_code\":\"$_http_code_post\"}"
            exit 1
        fi
        log_error "hotspot_mikrotik.sh" "Login gagal: Form login masih muncul. Kredensial ditolak."
        echo "{\"status\":\"error\",\"message\":\"Login Gagal: Kredensial ditolak oleh portal.\",\"http_code\":\"$_http_code_post\"}"
        exit 1
    fi
    
    log_info "hotspot_mikrotik.sh" "Login berhasil! Form login sudah tidak muncul."
    echo "{\"status\":\"success\",\"message\":\"Login berhasil! Anda sekarang terhubung ke internet.\",\"http_code\":\"$_http_code_post\"}"
    exit 0
fi

log_error "hotspot_mikrotik.sh" "Login gagal. Kode respons tidak dikenali: $_http_code_post."
echo "{\"status\":\"error\",\"message\":\"Login Gagal: Respons tidak diharapkan dari portal (HTTP $_http_code_post).\",\"http_code\":\"$_http_code_post\"}"
exit 1