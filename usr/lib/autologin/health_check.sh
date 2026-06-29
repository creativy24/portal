#!/bin/sh
# Health Check

. /usr/lib/autologin/logging.sh
. /usr/lib/autologin/captive-detect/detection.conf

dev="$1"
log_info "health_check.sh" "Memeriksa status koneksi interface $dev..."

if [ -f /usr/lib/autologin/routing_lib.sh ]; then
    . /usr/lib/autologin/routing_lib.sh
fi

ip=$(ip -4 addr show dev "$dev" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$ip" ]; then
    log_info "health_check.sh" "Interface $dev tidak memiliki alamat IP."
    echo "NO_IP"
    exit 0
fi

_gw=$(ip route show dev "$dev" 2>/dev/null | awk '/default/{print $3; exit}')
if [ -z "$_gw" ]; then
    _subnet=$(ip route show dev "$dev" 2>/dev/null | grep 'scope link' | head -1 | awk '{print $1}')
    [ -n "$_subnet" ] && _gw=$(echo "$_subnet" | cut -d'/' -f1 | sed 's/\.0$/\.1/')
fi

_mwan3_reserved=$(get_mwan3_reserved)
_mwan3_tables=$(echo "$_mwan3_reserved" | cut -d'|' -f1)
_mwan3_priorities=$(echo "$_mwan3_reserved" | cut -d'|' -f2)
ROUTE_TABLE=$(get_free_route_table "$_mwan3_tables")
POLICY_PRIO=$(get_free_priority "$_mwan3_priorities")

setup_dynamic_routing "$dev" "$ip" "$_gw" "$ROUTE_TABLE" "$POLICY_PRIO"
log_info "health_check.sh" "Policy routing aktif (tabel=$ROUTE_TABLE, prio=$POLICY_PRIO)"

cleanup_route() {
    teardown_dynamic_routing "$ROUTE_TABLE" "$POLICY_PRIO"
    log_info "health_check.sh" "Policy routing dibersihkan"
}
trap cleanup_route EXIT

ip neigh flush dev "$dev" >/dev/null 2>&1

log_info "health_check.sh" "Ping ke 8.8.8.8..."
_ping_ok=0
ping -I "$dev" -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && _ping_ok=1

if [ $_ping_ok -eq 0 ]; then
    log_info "health_check.sh" "Ping gagal: mungkin portal blokir ICMP, lanjut ke HTTP probe"
fi

log_info "health_check.sh" "HTTP probe generate_204..."
_tmp_header="/tmp/health_check_header_$$"

curl --interface "$dev" -s -o /dev/null -D "$_tmp_header" \
    --connect-timeout 3 --max-time 5 \
    "$PROBE_ENDPOINT_PRIMARY" 2>/dev/null

if [ -f "$_tmp_header" ]; then
    _http_code=$(awk 'NR==1 {print $2}' "$_tmp_header" 2>/dev/null)
else
    _http_code=""
fi

log_info "health_check.sh" "HTTP code: $_http_code"

case "$_http_code" in
    204)
        log_info "health_check.sh" "HTTP 204: Internet OK"
        rm -f "$_tmp_header"
        echo "CONNECTED"
        exit 0
        ;;
    301|302|303|307)
        _location=$(grep -i "^Location:" "$_tmp_header" 2>/dev/null | head -1 | sed 's/^[Ll]ocation:[[:space:]]*//' | tr -d '\r\n')
        log_info "health_check.sh" "HTTP $_http_code redirect ke: $_location"
        rm -f "$_tmp_header"
        echo "PORTAL_DETECTED"
        exit 0
        ;;
    200)
        log_info "health_check.sh" "HTTP 200: lanjut ke Layer 3 (cek konten)"
        ;;
    *)
        log_info "health_check.sh" "HTTP $_http_code tidak dikenal, lanjut ke fallback probe"
        ;;
esac

rm -f "$_tmp_header"

