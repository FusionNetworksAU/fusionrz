---@class CorePlayer
---@field source Source
---@field userId integer
---@field license string
---@field username string
---@field country string?
---@field avatar string?
---@field coins integer
---@field metadata table
---@field weapons table<string, integer> weapon spawn name -> ammo count
---@field playtime integer accumulated seconds, excluding the current session
---@field joinedAt integer os.time of this session's load
---@field identifiers PlayerIdentifiers
---@field tokens string[]
---@field dirty boolean
local CorePlayer = {}
CorePlayer.__index = CorePlayer

Core.CorePlayer = CorePlayer

---@param source Source
---@param user UserRecord
---@param identifiers PlayerIdentifiers
---@param tokens string[]
---@return CorePlayer
function CorePlayer.new(source, user, identifiers, tokens)
    return setmetatable({
        source = source,
        userId = user.userId,
        license = user.license,
        username = user.username,
        country = user.country,
        avatar = user.avatar,
        coins = user.coins,
        metadata = user.metadata or {},
        weapons = {},
        playtime = user.playtime or 0,
        joinedAt = os.time(),
        identifiers = identifiers,
        tokens = tokens,
        dirty = false,
    }, CorePlayer)
end

---@return table
function CorePlayer:getClientData()
    return {
        source = self.source,
        userId = self.userId,
        username = self.username,
        avatar = self.avatar,
        country = self.country,
        coins = self.coins,
        metadata = self.metadata,
        weapons = self.weapons,
        playtime = self:getPlaytime(),
    }
end

---`isLoaded` is deliberately NOT set here. The consumers gate on it before
---reading PlayerData (ui/client/uis/career.lua, outfits.lua), and at this
---point the client has not received its data yet -- so the client sets that
---key itself once it has, in main.lua's loadPlayer.
function CorePlayer:syncState()
    local state = Player(self.source).state

    state:set('userId', self.userId, true)
    state:set('username', self.username, true)
end

---@return integer seconds
function CorePlayer:getPlaytime()
    return self.playtime + (os.time() - self.joinedAt)
end

---@param key string
---@return any
function CorePlayer:getMetadata(key)
    return self.metadata[key]
end

---@param key string
---@param value any
---@param replicate boolean? defaults to true
function CorePlayer:setMetadata(key, value, replicate)
    if type(key) ~= 'string' then
        return
    end

    self.metadata[key] = value
    self.dirty = true

    if replicate ~= false then
        TriggerClientEvent('core:onSetMetadata', self.source, key, value)
        TriggerClientEvent('core:client:onSetMetadata', self.source, key, value)
    end

    TriggerEvent('core:server:onSetMetadata', self.source, key, value)
end

---@param values table<string, any>
function CorePlayer:setMetadataBulk(values)
    for key, value in pairs(values) do
        self:setMetadata(key, value)
    end
end

---@param amount integer
---@param reason string?
---@return boolean success
---@return integer balance
function CorePlayer:addCoins(amount, reason)
    return self:adjustCoins(math.abs(math.floor(amount or 0)), reason)
end

---@param amount integer
---@param reason string?
---@return boolean success
---@return integer balance
function CorePlayer:removeCoins(amount, reason)
    return self:adjustCoins(-math.abs(math.floor(amount or 0)), reason)
end

---@param delta integer
---@param reason string?
---@return boolean success
---@return integer balance
function CorePlayer:adjustCoins(delta, reason)
    if delta == 0 then
        return true, self.coins
    end

    local newBalance = Core.db.adjustCoins(self.userId, delta)

    if not newBalance then
        return false, self.coins
    end

    local oldAmount = self.coins
    self.coins = newBalance

    TriggerClientEvent('core:onCoinsChange', self.source, {
        oldAmount = oldAmount,
        newAmount = newBalance,
        delta = delta,
    })

    Core.log('coins', ('%s (%s) %s %s coins [%s] -> %s'):format(
        self.username, self.userId, delta > 0 and 'gained' or 'spent', math.abs(delta), reason or 'unspecified', newBalance
    ))

    return true, newBalance
end

---@param weapon string | integer
---@param ammo integer?
---@return boolean
function CorePlayer:giveWeapon(weapon, ammo)
    local weaponId = Core.resolveWeaponId(weapon)

    if not weaponId then
        return false
    end

    ammo = math.max(0, math.floor(ammo or 0))
    self.weapons[weaponId] = ammo

    TriggerClientEvent('core:onGiveWeapon', self.source, weaponId, ammo)

    return true
end

---@param weapon string | integer
---@param ammo integer
---@return boolean
function CorePlayer:setWeaponAmmo(weapon, ammo)
    local weaponId = Core.resolveWeaponId(weapon)

    if not weaponId or not self.weapons[weaponId] then
        return false
    end

    ammo = math.max(0, math.floor(ammo or 0))
    self.weapons[weaponId] = ammo

    TriggerClientEvent('core:onSetWeaponAmmo', self.source, weaponId, ammo)

    return true
end

---@param weapon string | integer
---@return boolean
function CorePlayer:removeWeapon(weapon)
    local weaponId = Core.resolveWeaponId(weapon)

    if not weaponId or not self.weapons[weaponId] then
        return false
    end

    self.weapons[weaponId] = nil

    TriggerClientEvent('core:onRemoveWeapon', self.source, weaponId)

    return true
end

function CorePlayer:removeAllWeapons()
    table.wipe(self.weapons)

    TriggerClientEvent('core:onRemoveAllWeapons', self.source)
end

---@param weapon string | integer
---@return boolean
function CorePlayer:hasWeapon(weapon)
    local weaponId = Core.resolveWeaponId(weapon)

    return weaponId ~= nil and self.weapons[weaponId] ~= nil
end

---@param username string
---@return boolean success
---@return string? error
function CorePlayer:setUsername(username)
    local valid, reason = Core.isUsernameShapeValid(username)

    if not valid then
        return false, reason
    end

    if Core.containsProfanity(username) then
        return false, locale('username_profanity')
    end

    if Core.db.isUsernameTaken(username) then
        return false, locale('username_taken')
    end

    self.username = username
    self.dirty = true

    Core.db.saveUser(self.userId, { username = username })

    self:syncState()

    return true
end

---@param avatar string?
function CorePlayer:setAvatar(avatar)
    self.avatar = avatar
    self.dirty = true
end

---@return vector3
function CorePlayer:getCoords()
    return GetEntityCoords(GetPlayerPed(self.source --[[@as string]]))
end

---@param reason string
function CorePlayer:kick(reason)
    DropPlayer(self.source --[[@as string]], reason)
end

---@param force boolean?
function CorePlayer:save(force)
    if not self.dirty and not force then
        return
    end

    local sessionSeconds = os.time() - self.joinedAt

    Core.db.saveUser(self.userId, {
        username = self.username,
        avatar = self.avatar,
        country = self.country,
        metadata = self.metadata,
    })

    if sessionSeconds > 0 then
        Core.db.addPlaytime(self.userId, sessionSeconds)

        self.playtime += sessionSeconds
        self.joinedAt = os.time()
    end

    self.dirty = false
end

return CorePlayer
