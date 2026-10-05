-- Fake player generator v5
-- Owns the pool. Exposes JSON via exports (consumed by nixy_loader which
-- writes them to disk for the DLL to serve).

math.randomseed(os.time())

local function ts() return os.date('%H:%M:%S') end
local function log(tag, msg)
    print(('[fake_players %s][%s] %s'):format(ts(), tag, msg))
end
local function dlog(tag, msg)
    if Config.Debug then log(tag, msg) end
end

local stats = { churns = 0, totalFakesEverMade = 0,
                playersJsonCalls = 0, dynamicJsonCalls = 0, infoJsonCalls = 0 }
local startTime = os.time()

local fakes = {}
local nextId = 65

local function makeFake()
    stats.totalFakesEverMade = stats.totalFakesEverMade + 1
    return {
        endpoint = '127.0.0.1',
        id = 0,
        name = 'Player',
        ping = 0,
        identifiers = {},
    }
end

local function seedPool()
    fakes = {}
    for _ = 1, Config.FakeCount do
        table.insert(fakes, makeFake())
    end
    log('seed', ('pool=%d lifetime=%d'):format(#fakes, stats.totalFakesEverMade))
end

local function churn()
    stats.churns = stats.churns + 1
    if Config.Debug and Config.DebugChurn then
        dlog('churn', ('rotation #%d'):format(stats.churns))
    end
end

local function getRealPlayers()
    local out = {}
    for _, src in ipairs(GetPlayers()) do
        local id = tonumber(src)
        local ids = {}
        for i = 0, GetNumPlayerIdentifiers(src) - 1 do
            table.insert(ids, GetPlayerIdentifier(src, i))
        end
        table.insert(out, {
            endpoint = GetPlayerEndpoint(src) or '0.0.0.0',
            id = id,
            name = GetPlayerName(src) or ('Player_' .. tostring(id)),
            ping = GetPlayerPing(src) or 0,
            identifiers = ids,
        })
    end
    return out
end

local function combinedList()
    local real = getRealPlayers()
    local combined = {}
    for _, r in ipairs(real) do table.insert(combined, r) end
    for _, f in ipairs(fakes) do table.insert(combined, f) end
    if Config.ReportedCap and #combined > Config.ReportedCap then
        while #combined > Config.ReportedCap do
            table.remove(combined)
        end
    end
    return combined, #real
end

-- Exports — nixy_loader (Node.js) calls these every second
exports('GetPlayersJson', function()
    stats.playersJsonCalls = stats.playersJsonCalls + 1
    local list = combinedList()
    return json.encode(list)
end)

exports('GetDynamicJson', function()
    stats.dynamicJsonCalls = stats.dynamicJsonCalls + 1
    local list = combinedList()   -- drops the second return value
    local hostname = Config.OverrideHostname ~= '' and Config.OverrideHostname
        or GetConvar('sv_hostname', 'FiveM Server')
    local gametype = Config.OverrideGametype ~= '' and Config.OverrideGametype
        or GetConvar('gametype', 'Freeroam')
    local mapname  = Config.OverrideMapname  ~= '' and Config.OverrideMapname
        or GetConvar('mapname', 'San Andreas')
    local maxclients = tonumber(GetConvarInt('sv_maxclients', 48))

    return json.encode({
        hostname = hostname,
        gametype = gametype,
        mapname = mapname,
        clients = #list,
        sv_maxclients = tostring(maxclients),
        iv = GetConvar('sv_infoVersion', '0'),
    })
end)

exports('GetInfoJson', function()
    stats.infoJsonCalls = stats.infoJsonCalls + 1
    local resources = {}
    for i = 0, GetNumResources() - 1 do
        table.insert(resources, GetResourceByFindIndex(i))
    end

    return json.encode({
        server = GetConvar('version', 'FXServer'),
        enhancedHostSupport = true,
        resources = resources,
        vars = {
            sv_enforceGameBuild = GetConvar('sv_enforceGameBuild', ''),
            sv_lan = GetConvar('sv_lan', 'false'),
            sv_licenseKeyToken = '',
            sv_maxClients = GetConvar('sv_maxclients', '48'),
            sv_scriptHookAllowed = GetConvar('sv_scriptHookAllowed', 'false'),
            locale = GetConvar('locale', 'en-US'),
            gamename = 'gta5',
        },
        version = tonumber(GetConvar('sv_infoVersion', '0')) or 0,
    })
end)

log('boot', ('starting v5; FakeCount=%d ReportedCap=%s churn=%dms@%.0f%%')
    :format(Config.FakeCount, tostring(Config.ReportedCap),
            Config.ChurnIntervalMs, Config.ChurnRatio * 100))

seedPool()

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.ChurnIntervalMs)
        churn()
    end
end)

if Config.HeartbeatMs > 0 then
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Config.HeartbeatMs)
            log('heartbeat', ('up=%ds pool=%d churns=%d calls p=%d d=%d i=%d lifetime=%d')
                :format(os.time() - startTime, #fakes, stats.churns,
                        stats.playersJsonCalls, stats.dynamicJsonCalls,
                        stats.infoJsonCalls, stats.totalFakesEverMade))
        end
    end)
