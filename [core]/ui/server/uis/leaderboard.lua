---Leaderboard callbacks.
---
---The NUI pages through the board with an opaque cursor rather than a page
---number, so a player whose rank shifts mid-scroll does not make a row appear
---twice. The cursor here is just the offset, sent back as a string.
---
---Rows come from `user_game_stats` (misc.sql), joined to `users`,
---`user_profiles` and `user_levels`. Gang columns are stubbed because core's
---gang callbacks still are.

local PAGE_SIZE = 25

---Columns a board may sort on. The category is interpolated into the ORDER BY,
---so it never comes from anywhere but this table.
---@type table<string, string>
local SORTABLE = {
    kills = 'kills',
    deaths = 'deaths',
    wins = 'wins',
    losses = 'losses',
    playtime = 'playtime',
    level = 'level',
}

---Gamemodes whose board is a rating ladder: the page shows an "Avg Elo"
---column for these and sorts on it. Rows carry the player's best rating
---across the ranked queues (ranked_elo), which is what a hopouts rank is.
---@type table<string, true>
local ELO_BOARDS = { hopouts = true, tdm = true, facechecks = true, wars = true }

local DEFAULT_ELO = 1000

---@param data table?
---@return string category the page's selected gamemode
local function categoryOf(data)
    local category = type(data) == 'table' and data.category or nil

    return type(category) == 'string' and category or 'all_modes'
end

---@param data table?
---@return string column
local function sortColumn(data)
    local category = categoryOf(data)

    if ELO_BOARDS[category] and Schema.has('ranked_elo') then
        return 'elo'
    end

    -- The FFA boards rank on wins; "all modes" on kills.
    if category ~= 'all_modes' and not SORTABLE[category] then
        return 'wins'
    end

    return SORTABLE[category] or 'kills'
end

---@param data table?
---@return integer
local function cursorOffset(data)
    local cursor = type(data) == 'table' and tonumber(data.cursor) or nil

    return math.max(0, math.floor(cursor or 0))
end

---@param data table
---@return { nextCursor: string?, players: table[] }
lib.callback.register('uis:server:getLeaderboardPlayers', function(_, data)
    -- Without the stats table this query throws, the client gets nil, and the
    -- page falls back to its demo rows. An empty board is the honest answer.
    if not Schema.has('user_game_stats') then
        return { nextCursor = nil, players = {} }
    end

    local category = categoryOf(data)
    local column = sortColumn(data)
    local offset = cursorOffset(data)
    local hasElo = Schema.has('ranked_elo')

    -- playtime, level and elo live on other tables than the stats, so the
    -- sort column decides which expression the ORDER BY uses.
    local orderBy = ('SUM(s.%s)'):format(column)

    if column == 'playtime' then
        orderBy = 'p.playtime'
    elseif column == 'level' then
        orderBy = 'l.prestige DESC, l.level'
    elseif column == 'elo' then
        orderBy = ('COALESCE(e.elo, %d)'):format(DEFAULT_ELO)
    end

    local eloJoin = hasElo
        and 'LEFT JOIN (SELECT user_id, MAX(elo) AS elo FROM ranked_elo GROUP BY user_id) e ON e.user_id = u.userId'
        or 'LEFT JOIN (SELECT NULL AS user_id, NULL AS elo) e ON FALSE'

    -- A gamemode board counts only that gamemode's stats; "all modes" all.
    local rows = MySQL.query.await(([[
        SELECT u.userId AS id,
               u.username AS username,
               p.avatar AS avatar,
               COALESCE(p.playtime, 0) AS playtime,
               COALESCE(l.level, 1) AS level,
               COALESCE(l.prestige, 0) AS prestige,
               COALESCE(e.elo, %d) AS elo,
               COALESCE(SUM(s.kills), 0) AS kills,
               COALESCE(SUM(s.deaths), 0) AS deaths,
               COALESCE(SUM(s.wins), 0) AS wins,
               COALESCE(SUM(s.losses), 0) AS losses
        FROM users u
        LEFT JOIN user_profiles p ON p.user_id = u.userId
        LEFT JOIN user_levels l ON l.user_id = u.userId
        LEFT JOIN user_game_stats s ON s.user_id = u.userId AND (? = 'all_modes' OR s.category = ?)
        %s
        GROUP BY u.userId, u.username, p.avatar, p.playtime, l.level, l.prestige, e.elo
        ORDER BY %s DESC, u.username ASC
        LIMIT ? OFFSET ?
    ]]):format(DEFAULT_ELO, eloJoin, orderBy), { category, category, PAGE_SIZE + 1, offset }) or {}

    -- One row over the page size is fetched purely to find out whether there
    -- is a next page, then dropped.
    local hasMore = #rows > PAGE_SIZE

    if hasMore then
        rows[#rows] = nil
    end

    local players = {}

    for index = 1, #rows do
        local row = rows[index]
        local elo = tonumber(row.elo) or DEFAULT_ELO

        players[index] = {
            id = row.id,
            username = row.username,
            avatar = row.avatar or '',
            -- SUM() arrives as a DECIMAL string from the driver. Passing it
            -- straight through shipped strings to the UI, which then sorts and
            -- does K/D arithmetic on them.
            kills = tonumber(row.kills) or 0,
            deaths = tonumber(row.deaths) or 0,
            wins = tonumber(row.wins) or 0,
            losses = tonumber(row.losses) or 0,
            elo = elo,
            avgElo = elo,
            -- The board's own place, so the page ranks rows the way the
            -- query did rather than re-deriving it.
            leaderboardPlace = offset + index,
            -- Nothing records headshots per player yet; the column renders
            -- as 0 rather than blank.
            headshots = 0,
            playtime = tonumber(row.playtime) or 0,
            level = tonumber(row.level) or 1,
            prestige = tonumber(row.prestige) or 0,
            -- Core's gang system is still stubs, so there is no gang to name.
            gang = nil,
        }
    end

    return {
        nextCursor = hasMore and tostring(offset + PAGE_SIZE) or nil,
        players = players,
    }
end)

---Gangs do not exist yet -- core/base/server/events/gangs.lua is a set of
---stubs returning empty shapes. This matches them, so the page renders its
---"no crews" state instead of raising.
---@return { nextCursor: string?, gangs: table[] }
lib.callback.register('uis:server:getLeaderboardGangs', function()
    return {
        nextCursor = nil,
        gangs = {},
    }
end)