if [ "$_http_code" = "200" ]; then
    log_info "health_check.sh" "Layer 3: Download body untuk cek konten..."
    _tmp_body="/tmp/health_check_body_$$"

    curl --interface "$dev" -s -o "$_tmp_body" \
        --connect-timeout 3 --max-time 5 \
        "$PROBE_ENDPOINT_PRIMARY" 2>/dev/null
    
    if [ -s "$_tmp_body" ]; then
        _meta_line=$(grep -i 'http-equiv="refresh"' "$_tmp_body" 2>/dev/null | head -1)
        
        if [ -n "$_meta_line" ]; then
            log_info "health_check.sh" "Meta refresh ditemukan: $_meta_line"
            rm -f "$_tmp_body"
            echo "PORTAL_DETECTED"
            exit 0
        fi
        
        if grep -qiE "$PORTAL_KEYWORDS" "$_tmp_body" 2>/dev/null; then
            log_info "health_check.sh" "Form login/kata kunci portal ditemukan di body (portal advanced)"
            rm -f "$_tmp_body"
            echo "PORTAL_DETECTED"
            exit 0
        fi
        
        log_info "health_check.sh" "Tidak ada meta refresh atau form login: internet bebas"
        rm -f "$_tmp_body"
        echo "CONNECTED"
        exit 0
    else
        log_info "health_check.sh" "Body kosong, lanjut ke fallback probe"
    fi
    
    rm -f "$_tmp_body"
fi

log_info "health_check.sh" "Layer 4: Fallback probe ke endpoints.conf..."
ep=$(grep -v '^\s*#' /usr/lib/autologin/captive-detect/endpoints.conf 2>/dev/null | grep -v '^\s*$' | head -1)

if [ -n "$ep" ]; then
    log_info "health_check.sh" "Probe endpoint: $ep"
    
    _tmp_header="/tmp/health_check_header_fb_$$"
    curl --interface "$dev" -s -o /dev/null -D "$_tmp_header" \
        --connect-timeout 3 --max-time 5 "$ep" 2>/dev/null
    
    if [ -f "$_tmp_header" ]; then
        _code=$(awk 'NR==1 {print $2}' "$_tmp_header" 2>/dev/null)
    else
        _code=""
    fi
    
    log_info "health_check.sh" "Fallback HTTP code: $_code"
    
    case "$_code" in
        204)
            log_info "health_check.sh" "Fallback: Internet OK"
            rm -f "$_tmp_header"
            echo "CONNECTED"
            exit 0
            ;;
        301|302|303|307)
            _location=$(grep -i "^Location:" "$_tmp_header" 2>/dev/null | head -1 | sed 's/^[Ll]ocation:[[:space:]]*//' | tr -d '\r\n')
            log_info "health_check.sh" "Fallback redirect ke: $_location"
            rm -f "$_tmp_header"
            echo "PORTAL_DETECTED"
            exit 0
            ;;
        200)
            _tmp_body="/tmp/health_check_body_fb_$$"
            curl --interface "$dev" -s -o "$_tmp_body" \
                --connect-timeout 3 --max-time 5 "$ep" 2>/dev/null
            
            if [ -s "$_tmp_body" ]; then
                if grep -qiE "http-equiv=\"refresh\"|$PORTAL_KEYWORDS" "$_tmp_body" 2>/dev/null; then
                    log_info "health_check.sh" "Fallback: Portal terdeteksi via konten"
                    rm -f "$_tmp_body" "$_tmp_header"
                    echo "PORTAL_DETECTED"
                    exit 0
                else
                    log_info "health_check.sh" "Fallback: Internet bebas (HTTP 200 tanpa portal)"
                    rm -f "$_tmp_body" "$_tmp_header"
                    echo "CONNECTED"
                    exit 0
                fi
            fi
            rm -f "$_tmp_body"
            ;;
        *)
            log_info "health_check.sh" "Fallback: HTTP $_code - tidak terhubung"
            ;;
    esac
    
    rm -f "$_tmp_header"
fi

log_info "health_check.sh" "Semua probe gagal: interface tidak terhubung"
echo "DISCONNECTED"
exit 0