end

-- After boot, trigger a resource restart so our AddEndpoint hook fires
-- naturally and captures the Manager pointer from `this`.
Citizen.CreateThread(function()
    Citizen.Wait(8000)
    log('bootstrap', 'issuing: restart chat')
    ExecuteCommand('restart chat')
    Citizen.Wait(1000)
    log('bootstrap', 'issuing: restart spawnmanager')
    ExecuteCommand('restart spawnmanager')
    Citizen.Wait(1000)
    log('bootstrap', 'issuing: refresh then restart basic-gamemode')
    ExecuteCommand('restart basic-gamemode')
    Citizen.Wait(1000)
    log('bootstrap', 'bootstrap complete — hook should have fired at least once')
end)

-- txAdmin population: two-pronged approach
-- 1) Fire structured traces so txAdmin's Node.js core registers the players
-- 2) Continuously inject into TX_PLAYERLIST so the Lua-side monitor refresh
--    doesn't wipe them (it removes any ID not found by GetPlayers() each cycle)
if Config.PopulateTxAdmin then
    local function hexpad(n, len)
        local h = string.format('%x', n)
        while #h < len do h = '0' .. h end
        return h
    end

    local txFakeIds = {}
    for i = 1, Config.FakeCount do
        txFakeIds[#txFakeIds + 1] = tostring(900 + i)
    end

    local function txFireJoins()
        for i = 1, Config.FakeCount do
            local fakeId = 900 + i
            local license = 'license:' .. hexpad(0xFACE0000 + i, 40)
            PrintStructuredTrace(json.encode({
                type = 'txAdminPlayerlistEvent',
                event = 'playerJoining',
                id = fakeId,
                player = {
                    name = 'Player',
                    ids = { license },
                    hwids = {},
                },
            }))
        end
        log('txadmin', 'fired ' .. Config.FakeCount .. ' fake playerJoining traces')
    end

    local function txKeepAlive()
        if type(TX_PLAYERLIST) ~= 'table' then
            return false
        end
        for _, sid in ipairs(txFakeIds) do
            if type(TX_PLAYERLIST[sid]) ~= 'table' then
                TX_PLAYERLIST[sid] = {
                    name = 'Player',
                    health = 100,
                    vType = 0,
                    xCoord = 0,
                    yCoord = 0,
                }
            end
            TX_PLAYERLIST[sid].foundLastCheck = true
        end
        return true
    end

    -- Fire traces on boot and re-fire every 60s to keep txAdmin in sync
    Citizen.CreateThread(function()
        Citizen.Wait(10000)
        txFireJoins()
        while true do
            Citizen.Wait(60000)
            txFireJoins()
        end
    end)

    -- Keepalive: run faster than the monitor's refresh (1.5s min) to
    -- ensure foundLastCheck is always true when the monitor checks.
    -- Log TX_PLAYERLIST accessibility on first run.
    local txPlLoggedOnce = false
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(500)
            local ok = txKeepAlive()
            if not txPlLoggedOnce then
                txPlLoggedOnce = true
                if ok then
                    log('txadmin', 'TX_PLAYERLIST is accessible, keepalive active')
                else
                    log('txadmin', 'TX_PLAYERLIST is nil — keepalive cannot inject (this is normal if txAdmin is not running)')
                end
            end
        end
    end)
end

-- Force heartbeat re-send after DLL hooks are installed.
-- The initial heartbeat fires during boot BEFORE nixy_loader injects our DLL,
-- so the WinINET hooks miss it. We wait long enough for the DLL to load and
-- hooks to activate, then force FiveM to send a fresh heartbeat with our
-- patched client count.
Citizen.CreateThread(function()
    Citizen.Wait(15000)
    log('heartbeat-force', 'forcing heartbeat re-send (attempt 1)')
    ExecuteCommand('heartbeat')
    Citizen.Wait(15000)
    log('heartbeat-force', 'forcing heartbeat re-send (attempt 2)')
    ExecuteCommand('heartbeat')
    Citizen.Wait(30000)
    log('heartbeat-force', 'forcing heartbeat re-send (attempt 3)')
    ExecuteCommand('heartbeat')
end)

RegisterCommand('fake_reseed', function(src)
    if src ~= 0 then return end
    log('cmd', 'reseeding pool')
    seedPool()
end, true)

RegisterCommand('fake_heartbeat', function(src)
    if src ~= 0 then return end
    log('cmd', 'forcing heartbeat re-send NOW')
    ExecuteCommand('heartbeat')
end, true)

RegisterCommand('fake_stats', function(src)
    if src ~= 0 then return end
    log('cmd', ('up=%ds pool=%d churns=%d calls p=%d d=%d i=%d lifetime=%d')
        :format(os.time() - startTime, #fakes, stats.churns,
                stats.playersJsonCalls, stats.dynamicJsonCalls,
                stats.infoJsonCalls, stats.totalFakesEverMade))
end, true)
