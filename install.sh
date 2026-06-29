#!/bin/sh
# AutoLogin Installer for OpenWrt
# Repo: https://github.com/creativy24/portal

REPO="https://raw.githubusercontent.com/creativy24/portal/main"
CHATTR=$(which chattr 2>/dev/null || echo /usr/bin/chattr)

echo "================================================"
echo "   AutoLogin Installer for OpenWrt"
echo "================================================"
echo ""

# --- Deteksi IP Router ---
ROUTER_IP=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
if [ -z "$ROUTER_IP" ]; then
    ROUTER_IP=$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
fi
[ -z "$ROUTER_IP" ] && ROUTER_IP="192.168.1.1"
echo "Router IP: $ROUTER_IP"
echo ""

# --- Cek dan instal dependensi ---
echo "Memeriksa dependensi..."

MISSING_PKGS=""
for pkg in curl libcurl4 ca-certificates zoneinfo-asia; do
    if ! opkg list-installed 2>/dev/null | grep -q "^$pkg "; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

if [ -n "$MISSING_PKGS" ]; then
    echo "Menginstal paket yang diperlukan:$MISSING_PKGS"
    opkg update >/dev/null 2>&1
    for pkg in $MISSING_PKGS; do
        echo "  -> $pkg"
        opkg install "$pkg" >/dev/null 2>&1
    done
    echo "Paket selesai diinstal."
else
    echo "Semua dependensi sudah terpasang."
fi
echo ""

# --- Buat direktori ---
mkdir -p /usr/lib/autologin
mkdir -p /usr/lib/autologin/captive-detect/handlers
mkdir -p /tmp/autologin/state
mkdir -p /tmp/autologin/debug

# --- Fungsi download ---
if command -v curl >/dev/null 2>&1; then
    DOWNLOAD="curl -sSL -o"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD="wget -q -O"
else
    echo "ERROR: curl atau wget tidak ditemukan!"
    exit 1
fi

download() {
    local src="$1"
    local dest="$2"
    echo "  -> $dest"
    $DOWNLOAD "$dest" "$src"
    chmod 0755 "$dest"
}

echo "Mengunduh file..."

# Hotplug & Init
download "$REPO/etc/hotplug.d/iface/99-autologin"       "/etc/hotplug.d/iface/99-autologin"
download "$REPO/etc/init.d/autologin"                    "/etc/init.d/autologin"

# Binary
download "$REPO/usr/bin/autologin"                       "/usr/bin/autologin"

# LuCI
download "$REPO/usr/lib/lua/luci/controller/autologin.lua" "/usr/lib/lua/luci/controller/autologin.lua"
download "$REPO/usr/lib/lua/luci/view/autologin/index.htm" "/usr/lib/lua/luci/view/autologin/index.htm"

# Core scripts
download "$REPO/usr/lib/autologin/anti_blocking.sh"      "/usr/lib/autologin/anti_blocking.sh"
download "$REPO/usr/lib/autologin/auto_timezone.sh"      "/usr/lib/autologin/auto_timezone.sh"
download "$REPO/usr/lib/autologin/common.sh"             "/usr/lib/autologin/common.sh"
download "$REPO/usr/lib/autologin/daemon.sh"             "/usr/lib/autologin/daemon.sh"
download "$REPO/usr/lib/autologin/health_check.sh"       "/usr/lib/autologin/health_check.sh"
download "$REPO/usr/lib/autologin/logging.sh"            "/usr/lib/autologin/logging.sh"
download "$REPO/usr/lib/autologin/login_executor.sh"     "/usr/lib/autologin/login_executor.sh"
download "$REPO/usr/lib/autologin/logout.sh"             "/usr/lib/autologin/logout.sh"
download "$REPO/usr/lib/autologin/mac_apply.sh"          "/usr/lib/autologin/mac_apply.sh"
download "$REPO/usr/lib/autologin/mac_spoof.sh"          "/usr/lib/autologin/mac_spoof.sh"
download "$REPO/usr/lib/autologin/routing_lib.sh"        "/usr/lib/autologin/routing_lib.sh"
download "$REPO/usr/lib/autologin/telegram_notify.sh"    "/usr/lib/autologin/telegram_notify.sh"

