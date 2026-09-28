---Core's client half: the local player cache, the item catalogue mirror, and
---every export the UI calls.
---
---Loads after '@ox_lib/init.lua', so `lib` and `cache` are available here --
---unlike base/client/init.lua, which is inlined into other resources ahead
---of ox_lib and has to stay dependency-free.

local config = require 'config.client'
local weapons = require 'data.weapons'
local locations = require 'data.locations'
local LibDeflate = require 'modules.deflate'

local playerState = LocalPlayer.state

-- ------------------------------------------------------------- weapons ----

---@type table<string, WeaponData>
local weaponsWithAce = {}

for weaponId, weaponData in pairs(weapons) do
    if weaponData.ace then
        weaponsWithAce[weaponId] = weaponData
    end
end

exports('GetWeapons', function()
    return weapons
end)

exports('GetWeaponsWithAce', function()
    return weaponsWithAce
end)

---@param weaponId string
exports('GetWeaponDataById', function(weaponId)
    return weapons[weaponId]
end)

-- --------------------------------------------------------- player data ----

---@type table
local playerData = {}

local isLoaded = false

---@return table
local function getPlayerData()
    return playerData
end

---Replaces the cache without running the load flow. The signup path calls
---this before core:loadPlayer so the UI can read the new account while the
---spawn is still in progress.
---@param data table
local function syncPlayerDataFromServer(data)
    if type(data) ~= 'table' then
        return
    end

    -- Consumers read PlayerData.metadata.<key> directly behind the isLoaded
    -- gate (ui/client/uis/career.lua, outfits.lua), so these two are
    -- guaranteed to be tables rather than left to whatever the row held.
    data.metadata = data.metadata or {}
    data.weapons = data.weapons or {}

    playerData = data
end

exports('GetPlayerData', getPlayerData)
exports('SyncPlayerDataFromServer', syncPlayerDataFromServer)

-- ----------------------------------------------------------- inventory ----

---@type table<string, true>
local ownedTypeIds = {}

---@type table<string, string>
local equippedByCategory = {}

---@param snapshot table?
---@param affectedTypeIds string[]? which item ids changed, nil for a full reload
local function applyInventorySnapshot(snapshot, affectedTypeIds)
    table.wipe(ownedTypeIds)
    table.wipe(equippedByCategory)

    if type(snapshot) ~= 'table' then
        return
    end

    for _, typeId in pairs(snapshot.typeIds or {}) do
        ownedTypeIds[typeId] = true
    end

    for category, itemId in pairs(snapshot.equipped or {}) do
        equippedByCategory[category] = itemId
    end

    -- Raised only once the snapshot above has been applied, so a consumer
    -- reacting to it is reading the new inventory rather than the old one.
    TriggerEvent('core:onInventoryUpdated', affectedTypeIds)
end

