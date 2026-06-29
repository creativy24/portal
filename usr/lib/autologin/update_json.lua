#!/usr/bin/lua

local json = require "luci.jsonc"
local fs = require "nixio.fs"

local profile_id = arg[1]
local probe_url = arg[2]
local new_ip = arg[3] or ""

local json_lock = "/var/run/autologin_json.lock"

local function cleanup_lock()
    os.execute("flock -u 200 2>/dev/null")
    os.execute("rm -f " .. json_lock .. " 2>/dev/null")
end

if not profile_id or not probe_url then
    os.execute('logger -t autologin "[ERROR] update_json.lua: Argumen tidak lengkap. Gunakan: update_json.lua <profile_id> <probe_url> <new_ip>"')
    os.exit(1)
end

os.execute("touch " .. json_lock .. " 2>/dev/null")
local lock_ok = os.execute(string.format("flock -n 200 2>/dev/null", json_lock))
if not lock_ok then
    os.execute('logger -t autologin "[INFO] update_json.lua: Proses penulisan lain sedang berjalan. Menunggu giliran..."')
    os.execute(string.format("flock -x 200", json_lock))
end

local config_file = "/etc/autologin/profiles.json"
if not fs.access(config_file, "r") then
    cleanup_lock()
    os.execute('logger -t autologin "[ERROR] update_json.lua: File profiles.json tidak ditemukan di ' .. config_file .. '"')
    os.exit(1)
end

local f = io.open(config_file, "r")
if not f then
    cleanup_lock()
    os.execute('logger -t autologin "[ERROR] update_json.lua: Gagal membuka profiles.json untuk dibaca."')
    os.exit(1)
end
local content = f:read("*all")
f:close()

local data = json.parse(content)
if not data or not data.profiles then
    cleanup_lock()
    os.execute('logger -t autologin "[ERROR] update_json.lua: Format profiles.json tidak sesuai."')
    os.exit(1)
end

