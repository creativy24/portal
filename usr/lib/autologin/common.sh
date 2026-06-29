#!/bin/sh
# Deteksi Portal

. /usr/lib/autologin/logging.sh

CONFIG_DIR="/usr/lib/autologin/captive-detect"
ENDPOINTS_FILE="$CONFIG_DIR/endpoints.conf"
PORTAL_FILE="$CONFIG_DIR/portal.json"
LOCK_FILE="/var/run/captive_portal_detect.lock"
COOKIE_BASE="/tmp/autologin_cookie_"
TIMEOUT_CONNECT=3; TIMEOUT_MAX=5; MAX_REDIRECT=5

. /usr/lib/autologin/captive-detect/detection.conf

log_info "common.sh" "Mulai deteksi portal"

. /usr/lib/autologin/routing_lib.sh

if [ -f "$PORTAL_FILE" ]; then
    UA_DEFAULT=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.ua' 2>/dev/null)
    SEC_CH_UA=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.sec_ch_ua' 2>/dev/null)
    SEC_CH_UA_PLATFORM=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.sec_ch_ua_platform' 2>/dev/null)
    SEC_CH_UA_MOBILE=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.desktop.sec_ch_ua_mobile' 2>/dev/null)    
    UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.ua' 2>/dev/null)
    SEC_CH_UA_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua' 2>/dev/null)
    SEC_CH_UA_PLATFORM_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_platform' 2>/dev/null)
    SEC_CH_UA_MOBILE_ANDROID=$(jsonfilter -i "$PORTAL_FILE" -e '@.fingerprint.android.sec_ch_ua_mobile' 2>/dev/null)
    
    PORTAL_PATTERNS_COUNT=$(jsonfilter -i "$PORTAL_FILE" -e '@.patterns[*].type_key' 2>/dev/null | wc -l)
    
    log_info "common.sh" "Konfigurasi portal dimuat ($PORTAL_PATTERNS_COUNT pola)"
else
    log_error "common.sh" "File portal.json tidak ditemukan: $PORTAL_FILE"
fi