# Lua
download "$REPO/usr/lib/autologin/update_json.lua"       "/usr/lib/autologin/update_json.lua"

# Captive detect config
download "$REPO/usr/lib/autologin/captive-detect/backend_hosts.conf" "/usr/lib/autologin/captive-detect/backend_hosts.conf"
download "$REPO/usr/lib/autologin/captive-detect/detection.conf"    "/usr/lib/autologin/captive-detect/detection.conf"
download "$REPO/usr/lib/autologin/captive-detect/endpoints.conf"    "/usr/lib/autologin/captive-detect/endpoints.conf"
download "$REPO/usr/lib/autologin/captive-detect/portal.json"       "/usr/lib/autologin/captive-detect/portal.json"

# Handlers
download "$REPO/usr/lib/autologin/captive-detect/handlers/hotspot_mikrotik.sh" "/usr/lib/autologin/captive-detect/handlers/hotspot_mikrotik.sh"
download "$REPO/usr/lib/autologin/captive-detect/handlers/wifi_id_classic.sh"  "/usr/lib/autologin/captive-detect/handlers/wifi_id_classic.sh"
download "$REPO/usr/lib/autologin/captive-detect/handlers/wifi_id_nextjs.sh"   "/usr/lib/autologin/captive-detect/handlers/wifi_id_nextjs.sh"
download "$REPO/usr/lib/autologin/captive-detect/handlers/wms.sh"              "/usr/lib/autologin/captive-detect/handlers/wms.sh"

# Web assets
download "$REPO/www/luci-static/resources/autologin.css"  "/www/luci-static/resources/autologin.css"
download "$REPO/www/luci-static/resources/autologin.js"   "/www/luci-static/resources/autologin.js"
download "$REPO/www/luci-static/resources/donate.png"     "/www/luci-static/resources/donate.png"

# Auto-update
download "$REPO/auto-update.sh"                            "/usr/lib/autologin/auto-update.sh"

echo ""
echo "Mengamankan semua file (immutable)..."

# Semua file di /usr/lib/autologin/
find /usr/lib/autologin/ -type f -exec $CHATTR +i {} \; 2>/dev/null

# LuCI
$CHATTR +i /usr/lib/lua/luci/controller/autologin.lua 2>/dev/null
$CHATTR +i /usr/lib/lua/luci/view/autologin/index.htm 2>/dev/null

# Web assets
$CHATTR +i /www/luci-static/resources/autologin.css 2>/dev/null
$CHATTR +i /www/luci-static/resources/autologin.js 2>/dev/null
$CHATTR +i /www/luci-static/resources/donate.png 2>/dev/null

# Hotplug & Init
$CHATTR +i /etc/hotplug.d/iface/99-autologin 2>/dev/null
$CHATTR +i /etc/init.d/autologin 2>/dev/null

# Binary
$CHATTR +i /usr/bin/autologin 2>/dev/null

echo ""
echo "Menjadwalkan auto-update setiap 6 jam..."
echo "0 */6 * * * /usr/lib/autologin/auto-update.sh" >> /etc/crontabs/root
/etc/init.d/cron enable 2>/dev/null
/etc/init.d/cron restart 2>/dev/null

echo ""
echo "Membersihkan throttle lama..."
rm -f /tmp/autologin/mwan3_throttle_*

echo ""
echo "================================================"
echo "   Instalasi selesai!"
echo "================================================"
echo "Restart layanan..."
/etc/init.d/autologin enable 2>/dev/null
/etc/init.d/autologin restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
echo ""
echo "AutoLogin terpasang!"
echo "Akses: http://$ROUTER_IP/cgi-bin/luci/admin/autologin/konfigurasi"
echo ""