local function load_portal_patterns()
    local portal_file = "/usr/lib/autologin/captive-detect/portal.json"
    if not fs.access(portal_file, "r") then
        return {}
    end
    local f = io.open(portal_file, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    local ok, parsed = pcall(json.parse, content)
    if not ok or not parsed or not parsed.patterns then
        return {}
    end
    return parsed.patterns
end

local function url_decode(str)
    if not str then return "" end
    str = str:gsub('+', ' ')
    str = str:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
    return str
end

local function get_query_param(url, param)
    local match = url:match("[?&]" .. param .. "=([^&]*)")
    return match or ""
end

local function replace_query_param(url, param, new_value)
    if url:find("[?&]" .. param .. "=") then
        return url:gsub("([?&]" .. param .. "=)[^&]*", "%1" .. new_value)
    else
        if url:find("?") then
            return url .. "&" .. param .. "=" .. new_value
        else
            return url .. "?" .. param .. "=" .. new_value
        end
    end
end

local function replace_path(url, new_path)
    return url:gsub("^(https?://[^/]+)(/[^?]*)", "%1" .. new_path)
end

local function json_pretty_print(data)
    local s = json.stringify(data, true)
    return s:gsub("\\/", "/")
end

local patterns = load_portal_patterns()

local updated = false
for _, p in ipairs(data.profiles) do
    if p.id == profile_id then
        local old_url = p.url or ""
        local portal_type = p.portal_type or ""
        local saved_mac = p.mac or ""
        local old_sessionid = p.sessionid or ""
        local old_gw_id = p.gw_id or ""
        local old_wlan = p.wlan or ""
        local old_ipc = p.ipc or ""
        
        os.execute('logger -t autologin "[INFO] update_json.lua: Memproses profil ' .. profile_id .. ' (tipe: ' .. portal_type .. ')."')

        local probe_path = probe_url:match("^https?://[^/]+(/[^?]*)") or "/"
        local old_path = old_url:match("^https?://[^/]+(/[^?]*)") or "/"
        local target_path = old_path
        local path_found = false
        
        for _, pat in ipairs(patterns) do
            if pat.type_key == portal_type and pat.path_key and pat.path_key ~= "" then
                if old_path:find(pat.path_key, 1, true) then
                    target_path = pat.path_key
                    path_found = true
                    break
                end
            end
        end
        
        if not path_found then
            os.execute('logger -t autologin "[INFO] update_json.lua: Alamat halaman tidak berubah. Tidak ada pola yang cocok di portal.json untuk ' .. old_path .. '"')
        end
        
        local final_url = probe_url
        if target_path ~= "/" and not probe_path:find(target_path, 1, true) then
            final_url = replace_path(probe_url, target_path)
            os.execute('logger -t autologin "[INFO] update_json.lua: Alamat halaman disesuaikan dari ' .. probe_path .. ' menjadi ' .. target_path .. '"')
        end
        
        if saved_mac ~= "" then
            local url_mac = get_query_param(final_url, "client_mac")
            if url_mac ~= "" and url_decode(url_mac) ~= saved_mac then
                final_url = replace_query_param(final_url, "client_mac", saved_mac)
                os.execute('logger -t autologin "[INFO] update_json.lua: MAC address di URL disesuaikan menjadi ' .. saved_mac .. '"')
            end
        end
        
        local final_ipc = url_decode(get_query_param(final_url, "ipc"))
        if final_ipc == "" and new_ip ~= "" then
            final_ipc = new_ip
            os.execute('logger -t autologin "[INFO] update_json.lua: Alamat IP diisi dari antarmuka: ' .. new_ip .. '"')
        end
        
        local final_gw_id = url_decode(get_query_param(final_url, "gw_id"))
        local final_wlan = url_decode(get_query_param(final_url, "wlan"))
        local final_sessionid = url_decode(get_query_param(final_url, "sessionid"))
        
        if p.url ~= final_url then
            p.url = final_url
            updated = true
            os.execute('logger -t autologin "[INFO] update_json.lua: URL diperbarui."')
        end
        
        if final_gw_id ~= "" and p.gw_id ~= final_gw_id then
            p.gw_id = final_gw_id
            updated = true
            os.execute('logger -t autologin "[INFO] update_json.lua: GW_ID diperbarui: ' .. old_gw_id .. ' -> ' .. final_gw_id .. '"')
        end
        
        if final_wlan ~= "" and p.wlan ~= final_wlan then
            p.wlan = final_wlan
            updated = true
            os.execute('logger -t autologin "[INFO] update_json.lua: WLAN diperbarui: ' .. old_wlan .. ' -> ' .. final_wlan .. '"')
        end
        
        if final_sessionid ~= "" and p.sessionid ~= final_sessionid then
            p.sessionid = final_sessionid
            updated = true
            os.execute('logger -t autologin "[INFO] update_json.lua: SESSIONID diperbarui: ' .. old_sessionid .. ' -> ' .. final_sessionid .. '"')
        end
        
        if final_ipc ~= "" and p.ipc ~= final_ipc then
            p.ipc = final_ipc
            updated = true
            os.execute('logger -t autologin "[INFO] update_json.lua: IPC diperbarui: ' .. old_ipc .. ' -> ' .. final_ipc .. '"')
        end
        
        break
    end
end

if updated then
    local json_str = json_pretty_print(data)
    local tmp_file = config_file .. ".tmp"
    local ok, err = fs.writefile(tmp_file, json_str)
    if ok then
        local ok = os.rename(tmp_file, config_file)
        if not ok then
            os.execute("mv " .. tmp_file .. " " .. config_file .. " 2>/dev/null")
        end
        os.execute('logger -t autologin "[INFO] update_json.lua: Berhasil memperbarui data profil ' .. profile_id .. '."')
    else
        os.execute('logger -t autologin "[ERROR] update_json.lua: Gagal menyimpan file. Detail: ' .. tostring(err) .. '"')
    end
else
    os.execute('logger -t autologin "[INFO] update_json.lua: Tidak ada perubahan data untuk profil ' .. profile_id .. '."')
end

cleanup_lock()