detect_portal_type() {
    _url="$1"
    _if="$2"
    _gw="$3"
    
    _path=$(printf '%s' "$_url" | sed 's|^https\?://[^/]*||' | awk -F'?' '{print $1}')
    [ -z "$_path" ] && _path="/"
    
    _domain=$(printf '%s' "$_url" | awk -F'/' '{print $3}' | awk -F':' '{print $1}')
    _query=$(printf '%s' "$_url" | awk -F'?' '{print $2}')
    
    log_info "common.sh" "Deteksi portal_type untuk path: $_path"
    
    _i=0
    while [ $_i -lt $PORTAL_PATTERNS_COUNT ]; do
        _path_key=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_i].path_key" 2>/dev/null)
        _query_key=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_i].query_key" 2>/dev/null)
        _type_key=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_i].type_key" 2>/dev/null)
        
        if [ -n "$_path_key" ] && [ "$_path_key" != "null" ]; then
            if echo "$_path" | grep -qF "$_path_key"; then
                log_info "common.sh" "Portal terdeteksi via path: $_type_key"
                echo "$_type_key"
                return 0
            fi
        fi
        
        if [ -n "$_query_key" ] && [ "$_query_key" != "null" ]; then
            if [ -n "$_query" ] && echo "$_query" | grep -qF "$_query_key"; then
                log_info "common.sh" "Portal terdeteksi via query: $_type_key"
                echo "$_type_key"
                return 0
            fi
        fi
        
        _i=$((_i + 1))
    done
    
    log_info "common.sh" "Tidak ada path/query cocok, download halaman untuk signature matching..."
    _html_file="/tmp/autologin_portal_check_$$"
    
    _curl_code=$(curl --interface "$_if" -s --connect-timeout 5 --max-time 10 -o "$_html_file" -w "%{http_code}" "$_url" 2>/dev/null)
    _curl_exit=$?
    
    if [ $_curl_exit -ne 0 ] || [ ! -s "$_html_file" ]; then
        if [ -n "$_gw" ]; then
            log_info "common.sh" "Download gagal, coba bypass via gateway $_gw"
            _bypass_url="http://$_gw$_path"
            [ -n "$_query" ] && _bypass_url="${_bypass_url}?${_query}"
            
            _curl_code=$(curl --interface "$_if" -s --connect-timeout 5 --max-time 10 \
                -H "Host: $_domain" \
                -o "$_html_file" -w "%{http_code}" "$_bypass_url" 2>/dev/null)
        fi
    fi
    
    log_info "common.sh" "Download halaman selesai (HTTP: $_curl_code, exit: $_curl_exit)"
    
    if [ -f "$_html_file" ] && [ -s "$_html_file" ]; then
        _j=0
        while [ $_j -lt $PORTAL_PATTERNS_COUNT ]; do
            _path_key=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_j].path_key" 2>/dev/null)
            _query_key=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_j].query_key" 2>/dev/null)
            _html_sig=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_j].html_signature" 2>/dev/null)
            _type_key=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_j].type_key" 2>/dev/null)
            
            if { [ -z "$_path_key" ] || [ "$_path_key" = "null" ]; } && { [ -z "$_query_key" ] || [ "$_query_key" = "null" ]; }; then
                if [ -n "$_html_sig" ] && [ "$_html_sig" != "null" ]; then
                    if grep -qF "$_html_sig" "$_html_file" 2>/dev/null; then
                        log_info "common.sh" "Portal terdeteksi via HTML: $_type_key"
                        rm -f "$_html_file"
                        echo "$_type_key"
                        return 0
                    fi
                fi
            fi
            _j=$((_j + 1))
        done
    fi
    
    if [ -f "$_html_file" ] && [ -s "$_html_file" ]; then
        if grep -qF "$HTML_SIGNATURE_HOTSPOT" "$_html_file" 2>/dev/null; then
            log_info "common.sh" "Portal terdeteksi via HTML signature: HOTSPOT (MikroTik)"
            rm -f "$_html_file"
            echo "HOTSPOT"
            return 0
        fi
        
        if grep -qiE "$HTML_SIGNATURE_WIFI_ID" "$_html_file" 2>/dev/null; then
            log_info "common.sh" "Portal terdeteksi via HTML signature: WIFI_ID"
            rm -f "$_html_file"
            echo "WIFI_ID"
            return 0
        fi
        
        if grep -qiE "$HTML_SIGNATURE_WMS" "$_html_file" 2>/dev/null; then
            log_info "common.sh" "Portal terdeteksi via HTML signature: WMS"
            rm -f "$_html_file"
            echo "WMS"
            return 0
        fi
        
        if grep -qiE "$HTML_SIGNATURE_GENERIC" "$_html_file" 2>/dev/null; then
            log_info "common.sh" "Portal terdeteksi via HTML signature: GENERIC"
            rm -f "$_html_file"
            echo "GENERIC"
            return 0
        fi
    fi
    
    rm -f "$_html_file"
    
    log_info "common.sh" "Fallback: UNKNOWN"
    echo "UNKNOWN"
    return 0
}

follow_redirects() {
    _start_url="$1"; _if="$2"; _cookie_file="$3"; _max_redirect=$MAX_REDIRECT; _current_url="$_start_url"; _count=0

    while [ $_count -lt $_max_redirect ]; do
        log_info "common.sh" "Redirect #$(($_count + 1)): request ke $_current_url via $_if"
        _curl_output=$(curl --interface "$_if" -L -s -o /dev/null -w "%{url_effective} %{http_code}" \
            --connect-timeout $TIMEOUT_CONNECT --max-time $TIMEOUT_MAX \
            -A "$UA_DEFAULT" --cookie-jar "$_cookie_file" --cookie "$_cookie_file" "$_current_url" 2>/dev/null)
        _next_url=$(extract_url_from_curl "$_curl_output")

        if [ -z "$_next_url" ] || [ "$_next_url" = "$_current_url" ]; then
            log_info "common.sh" "Redirect berakhir di $_current_url"
            break
        fi

        _current_url="$_next_url"; _count=$((_count + 1))
        if [ $_count -ge $_max_redirect ]; then
            log_info "common.sh" "Batas maksimum redirect tercapai ($_max_redirect), berhenti di $_current_url"
            break
        fi
    done

    log_info "common.sh" "URL akhir: $_current_url"
    printf '%s' "$(sanitize_and_normalize_url "$_current_url")"
}

