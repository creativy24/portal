#!/bin/sh
# ============================================================================
# Autologin Heartbeat & Self-Update Script
# ============================================================================

BASE_URL="https://raw.githubusercontent.com/creativy24/portal/main"
WORKER_URL="https://autologin.creativy24.workers.dev"

LICENSE_KEY=$(cat /usr/lib/autologin/.license_key 2>/dev/null)
FINGERPRINT=$(cat /usr/lib/autologin/.fingerprint 2>/dev/null)

if [ -z "$LICENSE_KEY" ] || [ -z "$FINGERPRINT" ]; then
    exit 1
fi

RESPONSE=$(curl -sSL -X POST "$WORKER_URL/validate" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\": \"$LICENSE_KEY\", \"fingerprint\": \"$FINGERPRINT\", \"request_type\": \"heartbeat\"}" 2>/dev/null)

SUCCESS=$(echo "$RESPONSE" | grep -o '"success":true' || true)

if [ -z "$SUCCESS" ]; then
    logger "Autologin: License validation failed. Stopping service."
    /etc/init.d/autologin stop
    echo "expired" > /usr/lib/autologin/.license_status
    exit 1
fi

echo "active" > /usr/lib/autologin/.license_status

LOCAL_VERSION=$(cat /usr/lib/autologin/.version 2>/dev/null || echo "0.0.0")
REMOTE_VERSION=$(curl -sSL "${BASE_URL}/version.txt" 2>/dev/null || echo "0.0.0")

if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
    logger "Autologin: Update available ($LOCAL_VERSION -> $REMOTE_VERSION). Running update..."
    curl -sSL "${BASE_URL}/update.sh" -o /tmp/autologin-update.sh
    chmod +x /tmp/autologin-update.sh
    /tmp/autologin-update.sh
    rm -f /tmp/autologin-update.sh
fi
