local json = json

---@param value string?
---@param default table
---@return table
local function decode(value, default)
    if type(value) ~= 'string' or value == '' then
        return default
    end

    local ok, decoded = pcall(json.decode, value)

    if not ok or type(decoded) ~= 'table' then
        return default
    end

    return decoded
end

---@param row table?
---@return UserRecord?
local function hydrateUser(row)
    if not row then
        return nil
    end

    return {
        userId = row.userId,
        license = row.license,
        username = row.username,
        country = row.country,
        avatar = row.avatar,
        coins = row.coins or 0,
        metadata = decode(row.metadata, {}),
        playtime = row.playtime or 0,
        createdAt = row.created_at,
        lastSeen = row.last_seen,
    }
end

local SELECT_USER = [[
    SELECT u.userId, u.username, u.license,
           p.country, p.avatar, p.coins, p.metadata, p.playtime, p.created_at, p.last_seen
    FROM users u
    LEFT JOIN user_profiles p ON p.user_id = u.userId
]]

---@param userId integer
local function ensureProfile(userId)
    MySQL.insert.await('INSERT IGNORE INTO user_profiles (user_id) VALUES (?)', { userId })
end

Core.db.ensureProfile = ensureProfile

---@param license string
---@return UserRecord?
function Core.db.getUserByLicense(license)
    local row = MySQL.single.await(SELECT_USER .. ' WHERE u.license = ?', { license })

    if not row then
        return nil
    end

    if row.coins == nil then
        ensureProfile(row.userId)

        row = MySQL.single.await(SELECT_USER .. ' WHERE u.userId = ?', { row.userId })
    end

    return hydrateUser(row)
end

---@param userId integer
---@return UserRecord?
function Core.db.getUserById(userId)
    local row = MySQL.single.await(SELECT_USER .. ' WHERE u.userId = ?', { userId })

    if row and row.coins == nil then
        ensureProfile(userId)

        row = MySQL.single.await(SELECT_USER .. ' WHERE u.userId = ?', { userId })
    end

    return hydrateUser(row)
end