test_portal_with_policy() {
    _if="$1"; _ip="$2"; _cookie_file="${COOKIE_BASE}${_if}"

    log_info "common.sh" "Deteksi portal dgn policy routing"
    log_info "common.sh" "Interface: $_if, IP: $_ip"

    _randomized_endpoints=$(randomize_endpoints "$ENDPOINTS_FILE")
    [ -z "$_randomized_endpoints" ] && _randomized_endpoints="$ENDPOINTS"

    _gw=$(ip route show dev "$_if" 2>/dev/null | awk '/default/{print $3; exit}')
    if [ -z "$_gw" ]; then
        _subnet=$(ip route show dev "$_if" 2>/dev/null | grep -v default | awk '/scope link/ {print $1}' | head -1)
        [ -n "$_subnet" ] && _gw=$(echo "$_subnet" | cut -d'/' -f1 | sed 's/\.0$/\.1/')
    fi

    log_info "common.sh" "Gateway: $_gw"

    setup_dynamic_routing "$_if" "$_ip" "$_gw" "$ROUTE_TABLE" "$POLICY_PRIORITY"
    log_info "common.sh" "Policy routing aktif (tabel=$ROUTE_TABLE, prio=$POLICY_PRIORITY)"

    _portal_url=""; _result=1

    for ep in $_randomized_endpoints; do
        _tmp_header="/tmp/curl_header_$$"
        log_info "common.sh" "Uji endpoint: $ep"

        curl --interface "$_if" -s -o /dev/null -D "$_tmp_header" \
            --connect-timeout $TIMEOUT_CONNECT --max-time $TIMEOUT_MAX \
            -A "$UA_DEFAULT" --cookie-jar "$_cookie_file" --cookie "$_cookie_file" "$ep" 2>/dev/null

        if [ -f "$_tmp_header" ]; then
            _code=$(awk 'NR==1 {print $2}' "$_tmp_header" 2>/dev/null)
        else
            _code=""
        fi

        log_info "common.sh" "Respon: $_code dari $ep"

        case "$_code" in
            204)
                log_info "common.sh" "HTTP 204: internet OK, tidak ada portal"
                ;;
            301|302|307|303)
                log_info "common.sh" "HTTP $_code: redirect, kemungkinan portal"
                _initial_url=$(grep -i "^Location:" "$_tmp_header" 2>/dev/null | head -1 | sed 's/^[Ll]ocation:[[:space:]]*//' | tr -d '\r\n')
                log_info "common.sh" "Redirect ke: $_initial_url"

                if validate_url "$_initial_url"; then
                    log_info "common.sh" "URL redirect valid, ikuti redirect..."
                    _portal_url=$(follow_redirects "$_initial_url" "$_if" "$_cookie_file")
                    if [ -n "$_portal_url" ]; then
                        _portal_url=$(upgrade_to_https "$_portal_url" "$_if")
                    fi
                    _result=0
                    log_info "common.sh" "Portal terdeteksi (redirect chain)"
                else
                    log_info "common.sh" "URL redirect tidak valid, lewati"
                fi
                rm -f "$_tmp_header"; break
                ;;
            200)
                log_info "common.sh" "HTTP 200: cek meta refresh dan konten..."
                _body=$(curl --interface "$_if" -s -m 5 -A "$UA_DEFAULT" --cookie-jar "$_cookie_file" --cookie "$_cookie_file" "$ep" 2>/dev/null)
                _meta_line=$(echo "$_body" | grep -i 'http-equiv="refresh"' 2>/dev/null | head -1)

                if [ -n "$_meta_line" ]; then
                    log_info "common.sh" "Meta refresh ditemukan"
                    _initial_url=$(echo "$_meta_line" | sed -n 's/.*URL=\([^"'\''>]*\).*/\1/p' | head -1)
                    [ -z "$_initial_url" ] && _initial_url=$(echo "$_meta_line" | sed -n 's/.*content="[^"]*URL=\([^"]*\)".*/\1/p' | head -1)
                    log_info "common.sh" "URL meta refresh: $_initial_url"

                    if validate_url "$_initial_url"; then
                        log_info "common.sh" "URL meta refresh valid, ikuti redirect..."
                        _portal_url=$(follow_redirects "$_initial_url" "$_if" "$_cookie_file")
                        if [ -n "$_portal_url" ]; then
                            _portal_url=$(upgrade_to_https "$_portal_url" "$_if")
                        fi
                        _result=0
                        log_info "common.sh" "Portal terdeteksi (meta refresh)"
                    fi
                elif echo "$_body" | grep -qiE "$PORTAL_KEYWORDS" 2>/dev/null; then
                    log_info "common.sh" "Portal advanced terdeteksi via konten HTML (HTTP 200 + form login/kata kunci portal)"
                    _portal_url="$ep"
                    _result=0
                else
                    log_info "common.sh" "Tidak ada meta refresh atau konten portal: internet bebas"
                fi
                rm -f "$_tmp_header"; break
                ;;
            *)
                log_info "common.sh" "HTTP $_code tidak dikenal, lewati"
                ;;
        esac
        rm -f "$_tmp_header"
    done

    log_info "common.sh" "Bersihkan policy routing"
    teardown_dynamic_routing "$ROUTE_TABLE" "$POLICY_PRIORITY"

    if [ $_result -eq 0 ]; then
        log_info "common.sh" "Deteksi berhasil"
        log_info "common.sh" "URL portal final: $_portal_url"
        printf '%s' "$_portal_url" | tr -d '\n\r\000-\037'
        return 0
    else
        rm -f "$_cookie_file" 2>/dev/null
        log_info "common.sh" "Deteksi gagal"
        log_info "common.sh" "Tidak ada portal di $_if"
        echo ""
        return 1
    fi
}

