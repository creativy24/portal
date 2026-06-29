#!/bin/sh
# Library: Logging Terpusat untuk Autologin

log_info()  { logger -t autologin "[INFO] $1: $2" >/dev/null 2>&1; }
log_error() { logger -t autologin "[ERROR] $1: $2" >/dev/null 2>&1; }
log_debug() { logger -t autologin "[DEBUG] $1: $2" >/dev/null 2>&1; }