---@param category ItemCategory? when given, only ids of that category
---@return string[]
local function getUsableTypeIds(category)
    ---@type string[]
    local typeIds = {}

    for typeId in pairs(ownedTypeIds) do
        if not category or (items[typeId] and items[typeId].category == category) then
            typeIds[#typeIds + 1] = typeId
        end
    end

    return typeIds
end

exports('ApplyInventorySnapshot', applyInventorySnapshot)
exports('GetUsableTypeIds', getUsableTypeIds)

---@param category string
exports('GetEquippedItemId', function(category)
    return equippedByCategory[category]
end)

RegisterNetEvent('core:client:inventorySnapshot', applyInventorySnapshot)

-- --------------------------------------------------------------- items ----

---@type ItemsLookup
local items = {}

---@type HandItemsLookup
local handItems = {}

local itemsReady = false

local function fetchItems()
    -- Arrives deflate-compressed: see the note on core:server:getItems. An
    -- uncompressed catalogue was large enough to exceed the net event size
    -- limit, which shows up here only as the callback never returning.
    local compressed = lib.callback.await('core:server:getItems', false)

    if type(compressed) ~= 'string' then
        return false
    end

    local decompressed = LibDeflate:DecompressDeflate(compressed)
    local payload = decompressed and json.decode(decompressed)

    if not payload then
        lib.print.error('[core] item catalogue arrived but could not be decoded')

        return false
    end

    items = payload.items or {}
    handItems = payload.handItems or {}
    itemsReady = true

    -- imports/items.lua reseeds from this, in this resource and in every
    -- other one that inlined it.
    TriggerEvent('core:itemsReady')

    return true
end

exports('AreItemsReady', function()
    return itemsReady
end)

exports('GetAllItems', function()
    return items
end)

exports('GetAllHandItems', function()
    return handItems
end)

---@param itemId string
exports('GetItem', function(itemId)
    return items[itemId]
end)

---The server fires this with no payload: broadcasting the whole catalogue to
---everyone on every refresh is a lot of traffic for a table most clients
---already hold, so each client pulls it instead.
RegisterNetEvent('core:itemsReady', function()
    CreateThread(fetchItems)
end)

RegisterNetEvent('core:onItemDeletedById', function(itemId)
    items[itemId] = nil
    ownedTypeIds[itemId] = nil
end)

---Calling cards, in the shape callingcards/client/main.lua reads them:
---`name`/`type` rather than the catalogue's `label`/`category`, because the
---card's own type (general, ranked, gang...) lives in its data blob and the
---category is always 'calling_cards'.
---@param item Item
---@return table
local function toCard(item)
    return {
        id = item.id,
        name = item.label,
        description = item.description,
        type = item.type or 'general',
    }
end

---@return table<string, table>
exports('GetAllCards', function()
    local cards = {}

    for itemId, item in pairs(items) do
        if item.category == 'calling_cards' then
            cards[itemId] = toCard(item)
        end
    end

    return cards
end)

---@param itemId string
---@return table?
exports('GetCardItem', function(itemId)
    local item = items[itemId]

    return (item and item.category == 'calling_cards') and toCard(item) or nil
end)

---The podium in `gamemodes` plays a winner's equipped emote and reads `dict`
---and `anim` off the row, so the item is returned as-is rather than reshaped
---the way calling cards are.
---@param itemId string
---@return table?
exports('GetEmoteItem', function(itemId)
    local item = items[itemId]

    return (item and item.category == 'emotes') and item or nil
end)

-- ------------------------------------------------------------ teleports ----

local FADE_MS = 500

---@param coords vector3 | vector4
---@param withFade boolean?
---@return boolean
local function teleportToCoords(coords, withFade)
    if not coords then
        return false
    end

    local ped = cache.ped

    if withFade and not IsScreenFadedOut() then
        DoScreenFadeOut(FADE_MS)

        while not IsScreenFadedOut() do
            Wait(0)
        end
    end

    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)

    if coords.w then
        SetEntityHeading(ped, coords.w)
    end

    -- Without this the player falls through the map: the collision around
    -- the destination has not streamed in yet, and the ped is already there.
    local deadline = GetGameTimer() + 10000

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    SetPedCoordsKeepVehicle(ped, coords.x, coords.y, coords.z)

    if withFade then
        DoScreenFadeIn(FADE_MS)
    end

    return true
end

exports('TeleportToCoords', teleportToCoords)

RegisterNetEvent('core:client:teleportToSpawn', function()
    teleportToCoords(config.spawnLocation, true)
end)

-- ------------------------------------------------------ location report ----

---Occupancy for the teleport menu is counted server-side, which means the
---server has to be told when the local player walks in or out of a location.
---Polled rather than zoned: at one second per sweep over a table this size
---the cost is nothing, and it needs no per-location zone objects.
local LOCATION_POLL_MS = 1000

local currentLocation

local function pollLocation()
    local coords = GetEntityCoords(cache.ped)
    local found

    for key, location in pairs(locations) do
        if location.coords then
            local radius = location.radius or 75.0

            if #(coords - vec3(location.coords.x, location.coords.y, location.coords.z)) <= radius then
                found = key
                break
            end
        end
    end

    if found == currentLocation then
        return
    end

    local previous = currentLocation and locations[currentLocation]

    if previous and previous.onExit then
        pcall(previous.onExit)
    end

    currentLocation = found

    local entered = found and locations[found]

    if entered and entered.onEnter then
        pcall(entered.onEnter)
    end

    TriggerServerEvent('core:server:setLocation', found)
end

exports('GetCurrentLocation', function()
    return currentLocation
end)

-- ---------------------------------------------------------- appearance ----

---The appearance resource is referenced by name rather than a hard
---dependency: this server renames illenium-appearance to `appearance`, and
---falling back keeps the export working either way.
---@return string?
local function getAppearanceResource()
    if GetResourceState('appearance') == 'started' then
        return 'appearance'
    end

    if GetResourceState('illenium-appearance') == 'started' then
        return 'illenium-appearance'
    end

    return nil
