#!/bin/sh
CONFIG_FILE="/etc/autologin/profiles.json"
STATE_DIR="/tmp/autologin/state"
LOCK_DIR="/var/run"

mkdir -p "$STATE_DIR"

. /usr/lib/autologin/logging.sh
if [ -f /usr/lib/autologin/routing_lib.sh ]; then
    . /usr/lib/autologin/routing_lib.sh
fi

get_field() { jsonfilter -i "$CONFIG_FILE" -e "@.profiles[@.id='$1'].$2" 2>/dev/null; }
get_state() { cat "$STATE_DIR/$1.state" 2>/dev/null || echo '{"status":"IDLE","retry_count":0,"cooldown_until":0,"disconnect_count":0}'; }
set_state() { echo "$2" > "$STATE_DIR/$1.state"; }

process_profile() {
    local pid="$1"
    local lock_file="$LOCK_DIR/autologin_${pid}.lock"
    
    exec 200>"$lock_file"
    if ! flock -n 200; then
        return 0
    fi
    
    local logical=$(get_field "$pid" "logical")
    local device=$(get_field "$pid" "device")
    local enabled=$(get_field "$pid" "enabled")
    local auto_reconnect=$(get_field "$pid" "auto_reconnect_enabled")
    local max_retry=$(get_field "$pid" "max_retry")
    local anti_blocking=$(get_field "$pid" "anti_blocking_enabled")

    if [ "$enabled" != "true" ]; then
        log_info "daemon.sh" "Profil $pid ($logical) dinonaktifkan. Tidak diproses."
        flock -u 200; return 0
    fi
    
    if [ "$auto_reconnect" != "true" ]; then
        log_info "daemon.sh" "Profil $pid ($logical) diatur untuk login manual. Tidak diproses otomatis."
        flock -u 200; return 0
    fi

    local claim_err=$(ifstatus "$logical" 2>/dev/null | jsonfilter -e '@["errors"][0].code' 2>/dev/null)
    if [ "$claim_err" = "DEVICE_CLAIM_FAILED" ]; then
        log_error "daemon.sh" "Interface $logical tidak dapat digunakan (DEVICE_CLAIM_FAILED). Menjalankan prosedur pemulihan..."
        /usr/lib/autologin/anti_blocking.sh "$pid" >/dev/null 2>&1
        flock -u 200; return 0
    fi
    
    local health_status=$(/usr/lib/autologin/health_check.sh "$device")
    local state=$(get_state "$pid")
    local retry_count=$(echo "$state" | jsonfilter -e '@.retry_count' 2>/dev/null)
    local prev_status=$(echo "$state" | jsonfilter -e '@.status' 2>/dev/null)
    local cooldown_until=$(echo "$state" | jsonfilter -e '@.cooldown_until' 2>/dev/null)
    local disconnect_count=$(echo "$state" | jsonfilter -e '@.disconnect_count' 2>/dev/null)
    local stab_delay=$(get_field "$pid" "stabilization_delay")
    stab_delay=${stab_delay:-15}    
    local fail_cd=$(get_field "$pid" "failure_cooldown")
    fail_cd=${fail_cd:-5}
    local fail_cd_sec=$((fail_cd * 60))
    
    retry_count=${retry_count:-0}
    cooldown_until=${cooldown_until:-0}
    disconnect_count=${disconnect_count:-0}

    if [ "$prev_status" = "PERMANENT_ERROR" ]; then
        log_error "daemon.sh" "Profil $pid ($logical) dalam keadaan galat permanen. Menunggu tindakan dari admin."
        flock -u 200; return 0
    fi
    
    if [ "$retry_count" -gt "$max_retry" ]; then
        retry_count=$max_retry
    fi
    
    local current_time=$(date +%s)
    if [ "$cooldown_until" -gt "$current_time" ]; then
        local wait_time=$((cooldown_until - current_time))
        log_info "daemon.sh" "Profil $pid ($logical) sedang dalam masa jeda. Menunggu $wait_time detik lagi."
        flock -u 200; return 0
    fi
    
    log_info "daemon.sh" "Profil $pid ($logical) | Status: $health_status | Percobaan ke-$retry_count"

    case "$health_status" in
        "CONNECTED")
            if [ "$prev_status" != "CONNECTED" ]; then
                case "$prev_status" in
                    "IDLE")
		    log_info "daemon.sh" "Interface $logical terdeteksi: CONNECTED. Internet siap digunakan."
		    /usr/lib/autologin/telegram_notify.sh "$pid" "initial" "Status awal interface terdeteksi CONNECTED. Internet siap digunakan." &
					;;
                    "PERMANENT_ERROR")
                    log_info "daemon.sh" "Koneksi internet pada Interface $logical berhasil dipulihkan dari error permanen."
                    /usr/lib/autologin/telegram_notify.sh "$pid" "reconnect" "Koneksi berhasil dipulihkan dari error permanen." &
                    ;;
                *)
                    log_info "daemon.sh" "Koneksi internet pada Interface $logical berhasil pulih (status sebelumnya: $prev_status)."
                    /usr/lib/autologin/telegram_notify.sh "$pid" "reconnect" "Koneksi internet berhasil dipulihkan." &
                    ;;
                esac
                    log_info "daemon.sh" "Membersihkan penyimpanan sementara DNS..."
                    killall -HUP dnsmasq >/dev/null 2>&1
            fi
            set_state "$pid" '{"status":"CONNECTED","retry_count":0,"cooldown_until":0,"disconnect_count":0}'
            set_mwan3_state "$logical" enabled
            ;;
        "PORTAL_DETECTED")
            log_info "daemon.sh" "Halaman login terdeteksi di Interface $logical. Mencoba login otomatis..."
            local login_output=$(/usr/lib/autologin/login_executor.sh "$pid" 2>&1)
            local _status=$(echo "$login_output" | grep -oE '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//')
            
            if [ "$_status" = "success" ]; then
                log_info "daemon.sh" "Login otomatis berhasil. Interface $logical terhubung."
                set_state "$pid" '{"status":"CONNECTED","retry_count":0,"cooldown_until":0,"disconnect_count":0}'
                set_mwan3_state "$logical" enabled
                log_info "daemon.sh" "Membersihkan penyimpanan sementara DNS..."
                killall -HUP dnsmasq >/dev/null 2>&1
                if [ "$prev_status" != "CONNECTED" ]; then
                    /usr/lib/autologin/telegram_notify.sh "$pid" "success" "Login otomatis berhasil dilakukan." &
                fi
            else
                log_error "daemon.sh" "Login otomatis gagal. Memanggil prosedur Anti-Blokir..."
                /usr/lib/autologin/anti_blocking.sh "$pid" >/dev/null 2>&1
                local new_cooldown=$((current_time + stab_delay))
                set_state "$pid" "{\"status\":\"IDLE\",\"retry_count\":0,\"cooldown_until\":$new_cooldown,\"disconnect_count\":0}"
                log_info "daemon.sh" "Anti-Blokir selesai. Menunggu $stab_delay detik untuk siklus berikutnya."
            fi
            flock -u 200; return 0
            ;;
        "NO_IP")
            local noip_attempt=$(echo "$state" | jsonfilter -e '@.noip_attempt' 2>/dev/null)
            noip_attempt=${noip_attempt:-0}
            noip_attempt=$((noip_attempt + 1))
            
            if [ "$noip_attempt" -ge 3 ]; then
                log_error "daemon.sh" "Interface $logical tidak mendapatkan alamat IP setelah 3 kali pemeriksaan. Menjalankan prosedur pemulihan..."
                /usr/lib/autologin/anti_blocking.sh "$pid" >/dev/null 2>&1
                local new_cooldown=$((current_time + stab_delay))
                set_state "$pid" "{\"status\":\"IDLE\",\"retry_count\":0,\"cooldown_until\":$new_cooldown,\"disconnect_count\":0,\"noip_attempt\":0}"
            else
                log_info "daemon.sh" "Interface $logical belum memiliki alamat IP (pemeriksaan ke-$noip_attempt dari 3). Menunggu siklus berikutnya."
                set_state "$pid" "{\"status\":\"NO_IP\",\"retry_count\":0,\"cooldown_until\":0,\"disconnect_count\":0,\"noip_attempt\":$noip_attempt}"
                set_mwan3_state "$logical" disabled
            fi
            flock -u 200; return 0
            ;;
        "DISCONNECTED"|"CLAIM_FAILED")
            disconnect_count=$((disconnect_count + 1))
            
            if [ "$disconnect_count" -lt 3 ]; then
                log_info "daemon.sh" "Interface $logical terputus. Memeriksa ulang (verifikasi ke-$disconnect_count dari 3)."
                set_state "$pid" "{\"status\":\"DISCONNECTED\",\"retry_count\":$retry_count,\"cooldown_until\":0,\"disconnect_count\":$disconnect_count,\"noip_attempt\":0}"
                set_mwan3_state "$logical" disabled
                flock -u 200; return 0
            fi
            
            disconnect_count=0
            retry_count=$((retry_count + 1))
            
            if [ "$retry_count" -ge "$max_retry" ]; then
				log_error "daemon.sh" "Interface $logical terputus dan sudah mencapai batas percobaan ($max_retry kali)."
                if [ "$anti_blocking" = "true" ]; then
                    log_info "daemon.sh" "Menjalankan prosedur Anti-Blokir untuk memulihkan koneksi..."
                    /usr/lib/autologin/anti_blocking.sh "$pid"
                    local anti_block_result=$?
                    
                    if [ "$anti_block_result" -eq 0 ]; then
                        local new_cooldown=$((current_time + stab_delay))
                        set_state "$pid" "{\"status\":\"IDLE\",\"retry_count\":0,\"cooldown_until\":$new_cooldown,\"disconnect_count\":0,\"noip_attempt\":0}"
                        log_info "daemon.sh" "Anti-Blokir berhasil. Menunggu $stab_delay detik untuk stabilisasi."
                    else
                        local new_cooldown=$((current_time + fail_cd_sec))
                        set_state "$pid" "{\"status\":\"IDLE\",\"retry_count\":0,\"cooldown_until\":$new_cooldown,\"disconnect_count\":0,\"noip_attempt\":0}"
                        log_error "daemon.sh" "Anti-Blokir gagal. Menunggu $fail_cd menit sebelum mencoba lagi."
                    fi
                else
					log_error "daemon.sh" "Anti-Blokir tidak diaktifkan. Diperlukan tindakan manual untuk Interface $logical."
                    /usr/lib/autologin/telegram_notify.sh "$pid" "fail" "Koneksi terputus setelah $max_retry kali percobaan. Diperlukan tindakan manual." &
                    local new_cooldown=$((current_time + fail_cd_sec))
                    set_state "$pid" "{\"status\":\"IDLE\",\"retry_count\":0,\"cooldown_until\":$new_cooldown,\"disconnect_count\":0,\"noip_attempt\":0}"
                fi
            else
                set_state "$pid" "{\"status\":\"DISCONNECTED\",\"retry_count\":$retry_count,\"cooldown_until\":0,\"disconnect_count\":0,\"noip_attempt\":0}"
                log_info "daemon.sh" "Interface $logical terputus. Mencoba memulihkan (percobaan $retry_count dari $max_retry)."
            fi
            ;;
        "PERMANENT_ERROR")
            log_error "daemon.sh" "Interface $logical dalam keadaan galat permanen. Menunggu tindakan admin."
            ;;
    esac
    
    flock -u 200
}

