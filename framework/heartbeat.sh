#!/bin/sh
# ============================================================================
# Autologin Heartbeat & Self-Update Script
# ============================================================================

BASE_URL="https://raw.githubusercontent.com/creativy24/portal/main"
WORKER_URL="https://autologin.creativy24.workers.dev"

log_info() { logger -t autologin "[INFO] $1"; }
log_warn() { logger -t autologin "[WARN] $1"; }
log_error() { logger -t autologin "[ERROR] $1"; }

LICENSE_KEY=$(cat /usr/lib/autologin/.license_key 2>/dev/null)
FINGERPRINT=$(cat /usr/lib/autologin/.fingerprint 2>/dev/null)

if [ -z "$LICENSE_KEY" ] || [ -z "$FINGERPRINT" ]; then
    log_error "Metadata tidak ditemukan. Service akan dihentikan."
    /etc/init.d/autologin stop
    exit 1
fi

log_info "Checking file integrity..."
HASH_FILE="/usr/lib/autologin/.file_hashes"

if [ -f "$HASH_FILE" ]; then
    TAMPERED=0
    
    while read -r expected_hash file; do
        if [ -f "$file" ]; then
            actual_hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
            if [ "$expected_hash" != "$actual_hash" ]; then
                log_error "FILE MODIFIED: $file"
                log_error "Expected: $expected_hash"
                log_error "Actual:   $actual_hash"
                TAMPERED=1
            fi
        else
            log_error "FILE MISSING: $file"
            TAMPERED=1
        fi
    done < "$HASH_FILE"
    
    if [ "$TAMPERED" -eq 1 ]; then
        log_error "Integrity check failed! Service will be stopped."
        echo "tampered" > /usr/lib/autologin/.license_status
        /etc/init.d/autologin stop
        exit 1
    fi
    
    log_info "Integrity check passed. All files OK."
else
    log_warn "Hash file not found: $HASH_FILE"
fi

log_info "Validating license..."
RESPONSE=$(curl -sSL -X POST "$WORKER_URL/validate" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"request_type\": \"heartbeat\"}" 2>/dev/null)

SUCCESS=$(echo "$RESPONSE" | grep -o '"success":true' || true)

if [ -z "$SUCCESS" ]; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
    log_error "License validation failed: $ERROR_MSG"
    /etc/init.d/autologin stop
    echo "expired" > /usr/lib/autologin/.license_status
    exit 1
fi

echo "active" > /usr/lib/autologin/.license_status
log_info "License valid."

log_info "Checking for updates..."
LOCAL_VERSION=$(cat /usr/lib/autologin/.version 2>/dev/null || echo "0.0.0")
REMOTE_VERSION=$(curl -sSL "${BASE_URL}/version.txt" 2>/dev/null || echo "0.0.0")

if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
    log_info "Update available: $LOCAL_VERSION -> $REMOTE_VERSION"
    
    curl -sSL "${BASE_URL}/update.sh" -o /tmp/autologin-update.sh
    chmod +x /tmp/autologin-update.sh
    
    /tmp/autologin-update.sh
    UPDATE_STATUS=$?
    
    rm -f /tmp/autologin-update.sh
    
    if [ "$UPDATE_STATUS" -eq 0 ]; then
        log_info "Update completed successfully."
    else
        log_error "Update failed with status $UPDATE_STATUS"
    fi
else
    log_info "Already up to date (v$LOCAL_VERSION)."
fi

log_info "Heartbeat completed."
exit 0