end

---@param appearance table
local function updatePlayerAppearance(appearance)
    if type(appearance) ~= 'table' then
        return false
    end

    local resource = getAppearanceResource()

    if resource then
        pcall(function()
            exports[resource]:setPedAppearance(cache.ped, appearance)
        end)
    end

    TriggerServerEvent('core:server:saveAppearance', appearance)

    return true
end

exports('UpdatePlayerAppearance', updatePlayerAppearance)

exports('GetDefaultAppearanceConfig', function()
    return config.defaultAppearanceConfig
end)

-- --------------------------------------------------------------- death ----

---@param coords vector3 | vector4 | nil
---@param instant boolean?
local function reviveSelf(coords, instant)
    local ped = cache.ped
    local target = coords or GetEntityCoords(ped)
    local heading = (coords and coords.w) or GetEntityHeading(ped)

    NetworkResurrectLocalPlayer(target.x, target.y, target.z, heading, true, false)

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    SetPlayerInvincible(cache.playerId, false)

    playerState:set('isDead', false, true)

    if not instant then
        DoScreenFadeIn(FADE_MS)
    end

    TriggerEvent('core:client:onRevived')
end

exports('reviveSelf', reviveSelf)

---Server-driven respawn (gamemodes rounds). `coords` is where to come back;
---without it the player is revived where they fell.
---@param coords vector4?
RegisterNetEvent('core:client:revive', function(coords)
    reviveSelf(coords)
end)

---ui/client/uis/lobbies.lua watches the isDead statebag to offer the instant
---revive, and the pause menu locks itself while it is set, so this has to be
---published rather than kept local.
local function pollDeath()
    local dead = IsEntityDead(cache.ped) or IsPlayerDead(cache.playerId)

    if dead ~= (playerState.isDead == true) then
        playerState:set('isDead', dead, true)

        TriggerEvent(dead and 'core:client:onDied' or 'core:client:onRevived')
    end
end

-- --------------------------------------------------- subscribe / report ----

---@type table<string, integer>
local subscriptionCounts = {}

---Reference counted: two menus asking for the same topic must not have the
---first one to close cancel the push for the other.
---@param topic string
exports('Subscribe', function(topic)
    if type(topic) ~= 'string' then
        return
    end

    local count = (subscriptionCounts[topic] or 0) + 1
    subscriptionCounts[topic] = count

    if count == 1 then
        TriggerServerEvent('core:server:subscribe', topic)
    end
end)

---@param topic string
exports('Unsubscribe', function(topic)
    local count = subscriptionCounts[topic]

    if not count then
        return
    end

    count -= 1

    if count > 0 then
        subscriptionCounts[topic] = count

        return
    end

    subscriptionCounts[topic] = nil

    TriggerServerEvent('core:server:unsubscribe', topic)
end)

---@param report table
exports('ReportHardware', function(report)
    if type(report) ~= 'table' then
        return
    end

    TriggerServerEvent('core:server:reportHardware', report)
end)

-- ---------------------------------------------------------- player load ----

---Every player starts in the same friendly relationship group, and by
---default a friendly cannot hurt a friendly -- so with nothing switching this
---on, shots between players did no damage and nobody could be killed.
---qbx_core used to do it; core replaced qbx_core without carrying it over.
---Turn off with `setr core:pvp 0`.
local PVP_ENABLED = GetConvarInt('core:pvp', 1) == 1

---@param ped integer
local function applyPvp(ped)
    SetCanAttackFriendly(ped, PVP_ENABLED, false)
    NetworkSetFriendlyFireOption(PVP_ENABLED)
end

-- The setting belongs to the ped, and the ped is replaced on a model change
-- (appearance) and some respawns, so it is re-applied to each new one.
lib.onCache('ped', function(ped)
    if isLoaded then
        applyPvp(ped)
    end
end)

local function applyPlayerStats()
    for statName, value in pairs(config.maxPlayerStats) do
        StatSetInt(joaat(statName), value, true)
    end
end

