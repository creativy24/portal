#!/bin/sh
# MAC PERSISTENCE HELPER - DYNAMIC UCI SECTION DETECTOR

. /usr/lib/autologin/logging.sh

ACTION="$1"; LOGICAL="$2"; DEVICE="$3"; MAC="$4"; VENDOR="$5"
LOCK="/var/run/autologin_mac.lock"
[ -e "$LOCK" ] && { echo '{"status":"busy","message":"Operation in progress"}'; exit 1; }
echo $$ > "$LOCK"
trap 'rm -f "$LOCK" 2>/dev/null' EXIT INT TERM HUP

sanitize_mac() { echo "$1" | tr 'a-f' 'A-F' | sed 's/[^0-9A-F:]//g'; }

find_uci_path() {
    local log="$1" dev="$2"
    local w_path=$(uci -q show wireless 2>/dev/null | grep -E "\.network='?$log'" | head -1 | awk -F. '{print $1"."$2}')
    [ -n "$w_path" ] && { echo "$w_path"; return 0; }
    local d_path=$(uci -q show network 2>/dev/null | grep -E "\.name='?$dev'" | head -1 | awk -F. '{print $1"."$2}')
    [ -n "$d_path" ] && { echo "$d_path"; return 0; }
    local l_path=$(uci -q show network 2>/dev/null | grep -E "\.(ifname|device)='?$dev'" | head -1 | awk -F. '{print $1"."$2}')
    [ -n "$l_path" ] && { echo "$l_path"; return 0; }
    uci -q get "network.$log" >/dev/null 2>&1 && echo "network.$log" && return 0
    return 1
}

UCI_PATH=$(find_uci_path "$LOGICAL" "$DEVICE")
[ -z "$UCI_PATH" ] && { echo '{"status":"error","message":"UCI target section not found"}'; exit 1; }

log_info "mac_apply.sh" "Target UCI: $UCI_PATH | Aksi: $ACTION | MAC: $MAC | Vendor: ${VENDOR:-tidak ada}"

if [ "$ACTION" = "apply" ]; then
    MAC=$(sanitize_mac "$MAC")
    [ -z "$MAC" ] && { echo '{"status":"error","message":"Invalid MAC format"}'; exit 1; }

    log_info "mac_apply.sh" "Menerapkan MAC address baru ke $UCI_PATH..."
    uci set "$UCI_PATH.macaddr"="$MAC" 2>/dev/null
    if [ -n "$VENDOR" ]; then
        uci set "$UCI_PATH.mac_vendor"="$VENDOR" 2>/dev/null
    fi
    uci commit "${UCI_PATH%%.*}"

    ip link set dev "$DEVICE" down 2>/dev/null
    sleep 1
    ip link set dev "$DEVICE" address "$MAC" 2>/dev/null
    RC=$?
    ip link set dev "$DEVICE" up 2>/dev/null

    case "$UCI_PATH" in
        wireless.*) wifi reload >/dev/null 2>&1 ;;
        network.*)  /etc/init.d/network reload >/dev/null 2>&1 ;;
    esac

    if [ $RC -eq 0 ]; then
        log_info "mac_apply.sh" "MAC address berhasil diterapkan: $MAC"
        echo "{\"status\":\"success\",\"message\":\"MAC persisted to $UCI_PATH\",\"mac\":\"$MAC\"}"
    else
        log_error "mac_apply.sh" "Gagal menerapkan MAC address ke interface $DEVICE."
        echo '{"status":"error","message":"Runtime apply failed"}'
    fi

elif [ "$ACTION" = "revert" ]; then
    MAC=$(sanitize_mac "$MAC")
    log_info "mac_apply.sh" "Mengembalikan MAC address asli ke $UCI_PATH..."
    uci delete "$UCI_PATH.macaddr" 2>/dev/null
    uci delete "$UCI_PATH.mac_vendor" 2>/dev/null
    uci commit "${UCI_PATH%%.*}"

    ip link set dev "$DEVICE" down 2>/dev/null
    sleep 1
    ip link set dev "$DEVICE" address "$MAC" 2>/dev/null
    RC=$?
    ip link set dev "$DEVICE" up 2>/dev/null

    case "$UCI_PATH" in
        wireless.*) wifi reload >/dev/null 2>&1 ;;
        network.*)  /etc/init.d/network reload >/dev/null 2>&1 ;;
    esac

    if [ $RC -eq 0 ]; then
        log_info "mac_apply.sh" "MAC address berhasil dikembalikan ke asli: $MAC"
        echo "{\"status\":\"success\",\"message\":\"MAC reverted on $UCI_PATH\",\"mac\":\"$MAC\"}"
    else
        log_error "mac_apply.sh" "Gagal mengembalikan MAC address ke interface $DEVICE."
        echo '{"status":"error","message":"Runtime revert failed"}'
    fi
fi