module("luci.controller.autologin", package.seeall)
local http = require "luci.http"
local fs = require "nixio.fs"
local json = require "luci.jsonc"

local SCRIPT_DIR = (luci.sys.exec("uci -q get autologin.config.script_dir 2>/dev/null"):gsub("\n", ""))
if SCRIPT_DIR == "" then SCRIPT_DIR = "/usr/lib/autologin" end

local function resolve_uci_section(log, dev)
    local w_path = luci.sys.exec(string.format("uci -q show wireless 2>/dev/null | grep -E \"\\.network='?%s'\" | head -1 | awk -F. '{print $1\".\"$2}'", log)):gsub("\n", "")
    if w_path ~= "" then return w_path end
    local d_path = luci.sys.exec(string.format("uci -q show network 2>/dev/null | grep -E \"\\.name='?%s'\" | head -1 | awk -F. '{print $1\".\"$2}'", dev)):gsub("\n", "")
    if d_path ~= "" then return d_path end
    local l_path = luci.sys.exec(string.format("uci -q show network 2>/dev/null | grep -E \"\\.(ifname|device)='?%s'\" | head -1 | awk -F. '{print $1\".\"$2}'", dev)):gsub("\n", "")
    if l_path ~= "" then return l_path end
    local fallback = luci.sys.exec(string.format("uci -q get network.%s 2>/dev/null", log)):gsub("\n", "")
    if fallback ~= "" then return "network."..log end
    return nil
end

local function send_manual_telegram(profile_id, event, message, token, chat_id, logical, device, mac, ip, portal_type, status)
    local env = string.format(
        "OVR_TOKEN=%q OVR_CHAT_ID=%q OVR_ENABLED=true OVR_LOGICAL=%q OVR_DEVICE=%q OVR_MAC=%q OVR_IPC=%q OVR_PORTAL_TYPE=%q OVR_STATUS=%q",
        token, chat_id, logical, device, mac, ip, portal_type, status
    )
    local safe_message = message:gsub("'", "'\"'\"'")
    local cmd = string.format("%s /usr/lib/autologin/telegram_notify.sh %s %s '%s' >/dev/null 2>&1", env, profile_id, event, safe_message)
    luci.sys.exec(cmd)
end

function index()
    entry({"admin", "autologin"}, firstchild(), _("Auto Login"), 100)
    entry({"admin", "autologin", "konfigurasi"}, template("autologin/index"), _("Konfigurasi"), 1)
    entry({"admin", "autologin", "scan"}, call("scan_portals"), nil).leaf = true
    entry({"admin", "autologin", "mac_spoof_check"}, call("check_mac_spoof_api"), nil).leaf = true
    entry({"admin", "autologin", "sync_time"}, call("sync_time_api"), nil).leaf = true
    entry({"admin", "autologin", "apply_mac"}, call("apply_mac_api"), nil).leaf = true
    entry({"admin", "autologin", "revert_mac"}, call("revert_mac_api"), nil).leaf = true
    entry({"admin", "autologin", "mac_status"}, call("get_mac_status_api"), nil).leaf = true
    entry({"admin", "autologin", "login"}, call("login_api"), nil).leaf = true
    entry({"admin", "autologin", "logout"}, call("logout_api"), nil).leaf = true
    entry({"admin", "autologin", "save_profile"}, call("save_profile_api"), nil).leaf = true
    entry({"admin", "autologin", "update_profile_field"}, call("update_profile_field_api"), nil).leaf = true
    entry({"admin", "autologin", "get_profiles"}, call("get_profiles_api"), nil).leaf = true
    entry({"admin", "autologin", "delete_profile"}, call("delete_profile_api"), nil).leaf = true
    entry({"admin", "autologin", "get_status"}, call("get_status_api"), nil).leaf = true
    entry({"admin", "autologin", "update_enabled_status"}, call("update_enabled_status_api"), nil).leaf = true
    entry({"admin", "autologin", "restart_interface"}, call("restart_interface_api"), nil).leaf = true
end