log_info "daemon.sh" "Daemon AutoLogin dimulai (PID $$)."
while true; do
    for trigger_file in /tmp/autologin_trigger_*; do
        [ -f "$trigger_file" ] || continue
        trig_iface=$(echo "$trigger_file" | sed 's/.*trigger_//')
        rm -f "$trigger_file"
        
        for pid in $(jsonfilter -i "$CONFIG_FILE" -e '@.profiles[*].id' 2>/dev/null); do
            trig_dev=$(get_field "$pid" "device")
            if [ "$trig_dev" = "$trig_iface" ]; then
                log_info "daemon.sh" "Interface $trig_iface baru saja menyala. Langsung memproses profil $pid."
                process_profile "$pid" &
                break
            fi
        done
    done
    
    profiles=$(jsonfilter -i "$CONFIG_FILE" -e '@.profiles[*].id' 2>/dev/null)
    
    min_interval=30
    for pid in $profiles; do
        interval=$(get_field "$pid" "health_check_interval")
        interval=${interval:-30}
        [ "$interval" -lt "$min_interval" ] && min_interval=$interval
        
        process_profile "$pid" &
    done
    wait
    
    log_info "daemon.sh" "Menunggu $min_interval detik sebelum pemeriksaan berikutnya..."
    sleep $min_interval
done