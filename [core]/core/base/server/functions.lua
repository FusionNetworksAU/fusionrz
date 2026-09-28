---@type table<string, true>
local profanities = {}

do
    local raw = GetConvar('core:profanityList', '')

    for word in raw:gmatch('[^,]+') do
        profanities[word:lower():gsub('%s', '')] = true
    end
end

---@param text string?
---@return boolean
function Core.containsProfanity(text)
    if type(text) ~= 'string' or not next(profanities) then
        return false
    end

    local normalised = text:lower():gsub('[^%a]', '')

    for word in pairs(profanities) do
        if normalised:find(word, 1, true) then
            return true
        end
    end

    return false
end

---@param ban BanRecord
---@return string
function Core.formatBanMessage(ban)
    if not ban.expiresAt then
        return ('You are permanently banned.\nReason: %s\nBan ID: %s\nAppeal at %s')
            :format(ban.reason or 'No reason given', ban.id, Core.config.urls.discord)
    end

    local remaining = ban.expiresAt - os.time()
    local hours = math.max(1, math.ceil(remaining / 3600))

    return ('You are banned for another %s hour(s).\nReason: %s\nBan ID: %s\nAppeal at %s'):format(hours, ban.reason or 'No reason given', ban.id, Core.config.urls.discord)
end

exports('GetPlayer', Core.getPlayer)
exports('GetPlayerByUserId', Core.getPlayerByUserId)
exports('GetPlayerByLicense', Core.getPlayerByLicense)
exports('GetPlayers', Core.getPlayers)
exports('GetPlayerCount', Core.getPlayerCount)

---@param source Source
---@return table?
exports('GetPlayerData', function(source)
    local player = Core.getPlayer(source)

    return player and player:getClientData() or nil
end)

---@param source Source
---@param key string
---@return any
exports('GetMetadata', function(source, key)
    local player = Core.getPlayer(source)

    return player and player:getMetadata(key) or nil
end)

---@param source Source
---@param key string
---@param value any
---@return boolean
exports('SetMetadata', function(source, key, value)
    local player = Core.getPlayer(source)

    if not player then
        return false
    end

    player:setMetadata(key, value)

    return true
end)

---@param source Source
---@param amount integer
---@param reason string?
---@return boolean success
---@return integer balance
exports('AddCoins', function(source, amount, reason)
    local player = Core.getPlayer(source)

    if not player then
        return false, 0
    end

    return player:addCoins(amount, reason)
end)

---@param source Source
---@param amount integer
---@param reason string?
---@return boolean success
---@return integer balance
exports('RemoveCoins', function(source, amount, reason)
    local player = Core.getPlayer(source)

    if not player then
        return false, 0
    end

    return player:removeCoins(amount, reason)
end)

---@param source Source
---@return integer
exports('GetCoins', function(source)
    local player = Core.getPlayer(source)

    return player and player.coins or 0
end)

exports('GetWeapons', Core.getWeapons)
exports('GetWeaponsWithAce', Core.getWeaponsWithAce)
exports('GetWeaponDataById', Core.getWeaponData)

---@param source Source
---@param weapon string | integer
---@param ammo integer?
exports('GiveWeapon', function(source, weapon, ammo)
    local player = Core.getPlayer(source)

    return player ~= nil and player:giveWeapon(weapon, ammo)
end)

---@param source Source
---@param weapon string | integer
exports('RemoveWeapon', function(source, weapon)
    local player = Core.getPlayer(source)

    return player ~= nil and player:removeWeapon(weapon)
end)

---@param source Source
exports('RemoveAllWeapons', function(source)
    local player = Core.getPlayer(source)

    if player then
        player:removeAllWeapons()
    end
end)


---@param source Source
---@param reason string
---@param durationSeconds integer? nil = permanent
---@param staff string?
---@return integer? banId
exports('BanPlayer', function(source, reason, durationSeconds, staff)
    local player = Core.getPlayer(source)
    local identifiers = Core.utils.getIdentifiers(source)
    local license = player and player.license or Core.toPrefixedLicense(identifiers.license)

    if not license then
        return nil
    end

    local tokens = Core.utils.getTokens(source)
    local expiresAt = durationSeconds and (os.time() + durationSeconds) or nil

    local banId = Core.db.createBan(player and player.userId or nil, license, tokens[1], reason, expiresAt, staff)

    Core.log('bans', ('%s banned %s: %s'):format(staff or 'SYSTEM', player and player.username or license, reason))

    DropPlayer(source --[[@as string]], Core.formatBanMessage({
        id = banId or 0,
        reason = reason,
        expiresAt = expiresAt,
        staff = staff,
    }))

    return banId
end)

---@param source Source
---@param reason string
exports('KickPlayer', function(source, reason)
    DropPlayer(source --[[@as string]], reason)
end)

---@param text string?
---@return boolean
exports('ContainsProfanity', function(text)
    return Core.containsProfanity(text)
end)

---@param source Source
---@param code string ISO 3166-1 alpha-2
---@return boolean success
---@return string? error
exports('SetCountry', function(source, code)
    local player = Core.getPlayer(source)

    if not player then
        return false, 'No player loaded.'
    end

    local normalised = Core.normaliseCountry(code)

    if not normalised then
        return false, 'That is not a country we recognise.'
    end

    player.country = normalised
    player.dirty = true

    Core.db.saveUser(player.userId, { country = normalised })

    return true
end)

---Renames a player. The shape check, the profanity check, the uniqueness
---check, the save and the statebag sync are all CorePlayer:setUsername's --
---this only reaches it, so callers outside core (shop's username-change
---purchase) cannot end up with their own half of those rules.
---@param source Source
---@param username string
---@return boolean success
---@return string? error
exports('SetUsername', function(source, username)
    local player = Core.getPlayer(source)

    if not player then
        return false, 'No player loaded.'
    end

    return player:setUsername(username)
end)

---A plain array of loaded sources. GetPlayers returns CorePlayer objects,
---which do not survive the msgpack round trip an export makes across a
---resource boundary (metatables and methods are stripped), so anything
---outside core iterates this instead.
---@return Source[]
exports('GetPlayerSources', function()
    local sources = {}

    for playerSource in pairs(Core.getPlayers()) do
        sources[#sources + 1] = playerSource
    end

    return sources
end)

---The shared config (username rules and the website/discord/store URLs).
---Read-only by convention: it crosses the resource boundary as a copy, so
---mutating the result changes nothing here.
---@return table
exports('GetConfig', function()
    return Core.config
end)

---@param source Source
---@param avatar string? a CDN url, or nil to clear it
---@return boolean
exports('SetAvatar', function(source, avatar)
    local player = Core.getPlayer(source)

    if not player then
        return false
    end

    if avatar ~= nil and (type(avatar) ~= 'string' or not avatar:match('^https://cdn%.discordapp%.com/')) then
        return false
    end

    player:setAvatar(avatar)
    player:syncState()

    TriggerClientEvent('core:onAvatarChanged', source, avatar)

    return true
end)