detect_portal() {
    _if="$1"; _ip="$2"
    log_info "common.sh" "Mulai deteksi portal untuk $_if"
    log_info "common.sh" "IP: $_ip"

    log_info "common.sh" "Langkah 1: ping 8.8.8.8 (cek koneksi)"
    _ping_ok=0
    ping -I "$_if" -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && _ping_ok=1

    if [ $_ping_ok -eq 0 ]; then
        log_info "common.sh" "Ping gagal: mungkin portal blokir ICMP"
        log_info "common.sh" "Langkah 2: deteksi HTTP via policy routing"
        _portal_url=$(test_portal_with_policy "$_if" "$_ip")
        _result=$?
        if [ $_result -eq 0 ] && [ -n "$_portal_url" ]; then
            _portal_url=$(upgrade_to_https "$_portal_url" "$_if")
        fi
        printf '%s' "$_portal_url"
        return $_result
    fi

    log_info "common.sh" "Ping OK, internet tersedia, lanjut cek HTTP"
    _tmp_body="/tmp/autologin_probe_$$"
    _first_ep=$(echo "$ENDPOINTS" | head -1)
    log_info "common.sh" "Langkah 2: unduh $_first_ep"

    _code=$(curl --interface "$_if" -s -o "$_tmp_body" -w "%{http_code}" \
        --connect-timeout 2 --max-time 3 -A "$UA_DEFAULT" "$_first_ep" 2>/dev/null)

    if [ "$_code" = "200" ] && [ -s "$_tmp_body" ]; then
        log_info "common.sh" "HTTP 200, cek meta refresh dan konten..."
        _meta_line=$(grep -i 'http-equiv="refresh"' "$_tmp_body" 2>/dev/null | head -1)

        if [ -n "$_meta_line" ]; then
            log_info "common.sh" "Meta refresh ditemukan"
            _initial_url=$(echo "$_meta_line" | sed -n 's/.*URL=\([^"'\''>]*\).*/\1/p' | head -1)
            [ -z "$_initial_url" ] && _initial_url=$(echo "$_meta_line" | sed -n 's/.*content="[^"]*URL=\([^"]*\)".*/\1/p' | head -1)
            log_info "common.sh" "URL meta refresh: $_initial_url"

            if validate_url "$_initial_url"; then
                log_info "common.sh" "Ikuti redirect meta..."
                _cookie_file="${COOKIE_BASE}${_if}"
                _portal_url=$(follow_redirects "$_initial_url" "$_if" "$_cookie_file")
                if [ -n "$_portal_url" ]; then
                    _portal_url=$(upgrade_to_https "$_portal_url" "$_if")
                fi
                rm -f "$_tmp_body"
                printf '%s' "$_portal_url"
                return 0
            fi
        elif grep -qiE "$PORTAL_KEYWORDS" "$_tmp_body" 2>/dev/null; then
            log_info "common.sh" "Portal advanced terdeteksi via konten HTML (HTTP 200 + form login/kata kunci portal)"
            _portal_url="$_first_ep"
            rm -f "$_tmp_body"
            printf '%s' "$_portal_url"
            return 0
        else
            log_info "common.sh" "Tidak ada meta refresh atau konten portal: internet bebas"
        fi
    else
        log_info "common.sh" "HTTP $_code diterima - Tidak ada portal atau koneksi bermasalah"
    fi

    rm -f "$_tmp_body"
    log_info "common.sh" "Tidak ada portal di $_if"
    echo ""; return 1
}

