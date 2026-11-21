local SOURCE = {
    user = "kurbansadbhai-cell",
    repo = "Chess",
    branch = "main",
    folder = "config",
}
local ROOT = "rochess_hax"
local FILES = { "chess", "config", "board_reader", "engine", "input", "overlay", "gui", "app" }
local FORCE_UPDATE = true
local CACHE_BUST = true

local env = (type(getgenv) == "function" and getgenv()) or _G

local function say(msg) print("[rochess hax] " .. msg) end
local function fail(msg)
    warn("[rochess hax] " .. msg)
    error(msg, 0)
end

if type(loadstring) ~= "function" then fail("this executor has no loadstring") end

if env.RochessHax and type(env.RochessHax.Destroy) == "function" then
    pcall(env.RochessHax.Destroy)
end
env.RochessHax = nil

local disk = type(isfile) == "function" and type(readfile) == "function"
    and type(writefile) == "function" and type(isfolder) == "function"
    and type(makefolder) == "function"

if not disk then
    warn("[rochess hax] file functions missing: running from memory, settings will not persist")
    local mem = {}
    if type(isfile) ~= "function" then env.isfile = function(p) return mem[p] ~= nil end end
    if type(readfile) ~= "function" then env.readfile = function(p) return mem[p] end end
    if type(writefile) ~= "function" then env.writefile = function(p, c) mem[p] = c end end
end

local CONFIG_DIR = ROOT .. "/config"
if disk then
    if not isfolder(ROOT) then makefolder(ROOT) end
    if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
end

local function urlFor(name)
    local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s/%s.lua",
        SOURCE.user, SOURCE.repo, SOURCE.branch, SOURCE.folder, name)
    if CACHE_BUST then url ..= "?t=" .. tostring(os.time()) end
    return url
end

local function fetch(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then
        if string.sub(body, 1, 3) == "404" then
            return nil, "404 (private repo, or wrong user/repo/branch/folder/file name)"
        end
        return body
    end
    local doRequest = env.request or env.http_request or (env.syn and env.syn.request)
    if doRequest then
        local ok2, res = pcall(doRequest, { Url = url, Method = "GET" })
        if ok2 and type(res) == "table" then
            if res.StatusCode == 200 and type(res.Body) == "string" and #res.Body > 0 then
                return res.Body
            end
            return nil, "HTTP " .. tostring(res.StatusCode)
        end
    end
    return nil, ok and "empty response" or tostring(body)
end

local sources, toWrite, problems, downloaded = {}, {}, {}, 0

for _, name in ipairs(FILES) do
    local path = CONFIG_DIR .. "/" .. name .. ".lua"
    local cached = disk and isfile(path)
    local src

    if FORCE_UPDATE or not cached then
        local body, why = fetch(urlFor(name))
        if body then
            local chunk, cerr = loadstring(body, "=" .. name)
            if chunk then
                src = body
                toWrite[path] = body
                downloaded += 1
            else
                warn("[rochess hax] " .. name .. " downloaded but does not compile: " .. tostring(cerr))
            end
        else
            warn("[rochess hax] download failed for " .. name .. ": " .. tostring(why))
        end
        if not src and cached then
            src = readfile(path)
            warn("[rochess hax] " .. name .. ": using saved copy")
        end
    else
        src = readfile(path)
    end

    if src then
        sources[name] = src
    else
        table.insert(problems, name)
    end
end

if #problems > 0 then
    fail("could not get: " .. table.concat(problems, ", ")
        .. " | check the repo is public and the file names match exactly")
end

if disk then
    for path, body in pairs(toWrite) do
        local ok, err = pcall(writefile, path, body)
        if not ok then warn("[rochess hax] could not save " .. path .. ": " .. tostring(err)) end
    end
end

local loaded, loading = {}, {}
local function req(name)
    if loaded[name] ~= nil then return loaded[name] end
    local src = sources[name]
    if not src then error("unknown module " .. tostring(name), 2) end
    if loading[name] then error("circular require of " .. name, 2) end
    loading[name] = true
    local chunk, cerr = loadstring(src, "=rochess/" .. name)
    if not chunk then
        loading[name] = nil
        error("compile error in " .. name .. ": " .. tostring(cerr), 0)
    end
    local mod = chunk(req)
    loading[name] = nil
    loaded[name] = mod
    return mod
end

local ok, result = pcall(function() return req("app").start({ root = ROOT }) end)
if not ok then fail("startup failed: " .. tostring(result)) end

env.RochessHax = result
say(("loaded %d modules (%d fresh from %s/%s@%s)"):format(#FILES, downloaded, SOURCE.user, SOURCE.repo, SOURCE.branch))
