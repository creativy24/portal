#!/bin/sh
# Library: Alokasi routing table, priority, dan utilitas jaringan

. /usr/lib/autologin/logging.sh

ROUTING_LOCK="/var/run/autologin_routing.lock"

_cleanup_routing_lock() {
    rm -f "$ROUTING_LOCK" 2>/dev/null
}

get_mwan3_reserved() {
    _mwan3_tables=""; _mwan3_priorities=""
    if [ -f /etc/config/mwan3 ]; then
        if pgrep -f 'mwan3(track|rtmon)' >/dev/null 2>&1; then
            log_info "routing_lib.sh" "mwan3 terpasang dan sedang aktif."
        else
            log_info "routing_lib.sh" "mwan3 terpasang tetapi tidak aktif."
        fi

        _mwan3_tables=$(ip rule show 2>/dev/null | \
            grep -E 'fwmark.*0x[0-9a-f]+/0x3f00.*lookup' | \
            awk '{for(i=1;i<=NF;i++) if($i=="lookup") print $(i+1)}' | \
            sort -u | tr '\n' ' ')

        _mwan3_priorities=$(ip rule show 2>/dev/null | \
            grep -E 'fwmark.*0x[0-9a-f]+/0x3f00' | \
            awk '{print $1}' | tr -d ':' | grep -E '^[0-9]+$' | sort -n | tr '\n' ' ')

        log_info "routing_lib.sh" "Tabel mwan3 yang digunakan: [$_mwan3_tables], prioritas: [$_mwan3_priorities]"
    else
        log_info "routing_lib.sh" "mwan3 tidak terpasang."
    fi
    printf '%s|%s' "$_mwan3_tables" "$_mwan3_priorities"
}

setup_dynamic_routing() {
	_dev="$1"; _ip="$2"; _gw="$3"; _table="$4"; _prio="$5"
    ip rule del priority "$_prio" >/dev/null 2>&1
    ip route del default table "$_table" >/dev/null 2>&1
    ip route flush table "$_table" >/dev/null 2>&1
    if [ -n "$_gw" ]; then
        ip route add default via "$_gw" dev "$_dev" table "$_table" >/dev/null 2>&1
    else
        ip route add default dev "$_dev" table "$_table" >/dev/null 2>&1
    fi
    ip rule add from "$_ip" lookup "$_table" priority "$_prio" >/dev/null 2>&1
    log_info "routing_lib.sh" "Routing dinamis dipasang: tabel=$_table, prioritas=$_prio, antarmuka=$_dev (IP: $_ip, Gateway: $_gw)."
}

teardown_dynamic_routing() {
	_table="$1"; _prio="$2"
    log_info "routing_lib.sh" "Membersihkan routing dinamis (tabel=$_table, prioritas=$_prio)..."
    ip rule del priority "$_prio" >/dev/null 2>&1
    ip route del default table "$_table" >/dev/null 2>&1
    ip route flush table "$_table" >/dev/null 2>&1
}

get_free_route_table() {
	_reserved="$1"
    [ -n "$_reserved" ] && log_info "routing_lib.sh" "Mencari tabel routing yang kosong (menghindari: $_reserved)."
    exec 201>"$ROUTING_LOCK"
    flock 201
    
    _start=200; _end=250; _table=$_start
    while [ $_table -le $_end ]; do
        if [ -n "$_reserved" ] && echo "$_reserved" | grep -qw "$_table"; then
            _table=$((_table + 1))
            continue
        fi
        if ! ip rule show 2>/dev/null | grep -q "lookup $_table"; then
            if ! ip route show table $_table 2>/dev/null | grep -q .; then
                echo $_table
                log_info "routing_lib.sh" "Tabel routing kosong terpilih: $_table."
                flock -u 201
                return 0
            fi
        fi
        _table=$((_table + 1))
    done
    echo 250
    log_info "routing_lib.sh" "Tidak ada tabel kosong. Menggunakan fallback: 250."
    flock -u 201
}

get_free_priority() {
	_reserved="$1"
    [ -n "$_reserved" ] && log_info "routing_lib.sh" "Mencari prioritas routing yang kosong (menghindari: $_reserved)."
    exec 201>"$ROUTING_LOCK"
    flock 201
    
    _start=1000; _end=2000; _prio=$_start
    _used=$(ip rule show 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n)
    while [ $_prio -le $_end ]; do
        if [ -n "$_reserved" ] && echo "$_reserved" | grep -qw "$_prio"; then
            _prio=$((_prio + 1))
            continue
        fi
        if ! echo "$_used" | grep -q "^$_prio$"; then
            echo $_prio
            log_info "routing_lib.sh" "Prioritas routing kosong terpilih: $_prio."
            flock -u 201
            return 0
        fi
        _prio=$((_prio + 1))
    done
    echo $_start
    log_info "routing_lib.sh" "Tidak ada prioritas kosong. Menggunakan fallback: $_start."
    flock -u 201
}

get_url_param() {
    _url="$1"; _param="$2"
    printf '%s' "$_url" | awk -F'?' -v p="$_param" '
        NR==1 {
            query=$2
            n=split(query, pairs, "&")
            for(i=1;i<=n;i++) {
                split(pairs[i], kv, "=")
                if(kv[1]==p) { print kv[2]; exit }
            }
        }'
}

sanitize_and_normalize_url() {
    printf '%s' "$1" | tr -d '\n\r\000-\037' | awk -F'?' '{
        base=$1
        query=$2
        if (query != "") {
            gsub(/ /, "%20", query)
            print base "?" query
        } else print base
    }'
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

extract_protocol() {
    printf '%s' "$1" | grep -oE '^https?://' | tr -d '://'
}