add_json() {
    _if="$1"; _dev="$2"; _ip="$3"; _gateway="$4"; _status="$5"; _url="$6"; _mac="$7"

    _logical=$(get_logical_if "$_dev"); [ -z "$_logical" ] && _logical="unknown"

    _type=$(detect_portal_type "$_url" "$_if" "$_gateway")
    
    _normalize=""
    _force_https="false"
    _add_ipc="false"
    _i=0
    while [ $_i -lt $PORTAL_PATTERNS_COUNT ]; do
        _p_type=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_i].type_key" 2>/dev/null)
        if [ "$_p_type" = "$_type" ]; then
            _norm=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_i].normalize_path" 2>/dev/null)
            if [ -n "$_norm" ] && [ "$_norm" != "null" ] && [ "$_norm" != "" ]; then
                _normalize="$_norm"
            fi
            _fh=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_i].force_https" 2>/dev/null)
            if [ "$_fh" = "true" ]; then
                _force_https="true"
            fi
            _ai=$(jsonfilter -i "$PORTAL_FILE" -e "@.patterns[$_i].add_ipc" 2>/dev/null)
            if [ "$_ai" = "true" ]; then
                _add_ipc="true"
            fi
            break
        fi
        _i=$((_i + 1))
    done
    
    if [ -n "$_normalize" ]; then
        _old_path=$(printf '%s' "$_url" | sed 's|^https\?://[^/]*||' | awk -F'?' '{print $1}')
        _url=$(printf '%s' "$_url" | sed "s|$_old_path|$_normalize|")
    fi
    
    if [ "$_force_https" = "true" ]; then
        _url=$(printf '%s' "$_url" | sed 's|^http://|https://|')
    fi

    if [ "$_add_ipc" = "true" ] && [ -n "$_ip" ] && ! echo "$_url" | grep -q 'ipc='; then
        if echo "$_url" | grep -q '?'; then
            _url="${_url}&ipc=${_ip}"
        else
            _url="${_url}?ipc=${_ip}"
        fi
    fi

    _logical=$(json_escape "$_logical")
    _dev=$(json_escape "$_dev")
    _url=$(json_escape "$_url")
    _mac=$(json_escape "$_mac")
    _gateway=$(json_escape "$_gateway")
    _ip=$(json_escape "$_ip")

    _protocol=$(extract_protocol "$_url")
    [ -z "$_protocol" ] && _protocol="unknown"

    _ipc="$_ip"

    _extra_fields=""
    _param_names=$(get_all_param_names "$_url")
    for _pname in $_param_names; do
        [ "$_pname" = "ipc" ] && continue
        _pval=$(get_url_param "$_url" "$_pname")
        _pval=$(json_escape "$_pval")
        _extra_fields="$_extra_fields\"$_pname\":\"$_pval\","
    done

    _item=$(printf '{"interface":"%s","device":"%s","ip":"%s","gateway":"%s","mac":"%s","status":"%s","portal_url":"%s","portal_type":"%s","portal_protocol":"%s",%s"ipc":"%s"}' \
        "$_logical" "$_dev" "$_ip" "$_gateway" "$_mac" "$_status" "$_url" \
        "$_type" "$_protocol" "$_extra_fields" "$_ipc")

    if [ $FIRST -eq 1 ]; then
        JSON_OUTPUT="{\"interfaces\":[$_item"
        FIRST=0
    else
        JSON_OUTPUT="$JSON_OUTPUT,$_item"
    fi
}

SCAN_TARGET="${1:-}"
if [ -n "$SCAN_TARGET" ]; then
    log_info "common.sh" "Mode scan per-interface untuk: $SCAN_TARGET"
fi

if [ -f "$ENDPOINTS_FILE" ]; then
    ENDPOINTS=$(grep -v '^\s*#' "$ENDPOINTS_FILE" 2>/dev/null | grep -v '^\s*$' 2>/dev/null)
    if [ -z "$ENDPOINTS" ]; then
        log_error "common.sh" "File endpoints kosong/hanya komentar"
        echo '{"interfaces":[]}'
        exit 1
    fi
    log_info "common.sh" "Endpoint dimuat: $(echo "$ENDPOINTS" | wc -w) endpoint"
