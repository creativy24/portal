#!/bin/sh
# MAC SPOOF DETECTION LIBRARY

. /usr/lib/autologin/logging.sh

MAC_CACHE_DIR=$(uci -q get autologin.config.cache_dir 2>/dev/null)
MAC_CACHE_DIR="${MAC_CACHE_DIR:-/etc/autologin}"
MAC_CACHE_FILE="mac_spoof.cache"; MAC_CACHE_PATH="${MAC_CACHE_DIR}/${MAC_CACHE_FILE}"
MAC_TEST_ADDR="02:11:22:33:44:55"

get_rep_if() {
    ls /sys/class/net 2>/dev/null | grep -Ev '^(lo|br-|docker|veth|virbr|tap|tun|sit|ppp|6to4|gre|gretap)' | head -1
}

is_dsa_bridge_member() {
    _line=$(uci -q show network 2>/dev/null | grep -e "\.name='"$1"'" | head -1)
    [ -z "$_line" ] && return 1
    _section=$(echo "$_line" | cut -d'=' -f1 | sed 's/\.[^.]*$//')
    uci -q show network 2>/dev/null | grep -q "^${_section}\.type='bridge'"
}

check_mac_spoof_support() {
    mkdir -p "$MAC_CACHE_DIR" 2>/dev/null
    if [ -f "$MAC_CACHE_PATH" ]; then cat "$MAC_CACHE_PATH"; return 0; fi

    _now=$(date +%s)
    _rep_if=$(get_rep_if)
    if [ -z "$_rep_if" ]; then
        log_info "mac_spoof.sh" "Tidak ada interface yang tersedia untuk pengujian MAC spoof."
        _res='{"supported":false,"level":"no_interface","checked_at":'$_now'}'
        echo "$_res" > "$MAC_CACHE_PATH"
        echo "$_res"
        return 0
    fi
    
    if is_dsa_bridge_member "$_rep_if"; then
        log_info "mac_spoof.sh" "Interface $_rep_if adalah anggota bridge. Pengujian MAC spoof dilewati."
        _res='{"supported":false,"level":"bridge_skip","checked_at":'$_now'}'
        echo "$_res" > "$MAC_CACHE_PATH"
        echo "$_res"
        return 0
    fi

    _orig_mac=$(cat "/sys/class/net/$_rep_if/address" 2>/dev/null | tr 'a-z' 'A-Z' | sed 's/[[:space:]]//g')
    case "$_orig_mac" in [0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]) ;; *)
        log_info "mac_spoof.sh" "Alamat MAC pada interface $_rep_if tidak valid."
        _res='{"supported":false,"level":"invalid_mac","checked_at":'$_now'}'
        echo "$_res" > "$MAC_CACHE_PATH"
        echo "$_res"
        return 0
    ;; esac

    _operstate=$(cat "/sys/class/net/$_rep_if/operstate" 2>/dev/null)
    _has_default=$(ip route show dev "$_rep_if" 2>/dev/null | grep -c "^default" 2>/dev/null || echo 0)
    if [ "$_operstate" = "up" ] && [ "$_has_default" -gt 0 ]; then
        log_info "mac_spoof.sh" "Interface $_rep_if sedang aktif digunakan. Pengujian MAC spoof dilewati."
        _res='{"supported":false,"level":"skipped_active","checked_at":'$_now'}'
        echo "$_res" > "$MAC_CACHE_PATH"
        echo "$_res"
        return 0
    fi

    _level="none"
    ip link set dev "$_rep_if" down 2>/dev/null
    if ip link set dev "$_rep_if" address "$MAC_TEST_ADDR" 2>/dev/null; then
        _cur_mac=$(cat "/sys/class/net/$_rep_if/address" 2>/dev/null | tr 'a-z' 'A-Z' | sed 's/[[:space:]]//g')
        case "$_cur_mac" in "$MAC_TEST_ADDR")
            _level="kernel"
            log_info "mac_spoof.sh" "MAC spoof didukung pada tingkat kernel."
            ;;
        *)
            _level="driver"
            log_info "mac_spoof.sh" "MAC spoof didukung pada tingkat driver."
            ;;
        esac
    fi
    ip link set dev "$_rep_if" address "$_orig_mac" 2>/dev/null
    if ! ip link show dev "$_rep_if" 2>/dev/null | grep -qi "link/ether $_orig_mac"; then
        log_error "mac_spoof.sh" "Gagal mengembalikan MAC asli pada interface $_rep_if!"
        _level="rollback_fail"
        _result="false"
    else
        case "$_level" in kernel|driver) _result="true" ;; *) _result="false" ;; esac
    fi
    ip link set dev "$_rep_if" up 2>/dev/null

    _res='{"supported":'$_result',"level":"'$_level'","checked_at":'$_now'}'
    echo "$_res" > "$MAC_CACHE_PATH"
    echo "$_res"
    log_info "mac_spoof.sh" "Hasil pengujian MAC spoof: didukung=$_result, tingkat=$_level."
    return 0
}