local function load_portal_rules()
    local portal_json = SCRIPT_DIR .. "/captive-detect/portal.json"
    local result = {rules = {}, features = {}}

    if not fs.access(portal_json) then
        luci.sys.exec("logger -t autologin '[WARN] portal.json tidak ditemukan: " .. portal_json .. "'")
        return result
    end

    local f = io.open(portal_json, "r")
    if not f then
        luci.sys.exec("logger -t autologin '[ERROR] Gagal membuka portal.json'")
        return result
    end

    local content = f:read("*all")
    f:close()

    local ok, parsed = pcall(json.parse, content)
    if not ok or not parsed or not parsed.patterns then
        luci.sys.exec("logger -t autologin '[ERROR] Gagal parsing portal.json'")
        return result
    end


    for _, p in ipairs(parsed.patterns) do
        local type_key = p.type_key
        if type_key and type_key ~= "" then
            -- Buat entry features jika belum ada
            if not result.features[type_key] then
                result.features[type_key] = {
                    label = type_key,
                    known_paths = {},
                    handlers = {}
                }
            end

            local feat = result.features[type_key]

            if p.path_key and p.handler_script then
                local handler_entry = {
                    path = p.path_key,
                    handler = p.handler_script
                }
                local already_exists = false
                for _, existing in ipairs(feat.handlers) do
                    if existing.path == handler_entry.path and existing.handler == handler_entry.handler then
                        already_exists = true
                        break
                    end
                end
                if not already_exists then
                    table.insert(feat.handlers, handler_entry)
                end
            end

            for k, v in pairs(p) do
                if k ~= "path_key" and k ~= "query_key" and k ~= "html_signature" and k ~= "type_key" and k ~= "normalize_path" and k ~= "handler_script" then
                    feat[k] = v
                end
            end
            if not feat.handler_script and p.handler_script then
                feat.handler_script = p.handler_script
            end

            if p.path_key and p.path_key ~= "" then
                local already_exists = false
                for _, existing_path in ipairs(feat.known_paths) do
                    if existing_path == p.path_key then
                        already_exists = true
                        break
                    end
                end
                if not already_exists then
                    table.insert(feat.known_paths, p.path_key)
                end
            end

            if p.normalize_path and p.normalize_path ~= "" then
                local already_exists = false
                for _, existing_path in ipairs(feat.known_paths) do
                    if existing_path == p.normalize_path then
                        already_exists = true
                        break
                    end
                end
                if not already_exists then
                    table.insert(feat.known_paths, p.normalize_path)
                end
            end
        end
    end

    luci.sys.exec("logger -t autologin '[INFO] load_portal_rules: Berhasil memuat " .. #parsed.patterns .. " pola'")
    return result
end

function scan_portals()
    http.prepare_content("application/json")
    local script = SCRIPT_DIR .. "/common.sh"
    local device = http.formvalue("device") or ""
    if device ~= "" then
        device = device:gsub("[^a-zA-Z0-9_@%-]", "")
        if device ~= "" then
            script = script .. " " .. device
        end
    end
    if fs.access(SCRIPT_DIR .. "/common.sh") then
        local pipe = io.popen(script .. " 2>/dev/null")
        if pipe then
            local res = pipe:read("*all")
            pipe:close()
            local data = json.parse(res) or {interfaces={}}
            local portal_rules = load_portal_rules()
            if data.interfaces then
                for _, iface in ipairs(data.interfaces) do
                    local logical = iface.interface or ""
                    local device = iface.device or ""
                    if logical ~= "" and device ~= "" then
                        local uci_sec = resolve_uci_section(logical, device)
                        if uci_sec then
                            local macaddr = luci.sys.exec(string.format("uci -q get %s.macaddr 2>/dev/null", uci_sec)):gsub("\n", "")
                            iface.mac_modified = (macaddr ~= "")
                            if iface.mac_modified then
                                local vendor = luci.sys.exec(string.format("uci -q get %s.mac_vendor 2>/dev/null", uci_sec)):gsub("\n", "")
                                if vendor ~= "" then
                                    iface.mac_vendor = vendor
                                else
                                    local fallback_vendor = luci.sys.exec(string.format("uci -q get network.%s.mac_vendor 2>/dev/null", logical)):gsub("\n", "")
                                    if fallback_vendor ~= "" then
                                        iface.mac_vendor = fallback_vendor
                                    end
                                end
                            end
                        else
                            local direct_mac = luci.sys.exec(string.format("uci -q get network.%s.macaddr 2>/dev/null", logical)):gsub("\n", "")
                            if direct_mac ~= "" then
                                iface.mac_modified = true
                                local direct_vendor = luci.sys.exec(string.format("uci -q get network.%s.mac_vendor 2>/dev/null", logical)):gsub("\n", "")
                                if direct_vendor ~= "" then
                                    iface.mac_vendor = direct_vendor
                                end
                            else
                                iface.mac_modified = false
                            end
                        end
                    else
                        iface.mac_modified = false
                    end
                end
            end           
            data.portal_config = portal_rules.features
            http.write(json.stringify(data) or '{"interfaces":[]}')
        else
            luci.sys.exec("logger -t autologin '[ERROR] scan_portals: Gagal membuka pipe ke common.sh'")
            http.write('{"interfaces":[]}')
        end
    else
        luci.sys.exec("logger -t autologin '[ERROR] scan_portals: Script common.sh tidak ditemukan'")
        http.write('{"interfaces":[]}')
    end
end

function check_mac_spoof_api()
    http.prepare_content("application/json")
    local cache_file = "/etc/autologin/mac_spoof.cache"
    local cache_content = nil
    local f = io.open(cache_file, "r")
    if f then
        cache_content = f:read("*all")
        f:close()
    end
    if cache_content and cache_content:match('"supported"%s*:%s*true') then
        http.write(cache_content)
        return
    end
    if not cache_content or cache_content == "" then
        local tmp_f = io.open("/tmp/mac_spoof.cache", "r")
        if tmp_f then
            cache_content = tmp_f:read("*all")
            tmp_f:close()
            if cache_content and cache_content:match('"supported"%s*:%s*true') then
                http.write(cache_content)
                return
            end
        end
    end
    os.execute(". " .. SCRIPT_DIR .. "/mac_spoof.sh && check_mac_spoof_support >/dev/null 2>&1 &")
    luci.sys.exec("sleep 2")
    f = io.open(cache_file, "r")
    if f then 
        cache_content = f:read("*all")
        f:close() 
    end
    if cache_content and cache_content:match('"supported"') then
        http.write(cache_content)
    else
        http.write('{"supported":false,"level":"none","checked_at":' .. os.time() .. '}')
    end
end

function sync_time_api()
    http.prepare_content("application/json")
    local current_tz = luci.sys.exec("uci -q get system.@system[0].zonename 2>/dev/null"):gsub("\n", "")
    local cache_tz = ""
    local f = io.open("/tmp/autologin_tz.cache", "r")
    if f then
        local lines = {}
        for line in f:lines() do
            table.insert(lines, line)
        end
        f:close()
        if #lines > 0 then
            cache_tz = lines[#lines]
        end
    end
    if current_tz ~= "" and current_tz ~= "UTC" and current_tz ~= "Etc/UTC" and current_tz == cache_tz then
        http.write(string.format('{"status":"skipped","message":"Zona waktu sudah valid dan sesuai cache (%s)","system_time":"%s","timezone":"%s"}', 
            current_tz, os.date("%Y-%m-%d %H:%M:%S"), current_tz))
        return
    end
    local ntp_server = luci.sys.exec("uci -q get autologin.config.ntp_server 2>/dev/null"):gsub("\n", "")
    if ntp_server == "" then ntp_server = "0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org" end
    os.execute("sh -c '" .. SCRIPT_DIR .. "/auto_timezone.sh & ntpd -n -q -p " .. ntp_server .. " >/dev/null 2>&1 &'")
    local display_tz = current_tz
    if not display_tz or display_tz == "" then 
        display_tz = "detecting..." 
    end
    http.write(string.format('{"status":"initiated","message":"Sinkronisasi waktu dan zona waktu dimulai","system_time":"%s","timezone":"%s"}', 
        os.date("%Y-%m-%d %H:%M:%S"), display_tz))
end

function apply_mac_api()
    http.prepare_content("application/json")
    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.write('{"status":"error","message":"Method not allowed"}')
        return
    end
    local logical = http.formvalue("logical")
    local device = http.formvalue("device")
    local target = http.formvalue("target_mac")
    local device_type = http.formvalue("device_type")
    if not logical or not device or not target then
        http.write('{"status":"error","message":"Missing parameters"}')
        return
    end
    local cmd = string.format("/usr/lib/autologin/mac_apply.sh apply %s %s %s", logical, device, target)
    local ok, res = pcall(function()
        local f = io.popen(cmd)
        if f then
            local data = f:read("*l")
            f:close()
            return data
        end
        return nil
    end)
    if ok and res and res ~= "" then
        local parsed = json.parse(res)
        if parsed and parsed.status == "success" then
            local section = resolve_uci_section(logical, device)
            if section and device_type and device_type ~= "" then
                luci.sys.exec("uci set " .. section .. ".mac_vendor=" .. device_type)
                luci.sys.exec("uci commit " .. section:match("^[^%.]+"))
            end
        end
        http.write(res)
    else
        luci.sys.exec("logger -t autologin '[ERROR] apply_mac: Backend execution failed'")
        http.write('{"status":"error","message":"Backend execution failed"}')
    end
end

function revert_mac_api()
    http.prepare_content("application/json")
    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.write('{"status":"error","message":"Method not allowed"}')
        return
    end
    local logical = http.formvalue("logical")
    local device = http.formvalue("device")
    local orig = http.formvalue("original_mac")
    if not logical or not device or not orig then
        http.write('{"status":"error","message":"Missing parameters"}')
        return
    end
    local cmd = string.format("/usr/lib/autologin/mac_apply.sh revert %s %s %s", logical, device, orig)
    local ok, res = pcall(function()
        local f = io.popen(cmd)
        if f then
            local data = f:read("*l")
            f:close()
            return data
        end
        return nil
    end)
    if ok and res and res ~= "" then
        local parsed = json.parse(res)
        if parsed and parsed.status == "success" then
            local section = resolve_uci_section(logical, device)
            if section then
                luci.sys.exec("uci delete " .. section .. ".mac_vendor")
                luci.sys.exec("uci commit " .. section:match("^[^%.]+"))
            end
        end
        http.write(res)
    else
        luci.sys.exec("logger -t autologin '[ERROR] revert_mac: Backend execution failed'")
        http.write('{"status":"error","message":"Backend execution failed"}')
    end
end

function get_mac_status_api()
    http.prepare_content("application/json")
    local logical = http.formvalue("logical")
    local device = http.formvalue("device")
    if not logical or not device then
        http.write('{"status":"error","message":"Missing parameters"}')
        return
    end
    local uci_section = resolve_uci_section(logical, device)
    if not uci_section then
        http.write('{"is_modified":false,"uci_section":null}')
        return
    end
    local macaddr_value = luci.sys.exec(string.format("uci -q get %s.macaddr 2>/dev/null", uci_section)):gsub("\n", "")
    local is_modified = (macaddr_value ~= "")
    
    http.write(string.format('{"is_modified":%s,"uci_section":"%s","macaddr":"%s"}', 
        is_modified and "true" or "false", uci_section, macaddr_value))
end

function login_api()
    http.prepare_content("application/json")

    local raw_data = http.content()
    local req_data = {}
    if raw_data and raw_data ~= "" then
        local ok, parsed = pcall(json.parse, raw_data)
        if ok and parsed then
            req_data = parsed
        else
            luci.sys.exec("logger -t autologin '[ERROR] login_api: Gagal parsing JSON'")
            http.write('{"status":"bug","message":"Format data tidak valid."}')
            return
        end
    end
    
    if not next(req_data) then
        luci.sys.exec("logger -t autologin '[ERROR] login_api: Tidak ada data POST'")
        http.write('{"status":"error","message":"Tidak ada data yang diterima."}')
        return
    end
    
    local portal_type = req_data.portal_type
    local url = req_data.url
    local username = req_data.username
    local password = req_data.password
    local device = req_data.device
    local handler_script = req_data.handler_script

    if not portal_type or not url or not username or not password or not device then
        luci.sys.exec("logger -t autologin '[ERROR] login_api: Parameter wajib tidak lengkap'")
        http.write('{"status":"error","message":"Parameter wajib tidak lengkap."}')
        return
    end
    
    if not handler_script then
        luci.sys.exec("logger -t autologin '[ERROR] login_api: handler_script tidak disertakan oleh frontend'")
        http.write('{"status":"error","message":"Handler script tidak ditentukan."}')
        return
    end
    
    if handler_script:match("[^a-zA-Z0-9_%.%-]") or handler_script:match("%.%.%.") then
        luci.sys.exec(string.format("logger -t autologin '[ERROR] login_api: handler_script mencurigakan: %s'", handler_script))
        http.write('{"status":"error","message":"Nama handler script tidak valid."}')
        return
    end
    
    local handler_path = SCRIPT_DIR .. "/captive-detect/handlers/" .. handler_script
    
    if not fs.access(handler_path) then
        luci.sys.exec(string.format("logger -t autologin '[ERROR] login_api: Handler script %s tidak ditemukan'", handler_path))
        http.write('{"status":"bug","message":"Handler script tidak ditemukan di sistem."}')
        return
    end
    
    luci.sys.exec(string.format(
        "logger -t autologin '[DEBUG] PARAMS: url=%s, user=%s, logical=%s, dev=%s, mac=%s, gw_id=%s, wlan=%s, sessionid=%s, ipc=%s, portal_type=%s, login_method=%s, sub_method=%s, handler=%s'",
        url or "nil", username or "nil", req_data.logical or "nil", device or "nil", req_data.mac or "nil",
        req_data.gw_id or "nil", req_data.wlan or "nil", req_data.sessionid or "nil", req_data.ipc or "nil",
        portal_type or "nil", req_data.login_method or "nil", req_data.sub_method or "nil", handler_script or "nil"))

    luci.sys.exec(string.format("logger -t autologin '[LOGIN] Memanggil handler: %s'", handler_script))
    
    local json_payload = json.stringify(req_data)
    
    local tmp_json = "/tmp/autologin_login_payload_" .. os.time() .. ".json"
    local write_ok, write_err = fs.writefile(tmp_json, json_payload)
    if not write_ok then
        luci.sys.exec("logger -t autologin '[ERROR] login_api: Gagal menulis temporary JSON'")
        http.write('{"status":"bug","message":"Gagal menyiapkan data untuk handler."}')
        return
    end
    
    local cmd = "cat " .. tmp_json .. " | sh " .. handler_path .. " 2>/dev/null"
    local f = io.popen(cmd, "r")
    if not f then
        luci.sys.exec("logger -t autologin '[ERROR] login_api: Gagal menjalankan handler'")
        os.remove(tmp_json)
        http.write('{"status":"bug","message":"Gagal menjalankan handler."}')
        return
    end
    
    local res = f:read("*all")
    f:close()
    os.remove(tmp_json)

    if res and res ~= "" then
        local parsed = json.parse(res)
        if parsed and parsed.status then
            if parsed.status == "success" then
                luci.sys.exec("logger -t autologin '[POST-LOGIN] Login berhasil.'")
                
                local logical = req_data.logical or ""
                if logical ~= "" then
                    luci.sys.exec(string.format(
                        ". /usr/lib/autologin/routing_lib.sh && set_mwan3_state %s enabled",
                        logical
                    ))
                end
            else
                luci.sys.exec(string.format("logger -t autologin '[LOGIN-FAIL] %s: %s'", parsed.status, parsed.message or "no message"))
            end
            local tg_enabled = req_data.telegram_enabled
            local tg_token = req_data.telegram_token
            local tg_chat_id = req_data.telegram_chat_id

            if tg_enabled == true and tg_token and tg_token ~= "" and tg_chat_id and tg_chat_id ~= "" then
                local event = (parsed.status == "success") and "manual_login_success" or "manual_login_fail"
                local message = parsed.message or (parsed.status == "success" and "Login manual berhasil." or "Login manual gagal.")
                local profile_id = (req_data.logical or "unknown") .. "_" .. (req_data.portal_type or "unknown"):lower()
                profile_id = profile_id:gsub("[^a-z0-9_]", "_")
                local status_text = (parsed.status == "success") and "CONNECTED" or "DISCONNECTED"
                send_manual_telegram(
                    profile_id,
                    event,
                    message,
                    tg_token,
                    tg_chat_id,
                    req_data.logical or "?",
                    req_data.device or "?",
                    req_data.mac or "?",
                    req_data.ipc or "?",
                    req_data.portal_type or "?",
                    status_text
                )
                luci.sys.exec(string.format("logger -t autologin '[NOTIFIKASI] Telegram manual %s dikirim untuk %s'", event, profile_id))
            else
                luci.sys.exec(string.format("logger -t autologin '[NOTIFIKASI] Telegram manual tidak dikirim: data tidak lengkap (enabled=%s, token=%s, chat=%s)'",
                    tostring(tg_enabled), tg_token and "ada" or "tidak", tg_chat_id and "ada" or "tidak"))
            end
            http.write(res)
        else
            luci.sys.exec("logger -t autologin '[ERROR] login_api: Handler output tidak valid'")
            http.write('{"status":"bug","message":"Handler output tidak valid."}')
        end
    else
        luci.sys.exec("logger -t autologin '[ERROR] login_api: Eksekusi handler gagal'")
        http.write('{"status":"bug","message":"Eksekusi handler gagal."}')
    end
end

function logout_api()
    http.prepare_content("application/json")
    
    local raw_data = http.content()
    local req_data = {}
    if raw_data and raw_data ~= "" then
        req_data = json.parse(raw_data) or {}
    end
    
    if not next(req_data) then
        luci.sys.exec("logger -t autologin '[ERROR] logout_api: Tidak ada data POST'")
        http.write('{"status":"error","message":"Tidak ada data."}')
        return
    end
    
    local portal_type = req_data.portal_type
    local url = req_data.url
    local device = req_data.device
    local logical = req_data.logical or ""
    local mac = req_data.mac or ""
    
    if not portal_type or not url or not device then
        luci.sys.exec("logger -t autologin '[ERROR] logout_api: Parameter tidak lengkap'")
        http.write('{"status":"error","message":"Parameter tidak lengkap (portal_type, url, device wajib)."}')
        return
    end
    
    luci.sys.exec(string.format("logger -t autologin '[LOGOUT] Menerima permintaan logout untuk %s/%s (%s)'", logical, device, portal_type))
    
    local function shell_escape(str)
        if not str then return "" end
        return "'" .. string.gsub(str, "'", "'\"'\"'") .. "'"
    end
    
    local cmd = string.format("sh /usr/lib/autologin/logout.sh %s %s %s %s %s", 
        shell_escape(portal_type), shell_escape(url), shell_escape(device), shell_escape(logical), shell_escape(mac))
    
    local ok, res = pcall(function()
        local f = io.popen(cmd .. " 2>/dev/null")
        if f then
            local data = f:read("*all")
            f:close()
            return data
        end
        return nil
    end)
    
    if ok and res and res ~= "" then
        luci.sys.exec("logger -t autologin '[LOGOUT] Selesai.'")
        local tg_enabled = req_data.telegram_enabled
        local tg_token = req_data.telegram_token
        local tg_chat_id = req_data.telegram_chat_id

        if tg_enabled == true and tg_token and tg_token ~= "" and tg_chat_id and tg_chat_id ~= "" then
            local parsed = json.parse(res)
            if parsed and parsed.status then
                local event = (parsed.status == "success" or parsed.status == "warning") and "manual_logout_success" or "manual_logout_fail"
                local message = parsed.message or (event == "manual_logout_success" and "Logout manual berhasil." or "Logout manual gagal.")
                local profile_id = (req_data.logical or "unknown") .. "_" .. (req_data.portal_type or "unknown"):lower()
                profile_id = profile_id:gsub("[^a-z0-9_]", "_")
                local status_text = "DISCONNECTED"
                local ip_notif = req_data.ipc
                if (not ip_notif or ip_notif == "") and req_data.device then
                    ip_notif = luci.sys.exec("ip -4 addr show dev " .. req_data.device .. " 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1"):gsub("\n", "")
                end
                if not ip_notif or ip_notif == "" then
                    ip_notif = "?"
                end

                send_manual_telegram(
                    profile_id,
                    event,
                    message,
                    tg_token,
                    tg_chat_id,
                    req_data.logical or "?",
                    req_data.device or "?",
                    req_data.mac or "?",
                    ip_notif,   -- gunakan IP yang sudah diambil
                    req_data.portal_type or "?",
                    status_text
                )
                luci.sys.exec(string.format("logger -t autologin '[NOTIFIKASI] Telegram manual %s dikirim untuk %s'", event, profile_id))
            else
                luci.sys.exec("logger -t autologin '[NOTIFIKASI] Telegram manual tidak dikirim: hasil logout tidak valid'")
            end
        else
            luci.sys.exec(string.format("logger -t autologin '[NOTIFIKASI] Telegram manual tidak dikirim: data tidak lengkap (enabled=%s, token=%s, chat=%s)'",
                tostring(tg_enabled), tg_token and "ada" or "tidak", tg_chat_id and "ada" or "tidak"))
        end
        http.write(res)
    else
        luci.sys.exec("logger -t autologin '[ERROR] logout_api: Eksekusi logout gagal'")
        http.write('{"status":"error","message":"Eksekusi logout gagal."}')
    end
end

local function safe_rename(src, dst)
    if fs.access(src) then
        if fs.access(dst) then
            os.remove(dst)
        end
        local ok = os.rename(src, dst)
        if not ok then
            luci.sys.exec("mv " .. src .. " " .. dst .. " 2>/dev/null")
        end
        return true
    end
    return false
end

local function restart_daemon()
    luci.sys.exec("logger -t autologin '[SISTEM] Memulai restart daemon yang aman...'")
    luci.sys.exec("/etc/init.d/autologin stop >/dev/null 2>&1")
    luci.sys.exec("for pid in $(ps w | grep '[/]usr/lib/autologin/daemon.sh' | awk '{print $1}'); do kill $pid 2>/dev/null; done")
    luci.sys.exec("sleep 1")
    luci.sys.exec("rm -f /var/run/autologin_*.lock 2>/dev/null")
    luci.sys.exec("if ps w | grep -q '[/]usr/lib/autologin/daemon.sh'; then kill -9 $(ps w | grep '[/]usr/lib/autologin/daemon.sh' | awk '{print $1}') 2>/dev/null; sleep 1; fi")
    luci.sys.exec("/etc/init.d/autologin start >/dev/null 2>&1")
    luci.sys.exec("logger -t autologin '[SISTEM] Daemon berhasil direstart.'")
end

function save_profile_api()
    http.prepare_content("application/json")
    local raw_data = http.content()
    if not raw_data or raw_data == "" then
        luci.sys.exec("logger -t autologin '[ERROR] save_profile: Tidak ada data'")
        http.write('{"status":"error","message":"Tidak ada data."}')
        return
    end
    
    local data = json.parse(raw_data)
    if not data or not data.logical or not data.portal_type then
        luci.sys.exec("logger -t autologin '[ERROR] save_profile: Data tidak lengkap'")
        http.write('{"status":"error","message":"Data profil tidak lengkap."}')
        return
    end
    
    local profile_id = (data.logical or "unknown") .. "_" .. (data.portal_type or "unknown"):lower()
    profile_id = profile_id:gsub("[^a-z0-9_]", "_")
    
    local config_dir = "/etc/autologin"
    local config_file = config_dir .. "/profiles.json"
    
    if not fs.access(config_dir, "r") then
        local ok, err = fs.mkdir(config_dir, 755)
        if not ok then
            luci.sys.exec("logger -t autologin 'Failed to create directory: " .. tostring(err) .. "'")
            http.write('{"status":"error","message":"Gagal membuat direktori."}')
            return
        end
    end
    
    local profiles_data = { profiles = {} }
    if fs.access(config_file, "r") then
        local f = io.open(config_file, "r")
        if f then
            local content = f:read("*all")
            f:close()
            if content and content ~= "" then
                local parsed = json.parse(content)
                if parsed and parsed.profiles then
                    profiles_data = parsed
                end
            end
        end
    end
    
    local existing_index = nil
    for i, profile in ipairs(profiles_data.profiles) do
        if profile.id == profile_id then
            existing_index = i
            break
        end
    end

    local new_profile = {
        id = profile_id,
        enabled = data.enabled ~= false,
        logical = data.logical,
        device = data.device,
        portal_type = data.portal_type,
        username = data.username,
        password = data.password,
		original_username = data.original_username or "",
        mac = data.mac,
        url = data.url,
        device_vendor = data.device_vendor or "",
        auto_login_enabled = data.auto_login_enabled ~= false,
        auto_reconnect_enabled = data.auto_reconnect_enabled ~= false,
        health_check_interval = tonumber(data.health_check_interval) or 30,
        stabilization_delay = tonumber(data.stabilization_delay) or 15,
        failure_cooldown = tonumber(data.failure_cooldown) or 5,
        max_retry = tonumber(data.max_retry) or 5,
        anti_blocking_enabled = data.anti_blocking_enabled ~= false,
        telegram_enabled = data.telegram_enabled == true,
        telegram_token = data.telegram_token or "",
        telegram_chat_id = data.telegram_chat_id or "",
        login_method = data.login_method or "",
        sub_method = data.sub_method or ""
    }
    
    if existing_index then
        new_profile.created_at = profiles_data.profiles[existing_index].created_at
        profiles_data.profiles[existing_index] = new_profile
    else
        new_profile.created_at = os.date("%Y-%m-%dT%H:%M:%SZ", os.time())
        table.insert(profiles_data.profiles, new_profile)
    end
    
    if data.has_session_grid == true then
        if data.gw_id then new_profile.gw_id = data.gw_id end
        if data.wlan then new_profile.wlan = data.wlan end
        if data.sessionid then new_profile.sessionid = data.sessionid end
        if data.ipc then new_profile.ipc = data.ipc end
    end
    
    local json_str = json.stringify(profiles_data, true):gsub("\\/", "/")
    local tmp_file = config_file .. ".tmp"
    local ok, err = fs.writefile(tmp_file, json_str)
    if not ok then
        luci.sys.exec("logger -t autologin '[ERROR] save_profile_api: Gagal menulis file sementara: " .. tostring(err) .. "'")
        http.write('{"status":"error","message":"Gagal menyimpan file."}')
        return
    end
    safe_rename(tmp_file, config_file)
    
    luci.sys.exec("logger -t autologin '[INFO] save_profile_api: Profil berhasil disimpan: " .. profile_id .. "'")
    
    if data.is_new == true then
        luci.sys.exec("logger -t autologin '[INFO] save_profile_api: Profil baru, merestart daemon...'")
        restart_daemon()
    else
        luci.sys.exec("logger -t autologin '[INFO] save_profile_api: Profil update, daemon tidak direstart.'")
    end
    
    http.write('{"status":"success","message":"Profil berhasil disimpan.","profile_id":"' .. profile_id .. '"}')
end

function update_profile_field_api()
    http.prepare_content("application/json")
    local profile_id = http.formvalue("profile_id")
    local field = http.formvalue("field")
    local value = http.formvalue("value")
    
    if not profile_id or not field then
        http.write('{"status":"error","message":"Missing parameters"}')
        return
    end
    
    local config_file = "/etc/autologin/profiles.json"
    if not fs.access(config_file, "r") then
        http.write('{"status":"error","message":"Config file not found"}')
        return
    end
    
    local f = io.open(config_file, "r")
    local content = f:read("*all")
    f:close()
    
    local data = json.parse(content)
    if not data or not data.profiles then
        http.write('{"status":"error","message":"Invalid JSON structure"}')
        return
    end
    
    local updated = false
    for _, p in ipairs(data.profiles) do
        if p.id == profile_id then
            if value == "true" then value = true
            elseif value == "false" then value = false
            elseif tonumber(value) then value = tonumber(value)
            end
            
            if p[field] ~= value then
                p[field] = value
                updated = true
            end
            break
        end
    end
    
    if updated then
        local json_str = json.stringify(data)
        local tmp_file = config_file .. ".tmp"
        local ok, err = fs.writefile(tmp_file, json_str)
        if ok then
            safe_rename(tmp_file, config_file)
            luci.sys.exec("logger -t autologin 'Updated field " .. field .. " for " .. profile_id .. "'")
            http.write('{"status":"success"}')
        else
            luci.sys.exec("logger -t autologin '[ERROR] Gagal menulis file: " .. tostring(err) .. "'")
            http.write('{"status":"error","message":"Gagal menulis file."}')
        end
    else
        http.write('{"status":"success","message":"No change needed"}')
    end
end

function get_profiles_api()
    http.prepare_content("application/json")
    local config_file = "/etc/autologin/profiles.json"
    if fs.access(config_file, "r") then
        local f = io.open(config_file, "r")
        if f then
            local content = f:read("*all")
            f:close()
            if content and content ~= "" then
                local parsed = json.parse(content)
                if parsed and parsed.profiles then
                    local portal_rules = load_portal_rules()
                    local response = {
                        profiles = parsed.profiles,
                        portal_config = portal_rules.features
                    }
                    http.write(json.stringify(response))
                    return
                end
            end
        end
    end
    local portal_rules = load_portal_rules()
    http.write(json.stringify({profiles={}, portal_config=portal_rules.features}))
end

function delete_profile_api()
    http.prepare_content("application/json")
    local profile_id = http.formvalue("profile_id")
    if not profile_id then
        http.write('{"status":"error","message":"Missing profile_id"}')
        return
    end
    
    local config_file = "/etc/autologin/profiles.json"
    if not fs.access(config_file, "r") then
        http.write('{"status":"error","message":"Config file not found"}')
        return
    end
    
    local f = io.open(config_file, "r")
    local content = f:read("*all")
    f:close()
    
    local data = json.parse(content)
    if not data or not data.profiles then
        http.write('{"status":"error","message":"Invalid JSON structure"}')
        return
    end
    
    local new_profiles = {}
    local deleted = false
    for _, p in ipairs(data.profiles) do
        if p.id == profile_id then
            deleted = true
        else
            table.insert(new_profiles, p)
        end
    end
    
    if deleted then
        local deleted_logical = ""
        local deleted_device = ""
        local pt = ""
        local pu = ""
        local pm = ""
        
        for _, p in ipairs(data.profiles) do
            if p.id == profile_id then
                deleted_logical = p.logical or ""
                deleted_device = p.device or ""
                pt = p.portal_type or ""
                pu = p.url or ""
                pm = p.mac or ""
                break
            end
        end
        
        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Memulai proses hapus profil " .. profile_id .. " (" .. deleted_logical .. "/" .. deleted_device .. ")'")
        
        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Menghentikan daemon...'")
        luci.sys.exec("/etc/init.d/autologin stop >/dev/null 2>&1")
        luci.sys.exec("sleep 1")

        local daemon_still_running = luci.sys.exec("ps w 2>/dev/null | grep -c '[/]usr/lib/autologin/daemon.sh'"):gsub("\n", "")
        if tonumber(daemon_still_running) and tonumber(daemon_still_running) > 0 then
            luci.sys.exec("logger -t autologin '[WARN] delete_profile_api: Daemon masih berjalan, force kill...'")
            luci.sys.exec("pkill -9 -f '/usr/lib/autologin/daemon.sh' 2>/dev/null")
            luci.sys.exec("sleep 1")
        end
        
        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Menghapus trigger file...'")
        if deleted_device ~= "" then
            luci.sys.exec("rm -f /tmp/autologin_trigger_" .. deleted_device .. " 2>/dev/null")
        end
        
        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Menghapus profil dari profiles.json...'")
        data.profiles = new_profiles
        local json_str = json.stringify(data)
        local tmp_file = config_file .. ".tmp"
        local ok, err = fs.writefile(tmp_file, json_str)
        if not ok then
            luci.sys.exec("logger -t autologin '[ERROR] delete_profile_api: Gagal menulis profiles.json: " .. tostring(err) .. "'")
            -- Rollback: start daemon lagi karena gagal
            luci.sys.exec("/etc/init.d/autologin start >/dev/null 2>&1")
            http.write('{"status":"error","message":"Gagal menghapus profil: ' .. tostring(err) .. '"}')
            return
        end
        safe_rename(tmp_file, config_file)
        
        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Membersihkan state, lock, cookie, debug...'")
        
        local state_file = "/tmp/autologin/state/" .. profile_id .. ".state"
        if fs.access(state_file) then
            os.remove(state_file)
        end
        
        local profil_lock = "/var/run/autologin_" .. profile_id .. ".lock"
        local antiblock_lock = "/var/run/autologin_antiblocking_" .. profile_id .. ".lock"
        if fs.access(profil_lock) then os.remove(profil_lock) end
        if fs.access(antiblock_lock) then os.remove(antiblock_lock) end
        
        luci.sys.exec("pkill -f 'login_executor.sh " .. profile_id .. "' 2>/dev/null")
        luci.sys.exec("pkill -f 'anti_blocking.sh " .. profile_id .. "' 2>/dev/null")
        luci.sys.exec("pkill -f 'health_check.sh " .. deleted_device .. "' 2>/dev/null")
        
        if deleted_logical ~= "" then
            luci.sys.exec("rm -f /tmp/autologin_cookie_" .. deleted_logical .. "_* 2>/dev/null")
        end
        if deleted_device ~= "" then
            luci.sys.exec("rm -f /tmp/autologin/debug/" .. deleted_device .. ".log 2>/dev/null")
        end
        
        if #new_profiles == 0 then
            luci.sys.exec("rm -f /tmp/autologin/debug/login_executor_debug.log 2>/dev/null")
        end

        if pt ~= "" and pu ~= "" and deleted_device ~= "" then
            luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Melakukan logout ke server portal...'")
            local cmd = "sh /usr/lib/autologin/logout.sh '" .. pt:gsub("'", "'\\''") .. "' '" .. pu:gsub("'", "'\\''") .. "' '" .. deleted_device:gsub("'", "'\\''") .. "' '" .. deleted_logical:gsub("'", "'\\''") .. "' '" .. pm:gsub("'", "'\\''") .. "'"
            luci.sys.exec(cmd .. " >/dev/null 2>&1")
        else
            luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Logout dilewati (data tidak lengkap)'")
        end

        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Memulai daemon baru...'")
        luci.sys.exec("/etc/init.d/autologin start >/dev/null 2>&1")
        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Stabilisasi mwan3.'")
        
        luci.sys.exec("logger -t autologin '[INFO] delete_profile_api: Profil " .. profile_id .. " berhasil dihapus beserta seluruh proses, state, lock, cookie, dan debug.'")
        http.write('{"status":"success","message":"Profil dan seluruh proses terkait berhasil dihapus dan dibersihkan."}')
    else
        http.write('{"status":"error","message":"Profil tidak ditemukan"}')
    end
end

function get_status_api()
    http.prepare_content("application/json")
    local state_dir = "/tmp/autologin/state"
    local config_file = "/etc/autologin/profiles.json"
    
    local profiles_data = {profiles={}}
    local f = io.open(config_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local parsed = json.parse(content)
        if parsed then
            profiles_data = parsed
        end
    end
    
    local status_data = {}
    for _, profile in ipairs(profiles_data.profiles) do
        local state_file = state_dir .. "/" .. profile.id .. ".state"
        local state = {status="IDLE", retry_count=0, cooldown_until=0}
        
        local sf = io.open(state_file, "r")
        if sf then
            local state_content = sf:read("*all")
            sf:close()
            local parsed_state = json.parse(state_content)
            if parsed_state then
                state = parsed_state
            end
        end
        
        status_data[profile.id] = {
            status = state.status or "IDLE",
            retry_count = state.retry_count or 0,
            cooldown_until = state.cooldown_until or 0,
            last_update = os.time()
        }
    end
    
    http.write(json.stringify(status_data))
end

function restart_interface_api()
    http.prepare_content("application/json")
    
    local logical = http.formvalue("logical")
    local device = http.formvalue("device")
    
    if not logical or logical == "" then
        luci.sys.exec("logger -t autologin '[ERROR] restart_interface: Parameter logical tidak diberikan'")
        http.write('{"status":"error","message":"Parameter logical tidak diberikan."}')
        return
    end
    
    local uci_check = luci.sys.exec(string.format("uci get network.%s 2>/dev/null", logical)):gsub("\n", "")
    if uci_check == "" then
        luci.sys.exec(string.format("logger -t autologin '[ERROR] restart_interface: Interface logis %s tidak ditemukan di UCI'", logical))
        http.write(string.format('{"status":"error","message":"Interface logis %s tidak ditemukan."}', logical))
        return
    end
    
    luci.sys.exec(string.format("logger -t autologin '[DETECT-URL] Merestart interface logis %s untuk deteksi URL...'", logical))
    
    luci.sys.exec(string.format("ubus call network.interface.%s down >/dev/null 2>&1", logical))
    luci.sys.exec("sleep 2")
    
    luci.sys.exec(string.format("ubus call network.interface.%s up >/dev/null 2>&1", logical))
    
    local timeout = 30
    local interval = 2
    local elapsed = 0
    local ip = ""
    local check_dev = device or luci.sys.exec(string.format("uci -q get network.%s.device 2>/dev/null", logical)):gsub("\n", "")
    
    if check_dev == "" then check_dev = logical end
    
    luci.sys.exec(string.format("logger -t autologin '[DETECT-URL] Menunggu interface %s/%s mendapatkan IP (timeout %d detik)...'", logical, check_dev, timeout))
    
    while elapsed < timeout do
        ip = luci.sys.exec(string.format("ip -4 addr show dev %s 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1", check_dev)):gsub("\n", "")
        if ip ~= "" then
            local gw = luci.sys.exec(string.format("ip route show dev %s 2>/dev/null | awk '/default/{print $3; exit}'", check_dev)):gsub("\n", "")

            if gw ~= "" then
                luci.sys.exec(string.format("logger -t autologin '[DETECT-URL] %s mendapatkan IP: %s, Gateway: %s'", logical, ip, gw))
                luci.sys.exec("sh -c '. /usr/lib/autologin/routing_lib.sh; sync_mwan3_interface_state " .. logical .. " DISCONNECTED'")
                http.write(string.format('{"status":"success","message":"Interface %s berhasil direstart. IP: %s","logical":"%s","device":"%s","ip":"%s"}', logical, ip, logical, check_dev, ip))
                return
            end
        end
        luci.sys.exec(string.format("sleep %d", interval))
        elapsed = elapsed + interval
    end
    
    luci.sys.exec(string.format("logger -t autologin '[DETECT-URL] WARNING: %s tidak mendapatkan IP setelah %d detik'", logical, timeout))
    http.write(string.format('{"status":"warning","message":"Interface %s direstart tapi tidak mendapatkan IP setelah %d detik. Mungkin masih proses atau tidak terhubung.","logical":"%s"}', logical, timeout, logical))
end

function update_enabled_status_api()
    http.prepare_content("application/json")
    local profile_id = http.formvalue("profile_id")
    local enabled_str = http.formvalue("enabled")
    
    if not profile_id or not enabled_str then
        http.write('{"status":"error","message":"Missing parameters"}')
        return
    end
    
    local enabled = (enabled_str == "true")
    local config_file = "/etc/autologin/profiles.json"
    
    if not fs.access(config_file, "r") then
        http.write('{"status":"error","message":"Config file not found"}')
        return
    end
    
    local f = io.open(config_file, "r")
    local content = f:read("*all")
    f:close()
    
    local data = json.parse(content)
    if not data or not data.profiles then
        http.write('{"status":"error","message":"Invalid JSON structure"}')
        return
    end
    
    local updated = false
    for _, p in ipairs(data.profiles) do
        if p.id == profile_id then
            if p.enabled ~= enabled then
                p.enabled = enabled
                updated = true
            end
            break
        end
    end
    
    if updated then
        local json_str = json.stringify(data)
        local tmp_file = config_file .. ".tmp"
        local ok, err = fs.writefile(tmp_file, json_str)
        if ok then
            safe_rename(tmp_file, config_file)
            
            if not enabled then
                local state_file = "/tmp/autologin/state/" .. profile_id .. ".state"
                os.execute("rm -f " .. state_file)
                luci.sys.exec("logger -t autologin '[SISTEM] Profil " .. profile_id .. " dinonaktifkan.'")
            else
                luci.sys.exec("logger -t autologin '[SISTEM] Profil " .. profile_id .. " diaktifkan.'")
            end
            http.write('{"status":"success","message":"Status profil berhasil diperbarui"}')
        else
            luci.sys.exec("logger -t autologin '[ERROR] Gagal menulis profiles.json: " .. tostring(err) .. "'")
            http.write('{"status":"error","message":"Gagal menulis file."}')
        end
    else
        http.write('{"status":"success","message":"Tidak ada perubahan"}')
    end
end