---@param userIds integer[]
---@return table<integer, string> usernamesByUserId
function Core.db.getUsernames(userIds)
    if #userIds == 0 then
        return {}
    end

    local placeholders = string.rep('?', #userIds, ',')
    local rows = MySQL.query.await(('SELECT userId, username FROM users WHERE userId IN (%s)'):format(placeholders), userIds)

    ---@type table<integer, string>
    local usernames = {}

    for index = 1, #(rows or {}) do
        local row = rows[index]
        usernames[row.userId] = row.username
    end

    return usernames
end

---Case-insensitive on purpose: two usernames that differ only in case are the
---same name as far as impersonation is concerned.
---@param username string
---@return boolean
function Core.db.isUsernameTaken(username)
    local row = MySQL.single.await('SELECT 1 AS taken FROM users WHERE LOWER(username) = LOWER(?) LIMIT 1', { username })

    return row ~= nil
end

---@param identifiers PlayerIdentifiers
---@param username string
---@param country string?
---@return integer? userId
function Core.db.createUser(identifiers, username, country)
    local userId = MySQL.insert.await(
        'INSERT INTO users (username, license, license2, fivem, discord) VALUES (?, ?, ?, ?, ?)',
        {
            username,
            Core.toPrefixedLicense(identifiers.license),
            Core.toPrefixedIdentifier('license2', identifiers.license2),
            Core.toPrefixedIdentifier('fivem', identifiers.fivem),
            Core.toPrefixedIdentifier('discord', identifiers.discord),
        }
    )

    if not userId then
        return nil
    end

    MySQL.insert.await(
        'INSERT INTO user_profiles (user_id, country, metadata) VALUES (?, ?, ?)',
        { userId, country, json.encode({}) }
    )

    return userId
end

---@param userId integer
---@param fields { username?: string, avatar?: string, coins?: integer, metadata?: table, country?: string }
function Core.db.saveUser(userId, fields)
    if fields.username then
        MySQL.update.await('UPDATE users SET username = ? WHERE userId = ?', { fields.username, userId })
    end

    MySQL.update.await(
        'UPDATE user_profiles SET avatar = COALESCE(?, avatar), coins = COALESCE(?, coins), country = COALESCE(?, country), metadata = COALESCE(?, metadata), last_seen = NOW() WHERE user_id = ?',
        {
            fields.avatar,
            fields.coins,
            fields.country,
            fields.metadata and json.encode(fields.metadata) or nil,
            userId,
        }
    )
end

---@param userId integer
---@param seconds integer
function Core.db.addPlaytime(userId, seconds)
    MySQL.update.await('UPDATE user_profiles SET playtime = playtime + ?, last_seen = NOW() WHERE user_id = ?', { seconds, userId })
end

---@param userId integer
---@param delta integer
---@param allowNegative boolean?
---@return integer? newBalance
function Core.db.adjustCoins(userId, delta, allowNegative)
    local affected = MySQL.update.await(
        allowNegative
            and 'UPDATE user_profiles SET coins = coins + ? WHERE user_id = ?'
            or 'UPDATE user_profiles SET coins = coins + ? WHERE user_id = ? AND coins + ? >= 0',
        allowNegative and { delta, userId } or { delta, userId, delta }
    )

    if not affected or affected == 0 then
        return nil
    end

    local row = MySQL.single.await('SELECT coins FROM user_profiles WHERE user_id = ?', { userId })

    return row and row.coins
end

---@class BanRecord
---@field id integer
---@field reason string
---@field expiresAt integer? unix seconds, nil = permanent
---@field staff string?

---@param license string
---@param tokens string[]
---@return BanRecord?
function Core.db.getActiveBan(license, tokens)
    local conditions = { 'b.license = ?' }
    local params = { license }

    if #tokens > 0 then
        conditions[#conditions + 1] = ('b.token IN (%s)'):format(string.rep('?', #tokens, ','))

        for index = 1, #tokens do
            params[#params + 1] = tokens[index]
        end
    end

    local row = MySQL.single.await(([[
        SELECT b.id, b.reason, UNIX_TIMESTAMP(b.expires_at) AS expires_at, b.staff
        FROM user_bans b
        WHERE (%s) AND (b.expires_at IS NULL OR b.expires_at > NOW())
        LIMIT 1
    ]]):format(table.concat(conditions, ' OR ')), params)

    if not row then
        return nil
    end

    return {
        id = row.id,
        reason = row.reason,
        expiresAt = row.expires_at,
        staff = row.staff,
    }
end

---@param userId integer?
---@param license string
---@param token string?
---@param reason string
---@param expiresAt integer? unix seconds, nil = permanent
---@param staff string?
---@return integer? banId
function Core.db.createBan(userId, license, token, reason, expiresAt, staff)
    return MySQL.insert.await(
        'INSERT INTO user_bans (user_id, license, token, reason, expires_at, staff, created_at) VALUES (?, ?, ?, ?, FROM_UNIXTIME(?), ?, NOW())',
        { userId, license, token, reason, expiresAt, staff }
    )
end

---@param userId integer
---@param identifiers PlayerIdentifiers
---@param tokens string[]
function Core.db.recordIdentity(userId, identifiers, tokens)
    local queries = {}

    for identifierType, value in pairs(identifiers) do
        queries[#queries + 1] = {
            'INSERT INTO user_identifiers (user_id, type, value, last_seen) VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE last_seen = NOW()',
            { userId, identifierType, value },
        }
    end

    for index = 1, #tokens do
        queries[#queries + 1] = {
            'INSERT INTO user_identifiers (user_id, type, value, last_seen) VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE last_seen = NOW()',
            { userId, 'token', tokens[index] },
        }
    end

    if #queries == 0 then
        return
    end

    MySQL.transaction.await(queries)
end

---@param userId integer
---@param report HardwareReport
function Core.db.recordHardware(userId, report)
    MySQL.insert.await(
        'INSERT INTO user_hardware (user_id, fingerprint, payload, first_seen, last_seen) VALUES (?, ?, ?, NOW(), NOW()) ON DUPLICATE KEY UPDATE payload = VALUES(payload), last_seen = NOW()',
        { userId, report.fingerprint, json.encode(report) }
    )
end

---@param userId integer
---@return integer[]
function Core.db.getLinkedUserIds(userId)
    local rows = MySQL.query.await([[
        SELECT DISTINCT other.user_id
        FROM user_identifiers mine
        JOIN user_identifiers other ON other.type = mine.type AND other.value = mine.value
        WHERE mine.user_id = ? AND other.user_id <> ?
    ]], { userId, userId })

    ---@type integer[]
    local linked = {}

    for index = 1, #(rows or {}) do
        linked[index] = rows[index].user_id
    end

    return linked
end

---@return ItemsLookup
function Core.db.getItems()
    local rows = MySQL.query.await('SELECT * FROM items WHERE enabled = 1')

    ---@type ItemsLookup
    local items = {}

    for index = 1, #(rows or {}) do
        local row = rows[index]

        if Core.isItemCategory(row.category) then
            ---@type Item
            local item = {
                id = row.id,
                category = row.category,
                label = row.label,
                description = row.description,
                image = row.image,
                rarity = row.rarity,
                price = row.price,
                purchasable = row.purchasable == 1,
                enabled = true,
                sortOrder = row.sort_order or 0,
                ace = Core.buildItemAce(row.category, row.id),
                data = decode(row.data, {}),
            }

            for key, value in pairs(item.data) do
                if item[key] == nil then
                    item[key] = value
                end
            end

            items[row.id] = item
        end
    end

    return items
end

---@return HandItemsLookup
function Core.db.getHandItems()
    local rows = MySQL.query.await('SELECT * FROM hand_items WHERE enabled = 1')

    ---@type HandItemsLookup
    local handItems = {}

    for index = 1, #(rows or {}) do
        local row = rows[index]

        handItems[row.id] = {
            id = row.id,
            label = row.label,
            model = row.model,
            bone = row.bone,
            offset = row.offset_x and vec3(row.offset_x, row.offset_y, row.offset_z) or nil,
            rotation = row.rotation_x and vec3(row.rotation_x, row.rotation_y, row.rotation_z) or nil,
        }
    end

    return handItems
end


---@class InventoryEntry
---@field id integer
---@field itemId string
---@field equipped boolean
---@field acquiredAt integer

---@param userId integer
---@return InventoryEntry[]
function Core.db.getInventory(userId)
    local rows = MySQL.query.await(
        'SELECT id, item_id, equipped, UNIX_TIMESTAMP(acquired_at) AS acquired_at FROM user_inventory WHERE user_id = ?',
        { userId }
    )

    ---@type InventoryEntry[]
    local entries = {}

    for index = 1, #(rows or {}) do
        local row = rows[index]

        entries[index] = {
            id = row.id,
            itemId = row.item_id,
            equipped = row.equipped == 1,
            acquiredAt = row.acquired_at,
        }
    end

    return entries
end

---@param userId integer
---@param itemId string
---@return integer? entryId
function Core.db.addInventoryItem(userId, itemId)
    return MySQL.insert.await(
        'INSERT INTO user_inventory (user_id, item_id, acquired_at) VALUES (?, ?, NOW())',
        { userId, itemId }
    )
end

---@param entryId integer
---@param userId integer
---@return boolean removed
function Core.db.removeInventoryEntry(entryId, userId)
    local affected = MySQL.update.await('DELETE FROM user_inventory WHERE id = ? AND user_id = ?', { entryId, userId })

    return (affected or 0) > 0
end

---@param itemId string
---@return integer removedCount
function Core.db.removeInventoryItemEverywhere(itemId)
    return MySQL.update.await('DELETE FROM user_inventory WHERE item_id = ?', { itemId }) or 0
end

---@param userId integer
---@param entryId integer
---@param equipped boolean
function Core.db.setInventoryEquipped(userId, entryId, equipped)
    MySQL.update.await('UPDATE user_inventory SET equipped = ? WHERE id = ? AND user_id = ?', { equipped and 1 or 0, entryId, userId })
end

---@param userId integer
---@return table?
function Core.db.getAppearance(userId)
    local row = MySQL.single.await('SELECT appearance FROM user_appearance WHERE user_id = ?', { userId })

    return row and decode(row.appearance, {}) or nil
end

---@param userId integer
---@param appearance table
function Core.db.saveAppearance(userId, appearance)
    MySQL.insert.await(
        'INSERT INTO user_appearance (user_id, appearance, updated_at) VALUES (?, ?, NOW()) ON DUPLICATE KEY UPDATE appearance = VALUES(appearance), updated_at = NOW()',
        { userId, json.encode(appearance) }
    )
end