get_all_param_names() {
    _url="$1"
    _query=$(printf '%s' "$_url" | awk -F'?' '{print $2}')
    [ -z "$_query" ] && return
    echo "$_query" | tr '&' '\n' | awk -F'=' '{print $1}'
}

validate_url() {
    if printf '%s' "$1" | grep -qE '^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$'; then
        return 0
    else
        return 1
    fi
}

extract_url_from_curl() {
    printf '%s' "$1" | sed 's/ [0-9][0-9]*$//'
}

get_logical_if() {
    _dev="$1"
    _UBUS_MAP="$(ubus call network.interface dump 2>/dev/null)"
    if command -v jsonfilter >/dev/null 2>&1; then
        _result=$(echo "$_UBUS_MAP" | jsonfilter -e "@.interface[@.l3_device='$_dev'].interface" 2>/dev/null)
        if [ -n "$_result" ]; then
            echo "$_result"; return 0
        fi
    fi
    echo ""
}

filter_physical_if() {
    _if="$1"

    case "$_if" in
        lo|br-*|docker*|veth*|virbr*|tap*|tun*|sit*|ppp*|6to4*|gre*|gretap*)
            return 1
            ;;
    esac

    if [ -f /etc/board.json ] && command -v ubus >/dev/null 2>&1; then
        _dev_status=$(ubus call network.device status "{\"name\":\"$_if\"}" 2>/dev/null)
        if [ -n "$_dev_status" ]; then
            _up=$(printf '%s' "$_dev_status" | grep -oE '"up":[[:space:]]*(true|false)' | grep -oE 'true|false')
            _present=$(printf '%s' "$_dev_status" | grep -oE '"present":[[:space:]]*(true|false)' | grep -oE 'true|false')

            if [ "$_present" = "true" ] || [ "$_up" = "true" ]; then
                return 0
            fi
            return 1
        fi
    fi

    if [ -f "/sys/class/net/$_if/carrier" ]; then
        return 0
    fi

    return 1
}

randomize_endpoints() {
    _endpoints_file="$1"
    if [ -f "$_endpoints_file" ]; then
        _result=$(grep -v '^\s*#' "$_endpoints_file" 2>/dev/null | grep -v '^\s*$' | awk 'BEGIN{srand()}{print rand()"|"$0}' | sort -t'|' -k1 -n | cut -d'|' -f2)
        if [ -n "$_result" ]; then
            printf '%s' "$_result"
            return 0
        fi
    fi
    return 1
}

cleanup_routing() {
	log_info "routing_lib.sh" "Membersihkan routing dinamis..."
    teardown_dynamic_routing "$ROUTE_TABLE" "$POLICY_PRIORITY"
    log_info "routing_lib.sh" "Routing dinamis sudah dibersihkan (tabel $ROUTE_TABLE, prioritas $POLICY_PRIORITY)."
}

upgrade_to_https() {
    _url="$1"
    _if="$2"

    case "$_url" in
        https://*) 
            log_info "routing_lib.sh" "Alamat sudah menggunakan HTTPS."
            printf '%s' "$_url"
            return 0
            ;;
    esac

    _https_url=$(printf '%s' "$_url" | sed 's|^http://|https://|')
    
    local max_retry=3
    local retry=0
    local last_code=""
    
    while [ $retry -lt $max_retry ]; do
        retry=$((retry + 1))
        log_info "routing_lib.sh" "Mencoba meningkatkan ke HTTPS (percobaan $retry dari $max_retry): $_https_url"
        
        _test_code=$(curl --interface "$_if" -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 2 --max-time 3 -A "$UA_DEFAULT" "$_https_url" 2>/dev/null)
        last_code=$_test_code
        
        case "$_test_code" in
            200|204|301|302|303|307|308)
                log_info "routing_lib.sh" "HTTPS tersedia (kode $_test_code). Menggunakan $_https_url"
                printf '%s' "$_https_url"
                return 0
                ;;
            *)
                log_info "routing_lib.sh" "Percobaan ke-$retry gagal (kode respons: $_test_code)."
                ;;
        esac
    done
    
    log_info "routing_lib.sh" "HTTPS tidak tersedia setelah $max_retry kali percobaan. Tetap menggunakan HTTP."
    printf '%s' "$_url"
    return 0
}

set_mwan3_state() {
    _logical="$1"
    _desired_state="$2"   # "enabled" atau "disabled"

    [ -z "$_logical" ] && { log_error "routing_lib.sh" "[set_mwan3] logical interface wajib diisi"; return 1; }
    [ -z "$_desired_state" ] && { log_error "routing_lib.sh" "[set_mwan3][$_logical] state wajib diisi"; return 1; }

    case "$_desired_state" in
        enabled) _should_enable=1 ;;
        disabled) _should_enable=0 ;;
        *) log_error "routing_lib.sh" "[set_mwan3][$_logical] state tidak valid: $_desired_state"; return 1 ;;
    esac

    local _current=$(uci -q get mwan3."$_logical".enabled 2>/dev/null)
    [ -z "$_current" ] && _current=1

    if [ "$_current" = "$_should_enable" ]; then
        return 0
    fi

    if [ "$_should_enable" = "1" ]; then
        log_info "routing_lib.sh" "[set_mwan3][$_logical] Mengaktifkan interface di mwan3..."
    else
        log_info "routing_lib.sh" "[set_mwan3][$_logical] Menonaktifkan interface di mwan3..."
    fi

    uci set mwan3."$_logical".enabled="$_should_enable"
    uci commit mwan3
    /etc/init.d/mwan3 restart >/dev/null 2>&1
    log_info "routing_lib.sh" "[set_mwan3][$_logical] mwan3 berhasil direstart."
    return 0
}