else
    log_error "common.sh" "File endpoints tidak ada: $ENDPOINTS_FILE"
    echo '{"interfaces":[]}'
    exit 1
fi

exec 200>"$LOCK_FILE"
flock -n 200 || {
    echo '{"interfaces":[]}'
    exit 0
}

log_info "common.sh" "Cari tabel routing & prioritas bebas mwan3"
_mwan3_reserved=$(get_mwan3_reserved)
_mwan3_tables=$(echo "$_mwan3_reserved" | cut -d'|' -f1)
_mwan3_priorities=$(echo "$_mwan3_reserved" | cut -d'|' -f2)
ROUTE_TABLE=$(get_free_route_table "$_mwan3_tables")
POLICY_PRIORITY=$(get_free_priority "$_mwan3_priorities")
log_info "common.sh" "Alokasi: tabel=$ROUTE_TABLE, prio=$POLICY_PRIORITY"

trap 'cleanup_routing' EXIT INT TERM HUP QUIT
log_info "common.sh" "Trap cleanup terpasang (EXIT/INT/TERM/HUP/QUIT)"

JSON_OUTPUT=""; FIRST=1
portal_count=0

log_info "common.sh" "Mulai iterasi interface fisik"
if [ -n "$SCAN_TARGET" ]; then
    INTERFACE_LIST="$SCAN_TARGET"
else
    INTERFACE_LIST=$(ls /sys/class/net 2>/dev/null)
fi
for ifname in $INTERFACE_LIST; do
    ifname=$(echo "$ifname" | cut -d'@' -f1)

    if ! filter_physical_if "$ifname"; then
        continue
    fi

    ipaddr=$(ip -4 addr show "$ifname" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    if [ -z "$ipaddr" ]; then
        log_info "common.sh" "$ifname tidak punya IPv4, lewati"
        continue
    fi
    log_info "common.sh" "IPv4: $ipaddr"

    macaddr=$(cat /sys/class/net/"$ifname"/address 2>/dev/null | tr '[:lower:]' '[:upper:]')
    [ -z "$macaddr" ] && macaddr="UNKNOWN"
    log_info "common.sh" "MAC: $macaddr"

    gateway=""
    logical=$(get_logical_if "$ifname")
    if [ -n "$logical" ] && [ "$logical" != "unknown" ]; then
        _UBUS_MAP="$(ubus call network.interface dump 2>/dev/null)"
        if command -v jsonfilter >/dev/null 2>&1; then
            gateway=$(echo "$_UBUS_MAP" | jsonfilter -e "@.interface[@.interface='$logical'].route[@.target='0.0.0.0'].nexthop" 2>/dev/null)
            [ -z "$gateway" ] && gateway=$(echo "$_UBUS_MAP" | jsonfilter -e "@.interface[@.interface='$logical'].route[@.target='0.0.0.0'].gateway" 2>/dev/null)
        fi
    fi
    [ -z "$gateway" ] && gateway=$(ip route show dev "$ifname" 2>/dev/null | awk '/default/ {print $3; exit}')
    log_info "common.sh" "Gateway: $gateway, logical: $logical"

    log_info "common.sh" "Mulai deteksi portal di $ifname..."
    portal_url=$(detect_portal "$ifname" "$ipaddr")

    if [ $? -eq 0 ] && [ -n "$portal_url" ]; then
        log_info "common.sh" "Portal terdeteksi di $ifname"
        log_info "common.sh" "URL portal mentah: $portal_url"
        add_json "$ifname" "$ifname" "$ipaddr" "$gateway" "Portal_Login" "$portal_url" "$macaddr"
        portal_count=$((portal_count + 1))
    else
        log_info "common.sh" "Tidak ada portal di $ifname"
    fi
done

log_info "common.sh" "Iterasi selesai"

if [ $FIRST -eq 0 ]; then
    printf '%s]}\n' "$JSON_OUTPUT"
    log_info "common.sh" "Selesai: Ditemukan $portal_count interface dengan portal"
else
    echo '{"interfaces":[]}'
    log_info "common.sh" "Selesai: tidak ada portal"
fi

log_info "common.sh" "Deteksi portal selesai"