#!/bin/sh
# Auto-Update Script untuk AutoLogin
# Repo: https://github.com/creativy24/portal

REPO="https://raw.githubusercontent.com/creativy24/portal/main"
CHATTR=$(which chattr 2>/dev/null || echo /usr/bin/chattr)
LOCK_FILE="/var/run/autologin-update.lock"
LOG_TAG="autologin"

# Cegah duplikasi
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    logger -t "$LOG_TAG" "[AUTO-UPDATE] Proses update sedang berjalan, dilewati."
    exit 0
fi

logger -t "$LOG_TAG" "[AUTO-UPDATE] Memeriksa pembaruan..."

TMP_DIR="/tmp/autologin-update"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Daftar file yang dimonitor (remote_path:local_path)
FILES="
etc/hotplug.d/iface/99-autologin:/etc/hotplug.d/iface/99-autologin
etc/init.d/autologin:/etc/init.d/autologin
usr/bin/autologin:/usr/bin/autologin
usr/lib/lua/luci/controller/autologin.lua:/usr/lib/lua/luci/controller/autologin.lua
usr/lib/lua/luci/view/autologin/index.htm:/usr/lib/lua/luci/view/autologin/index.htm
usr/lib/autologin/anti_blocking.sh:/usr/lib/autologin/anti_blocking.sh
usr/lib/autologin/auto_timezone.sh:/usr/lib/autologin/auto_timezone.sh
usr/lib/autologin/common.sh:/usr/lib/autologin/common.sh
usr/lib/autologin/daemon.sh:/usr/lib/autologin/daemon.sh
usr/lib/autologin/health_check.sh:/usr/lib/autologin/health_check.sh
usr/lib/autologin/logging.sh:/usr/lib/autologin/logging.sh
usr/lib/autologin/login_executor.sh:/usr/lib/autologin/login_executor.sh
usr/lib/autologin/logout.sh:/usr/lib/autologin/logout.sh
usr/lib/autologin/mac_apply.sh:/usr/lib/autologin/mac_apply.sh
usr/lib/autologin/mac_spoof.sh:/usr/lib/autologin/mac_spoof.sh
usr/lib/autologin/routing_lib.sh:/usr/lib/autologin/routing_lib.sh
usr/lib/autologin/telegram_notify.sh:/usr/lib/autologin/telegram_notify.sh
usr/lib/autologin/update_json.lua:/usr/lib/autologin/update_json.lua
usr/lib/autologin/captive-detect/backend_hosts.conf:/usr/lib/autologin/captive-detect/backend_hosts.conf
usr/lib/autologin/captive-detect/detection.conf:/usr/lib/autologin/captive-detect/detection.conf
usr/lib/autologin/captive-detect/endpoints.conf:/usr/lib/autologin/captive-detect/endpoints.conf
usr/lib/autologin/captive-detect/portal.json:/usr/lib/autologin/captive-detect/portal.json
usr/lib/autologin/captive-detect/handlers/hotspot_mikrotik.sh:/usr/lib/autologin/captive-detect/handlers/hotspot_mikrotik.sh
usr/lib/autologin/captive-detect/handlers/wifi_id_classic.sh:/usr/lib/autologin/captive-detect/handlers/wifi_id_classic.sh
usr/lib/autologin/captive-detect/handlers/wifi_id_nextjs.sh:/usr/lib/autologin/captive-detect/handlers/wifi_id_nextjs.sh
usr/lib/autologin/captive-detect/handlers/wms.sh:/usr/lib/autologin/captive-detect/handlers/wms.sh
www/luci-static/resources/autologin.css:/www/luci-static/resources/autologin.css
www/luci-static/resources/autologin.js:/www/luci-static/resources/autologin.js
www/luci-static/resources/donate.png:/www/luci-static/resources/donate.png
"

UPDATED=0

for entry in $FILES; do
    remote_path=$(echo "$entry" | cut -d: -f1)
    local_path=$(echo "$entry" | cut -d: -f2)

    # Buat direktori sementara
    mkdir -p "$TMP_DIR/$(dirname "$remote_path")"

    # Unduh file dari GitHub
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -o "$TMP_DIR/$remote_path" "$REPO/$remote_path" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$TMP_DIR/$remote_path" "$REPO/$remote_path" 2>/dev/null
    else
        logger -t "$LOG_TAG" "[AUTO-UPDATE] ERROR: curl atau wget tidak ditemukan!"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # Bandingkan checksum
    if [ -f "$local_path" ] && [ -f "$TMP_DIR/$remote_path" ]; then
        LOCAL_SHA=$(sha256sum "$local_path" 2>/dev/null | awk '{print $1}')
        REMOTE_SHA=$(sha256sum "$TMP_DIR/$remote_path" | awk '{print $1}')

        if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
            logger -t "$LOG_TAG" "[AUTO-UPDATE] Memperbarui: $local_path"

            # Hapus immutable
            $CHATTR -i "$local_path" 2>/dev/null

            # Ganti file
            cat "$TMP_DIR/$remote_path" > "$local_path"
            chmod 0755 "$local_path"

            # Pasang kembali immutable
            $CHATTR +i "$local_path" 2>/dev/null

            UPDATED=1
        fi
    fi
done

rm -rf "$TMP_DIR"

if [ $UPDATED -eq 1 ]; then
    logger -t "$LOG_TAG" "[AUTO-UPDATE] Pembaruan selesai. Restart layanan..."
    /etc/init.d/autologin restart 2>/dev/null
    /etc/init.d/uhttpd restart 2>/dev/null
else
    logger -t "$LOG_TAG" "[AUTO-UPDATE] Semua file sudah yang terbaru."
fi

flock -u 200
exit 0