---@param data table
local function loadPlayer(data)
    if isLoaded then
        return
    end

    syncPlayerDataFromServer(data)

    isLoaded = true

    applyPlayerStats()

    SetPlayerInvincible(cache.playerId, false)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    teleportToCoords(config.spawnLocation, true)

    -- A player joins frozen with controls off until a spawn script lets them
    -- go. That is spawnmanager's job on a stock server, but nothing here calls
    -- it, so without this everyone hung frozen at the spawn point. Released
    -- only after teleportToCoords has waited for the ground to stream in, so
    -- they land rather than fall through.
    FreezeEntityPosition(cache.ped, false)
    SetEntityCollision(cache.ped, true, true)
    SetEntityVisible(cache.ped, true, false)
    SetPlayerControl(cache.playerId, true, 0)

    applyPvp(cache.ped)

    playerState:set('isDead', false, true)

    -- Set here and not on the server: this is the first moment PlayerData is
    -- actually populated, and every consumer treats isLoaded as permission
    -- to read it.
    playerState:set('isLoaded', true, true)

    TriggerEvent('core:onPlayerLoaded')

    CreateThread(function()
        while isLoaded do
            pollDeath()
            pollLocation()

            Wait(LOCATION_POLL_MS)
        end
    end)
end

exports('loadPlayer', loadPlayer)

exports('IsPlayerLoaded', function()
    return isLoaded
end)

-- ------------------------------------------------------- data mirroring ----

RegisterNetEvent('core:onCoinsChange', function(data)
    playerData.coins = data.newAmount
end)

RegisterNetEvent('core:onSetMetadata', function(key, value)
    if playerData.metadata then
        playerData.metadata[key] = value
    end
end)

-- These events are the only thing the server sends when it gives or takes a
-- weapon, so this is where the ped actually gets it. They used to update the
-- cache alone, which left gamemode loadouts recorded but never in hand.

---GiveWeaponToPed throws on a hash the game does not know, which is what an
---addon weapon that is not streamed looks like.
---@param weaponName string
---@return integer?
local function validWeaponHash(weaponName)
    local hash = type(weaponName) == 'string' and joaat(weaponName) or nil

    return hash and IsWeaponValid(hash) and hash or nil
end

RegisterNetEvent('core:onGiveWeapon', function(weaponHash, ammoCount)
    playerData.weapons = playerData.weapons or {}
    playerData.weapons[weaponHash] = ammoCount

    local hash = validWeaponHash(weaponHash)

    if not hash then
        return lib.print.warn(('[core] weapon "%s" is not on this server; not giving it.'):format(weaponHash))
    end

    GiveWeaponToPed(cache.ped, hash, ammoCount or 0, false, false)
end)

RegisterNetEvent('core:onSetWeaponAmmo', function(weaponHash, ammoCount)
    playerData.weapons = playerData.weapons or {}
    playerData.weapons[weaponHash] = ammoCount

    local hash = validWeaponHash(weaponHash)

    if hash and HasPedGotWeapon(cache.ped, hash, false) then
        SetPedAmmo(cache.ped, hash, ammoCount or 0)
    end
end)

RegisterNetEvent('core:onRemoveWeapon', function(weaponHash)
    if playerData.weapons then
        playerData.weapons[weaponHash] = nil
    end

    local hash = validWeaponHash(weaponHash)

    if hash then
        RemoveWeaponFromPed(cache.ped, hash)
    end
end)

RegisterNetEvent('core:onRemoveAllWeapons', function()
    playerData.weapons = {}

    RemoveAllPedWeapons(cache.ped, true)
end)

-- --------------------------------------------------------------- spawn ----

---The handshake: ask the server for this license's account. A table is a
---returning player, `false` means there is no account yet and the signup UI
---owns the rest of the flow, and nil means the server refused (it has
---already dropped the connection by then).
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(100)
    end

    -- The items callback is registered on the server, so it is safe to ask
    -- for the catalogue as soon as the session is up.
    CreateThread(fetchItems)

    local data = lib.callback.await('core:server:requestPlayer', false)

    if data == nil then
        return
    end

    if data == false then
        -- 'started' only means ui's scripts are running; its NUI page mounts
        -- later and reports in through the `init` callback (uisReady). Sent
        -- any earlier, setSignupVisible has no listener and is dropped,
        -- leaving the player on a faded-out screen with nothing on it.
        while GetResourceState('ui') ~= 'started' or not playerState.uisReady do
            Wait(100)
        end

        return exports.ui:displaySignup()
    end

    applyInventorySnapshot(lib.callback.await('core:server:getInventory', false))

    loadPlayer(data)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then
        return
    end

    isLoaded = false

    playerState:set('isLoaded', false, true)
end)
