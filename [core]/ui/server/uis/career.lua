---Career page callbacks.
---
---ui/client/uis/career.lua has always called these and nothing registered
---them, so every one raised "callback does not exist" the moment the page was
---opened. Like the rest of server/uis, nothing here stores data of its own:
---it reads the tables that already exist.
---
---Where that data comes from, and what is honestly missing:
---  ranked_elo             rating, wins, losses, games      (ranked.sql)
---  ranked_elo_adjustments per-match history                (ranked.sql)
---  user_game_stats        kills/deaths per gamemode        (misc.sql)
---  user_levels            level and prestige               (levels.sql)
---  user_profiles          playtime and avatar              (core.sql)
---Nothing records per-match kills, maps or scoreboards yet, so match details
---return what the adjustment row knows and no more.

local core = exports.core

---Rank tiers, lowest first. These mirror ranked/server/display.lua -- ui
---cannot require a server file out of another resource, so the ladder is
---restated. Keep the two in step if the tiers ever change.
local RANK_TIERS = {
    { name = 'Bronze', minElo = 0 },
    { name = 'Silver', minElo = 900 },
    { name = 'Gold', minElo = 1100 },
    { name = 'Platinum', minElo = 1300 },
    { name = 'Diamond', minElo = 1500 },
    { name = 'Feared', minElo = 1750 },
    { name = 'God', minElo = 2000 },
}

local DEFAULT_ELO = 1000

---@param source number
---@param payload table?
---@return integer? userId the page's subject, which may be someone else
local function subjectUserId(source, payload)
    if type(payload) == 'table' and tonumber(payload.userId) then
        return math.floor(tonumber(payload.userId))
    end

    local data = core:GetPlayerData(source)

    return data and data.userId or nil
end

---@param payload table?
---@return string
local function gamemodeOf(payload)
    if type(payload) == 'table' and type(payload.gamemode) == 'string' then
        return payload.gamemode
    end

    return 'solo'
end

---@param elo integer
---@return integer index
local function tierIndexFor(elo)
    local index = 1

    for position = 1, #RANK_TIERS do
        if elo >= RANK_TIERS[position].minElo then
            index = position
        end
    end

    return index
end

---The NUI renders `name` as the badge and `label` as the text beside it. With
---no divisions in the ladder the two are the same string.
---@param index integer?
---@return table?
local function tierAt(index)
    local tier = index and RANK_TIERS[index] or nil

    if not tier then
        return nil
    end

    return { name = tier.name, label = tier.name, minElo = tier.minElo }
end

---The stat block every panel expects, with nothing in it. Returned wherever
---the table behind the numbers has not been imported, so the page renders
---zeroes instead of the callback failing and taking the page with it.
---@return table
local function emptyStats()
    return {
        kills = 0,
        deaths = 0,
        wins = 0,
        losses = 0,
        matches = 0,
        kdr = 0,
        winRate = 0,
    }
end

---The ranked queues. Ratings are stored per queue (ranked/server/queue.lua),
---but the career page asks for a gamemode -- "hopouts" -- which no rating row
---is ever filed under, so it always fell back to 1000 whatever was played.
---@type table<string, true>
local RANKED_MODES = { solo = true, duo = true, trio = true, squad = true }

---@param mode string
---@return boolean
local function isRankedMode(mode)
    return RANKED_MODES[mode] == true
end

---A player's rating for a page. A queue name reads that queue; "hopouts" (the
---career/leaderboard gamemode) is their best rating across every queue, with
---wins, losses and games summed, which is what "your hopouts rank" means.
---@param userId integer
---@param mode string
---@return table?
local function fetchElo(userId, mode)
    if not Schema.has('ranked_elo') then
        return nil
    end

    if isRankedMode(mode) then
        return MySQL.single.await([[
            SELECT elo, wins, losses, games FROM ranked_elo WHERE user_id = ? AND mode = ?
        ]], { userId, mode })
    end

    local row = MySQL.single.await([[
        SELECT MAX(elo) AS elo, SUM(wins) AS wins, SUM(losses) AS losses, SUM(games) AS games
        FROM ranked_elo WHERE user_id = ?
    ]], { userId })

    if not row or row.elo == nil then
        return nil
    end

    return {
        elo = tonumber(row.elo),
        wins = tonumber(row.wins) or 0,
        losses = tonumber(row.losses) or 0,
        games = tonumber(row.games) or 0,
    }
end

---How many players are rated above `rating` on the same basis fetchElo used.
---@param mode string
---@param rating integer
---@return integer
local function countAbove(mode, rating)
    if not Schema.has('ranked_elo') then
        return 0
    end

    if isRankedMode(mode) then
        return tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM ranked_elo WHERE mode = ? AND elo > ?', { mode, rating }
        )) or 0
    end

    return tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM (
            SELECT user_id FROM ranked_elo GROUP BY user_id HAVING MAX(elo) > ?
        ) above
    ]], { rating })) or 0
end

---@param mode string
---@return string where, any[] params  the adjustment-log filter for `mode`
local function adjustmentFilter(mode)
    if isRankedMode(mode) then
        return 'mode = ?', { mode }
    end

    return '1 = 1', {}
end

---Stats rows are filed under the gamemode (hopouts writes 'hopouts'), not the
---queue, so a queue name reads its gamemode's row.
---@param mode string
---@return string
local function statsCategory(mode)
    return isRankedMode(mode) and 'hopouts' or mode
end

---Career totals across every gamemode, from the podium stats table.
---@param userId integer
---@return table
local function fetchLifetime(userId)
    if not Schema.has('user_game_stats') then
        return emptyStats()
    end

    local row = MySQL.single.await([[
        SELECT COALESCE(SUM(kills), 0) AS kills,
               COALESCE(SUM(deaths), 0) AS deaths,
               COALESCE(SUM(wins), 0) AS wins,
               COALESCE(SUM(losses), 0) AS losses
        FROM user_game_stats WHERE user_id = ?
    ]], { userId })

    -- SUM() comes back as DECIMAL, which the MySQL driver hands over as a
    -- string to keep precision. Arithmetic coerces it silently, so `matches`
    -- looked fine, but the `deaths > 0` comparison below raised
    -- "attempt to compare number with string".
    local kills = tonumber(row and row.kills) or 0
    local deaths = tonumber(row and row.deaths) or 0
    local wins = tonumber(row and row.wins) or 0
    local losses = tonumber(row and row.losses) or 0
    local matches = wins + losses

    return {
        kills = kills,
        deaths = deaths,
        wins = wins,
        losses = losses,
        matches = matches,
        kdr = deaths > 0 and math.floor((kills / deaths) * 100 + 0.5) / 100 or kills,
        winRate = matches > 0 and math.floor((wins / matches) * 100 + 0.5) or 0,
    }
end

---@param userId integer
---@param mode string
---@return table
local function fetchSeasonStats(userId, mode)
    local elo = fetchElo(userId, mode)
    local stats = Schema.has('user_game_stats') and MySQL.single.await([[
        SELECT COALESCE(SUM(kills), 0) AS kills, COALESCE(SUM(deaths), 0) AS deaths
        FROM user_game_stats WHERE user_id = ? AND category = ?
    ]], { userId, statsCategory(mode) }) or nil

    -- Same DECIMAL-as-string coercion as fetchLifetimeStats above.
    local wins = tonumber(elo and elo.wins) or 0
    local losses = tonumber(elo and elo.losses) or 0
    local matches = wins + losses
    local kills = tonumber(stats and stats.kills) or 0
    local deaths = tonumber(stats and stats.deaths) or 0

    return {
        kills = kills,
        deaths = deaths,
        wins = wins,
        losses = losses,
        matches = matches,
        kdr = deaths > 0 and math.floor((kills / deaths) * 100 + 0.5) / 100 or kills,
        winRate = matches > 0 and math.floor((wins / matches) * 100 + 0.5) or 0,
    }
end

---Longest run of wins in the adjustment log. The log is the only per-match
---record there is, so it is also the only place a streak can come from.
---@param userId integer
---@param mode string
---@return integer
local function fetchHighestWinStreak(userId, mode)
    if not Schema.has('ranked_elo_adjustments') then
        return 0
    end

    local where, params = adjustmentFilter(mode)

    local rows = MySQL.query.await(([[
        SELECT won FROM ranked_elo_adjustments
        WHERE user_id = ? AND %s
        ORDER BY created_at ASC, id ASC
    ]]):format(where), { userId, table.unpack(params) }) or {}

    local best, current = 0, 0

    for index = 1, #rows do
        if rows[index].won == 1 then
            current += 1
            best = math.max(best, current)
        else
            current = 0
        end
    end

    return best
end

---The top of the ladder for `mode`, as the standings panel lists it.
---@param mode string
---@return table[]
local function fetchStandings(mode)
    if not Schema.has('ranked_elo') then
        return {}
    end

    local ratingSql = isRankedMode(mode)
        and 'SELECT user_id, elo FROM ranked_elo WHERE mode = ?'
        or 'SELECT user_id, MAX(elo) AS elo FROM ranked_elo GROUP BY user_id'

    local rows = MySQL.query.await(([[
        SELECT r.user_id AS id, u.username AS username, p.avatar AS avatar, r.elo AS elo,
               COALESCE(l.level, 1) AS level, COALESCE(l.prestige, 0) AS prestige
        FROM (%s) r
        INNER JOIN users u ON u.userId = r.user_id
        LEFT JOIN user_profiles p ON p.user_id = r.user_id
        LEFT JOIN user_levels l ON l.user_id = r.user_id
        ORDER BY r.elo DESC, u.username ASC
        LIMIT 10
    ]]):format(ratingSql), isRankedMode(mode) and { mode } or {}) or {}

    for index = 1, #rows do
        local row = rows[index]

        row.elo = tonumber(row.elo) or DEFAULT_ELO
        row.level = tonumber(row.level) or 1
        row.prestige = tonumber(row.prestige) or 0
        row.avatar = row.avatar or ''
    end

    return rows
end

---Mirrors levels/config/shared.lua (4000 + 400 per level, 100 levels, 6
---prestiges); ui cannot require another resource's config at runtime.
---@param userId integer
---@return table
local function fetchCareerLevel(userId)
    local row = Schema.has('user_levels') and MySQL.single.await(
        'SELECT level, xp, prestige FROM user_levels WHERE user_id = ?', { userId }
    ) or nil

    local level = tonumber(row and row.level) or 1

    return {
        level = level,
        xp = tonumber(row and row.xp) or 0,
        prestige = tonumber(row and row.prestige) or 0,
        xpForNext = 4000 + 400 * level,
        maxLevel = 100,
        maxPrestige = 6,
    }
end

-- -------------------------------------------------------- rank overview ----

---@param payload { gamemode: string, userId: number? }
---@return table?
lib.callback.register('career:server:getRankOverview', function(source, payload)
    local userId = subjectUserId(source, payload)

    if not userId then
        return nil
    end

    local mode = gamemodeOf(payload)
    local elo = fetchElo(userId, mode)
    local rating = elo and elo.elo or DEFAULT_ELO
    local index = tierIndexFor(rating)

    -- Position is a live count of everyone rated above them, not a stored
    -- rank, so it cannot go stale.
    local above = countAbove(mode, rating)

    local where, params = adjustmentFilter(mode)
    local peak = Schema.has('ranked_elo_adjustments') and tonumber(MySQL.scalar.await(([[
        SELECT MAX(elo_after) FROM ranked_elo_adjustments WHERE user_id = ? AND %s
    ]]):format(where), { userId, table.unpack(params) })) or nil

    -- The peak can never be below where they stand now.
    peak = math.max(peak or rating, rating)

    local playtime = tonumber(MySQL.scalar.await(
        'SELECT playtime FROM user_profiles WHERE user_id = ?', { userId }
    )) or 0

    local rated = Schema.has('ranked_elo') and tonumber(MySQL.scalar.await(
        'SELECT COUNT(DISTINCT user_id) FROM ranked_elo'
    )) or 0

    return {
        season = 1,
        elo = rating,
        position = above + 1,
        -- Real standings: the players around this one, not the page's demo
        -- list of "Player 1..10".
        standings = {
            position = above + 1,
            total = math.max(rated, above + 1),
            players = fetchStandings(mode),
        },
        rank = tierAt(index),
        prev = tierAt(index - 1),
        next = tierAt(index + 1),
        peak = tierAt(tierIndexFor(peak)),
        highestWinStreak = fetchHighestWinStreak(userId, mode),
        playtime = playtime,
        stats = fetchSeasonStats(userId, mode),
        lifetime = fetchLifetime(userId),
        career = fetchCareerLevel(userId),
    }
end)

-- -------------------------------------------------------- match history ----

---Built from the rating log, which is the only per-match record that exists.
---It knows the mode, the result and the rating swing; it does not know the
---map or the scoreboard, because nothing writes those yet.
---@param payload { userId: number? }
---@return table[]
lib.callback.register('career:server:getMatchHistoryData', function(source, payload)
    local userId = subjectUserId(source, payload)

    if not userId or not Schema.has('ranked_elo_adjustments') then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT id, mode, delta, elo_before AS eloBefore, elo_after AS eloAfter,
               won, UNIX_TIMESTAMP(created_at) AS playedAt
        FROM ranked_elo_adjustments
        WHERE user_id = ?
        ORDER BY created_at DESC
        LIMIT 50
    ]], { userId }) or {}

    local history = {}

    for index = 1, #rows do
        local row = rows[index]

        history[index] = {
            matchId = row.id,
            gamemode = row.mode,
            won = row.won == 1,
            eloDelta = row.delta,
            eloBefore = row.eloBefore,
            eloAfter = row.eloAfter,
            playedAt = row.playedAt,
        }
    end

    return history
end)

---@param payload { matchId: number, userId: number? }
---@return table?
lib.callback.register('career:server:getMatchDetails', function(source, payload)
    if type(payload) ~= 'table' or not tonumber(payload.matchId) then
        return nil
    end

    local userId = subjectUserId(source, payload)

    if not userId or not Schema.has('ranked_elo_adjustments') then
        return nil
    end

    local row = MySQL.single.await([[
        SELECT id, mode, delta, elo_before AS eloBefore, elo_after AS eloAfter,
               won, UNIX_TIMESTAMP(created_at) AS playedAt
        FROM ranked_elo_adjustments
        WHERE id = ? AND user_id = ?
    ]], { math.floor(tonumber(payload.matchId)), userId })

    if not row then
        return nil
    end

    return {
        matchId = row.id,
        gamemode = row.mode,
        won = row.won == 1,
        eloDelta = row.delta,
        eloBefore = row.eloBefore,
        eloAfter = row.eloAfter,
        playedAt = row.playedAt,
        -- Empty rather than absent: the details panel iterates this, so it
        -- needs a list even when no scoreboard was recorded.
        players = {},
    }
end)

-- --------------------------------------------------------------- stats -----

---@param payload { gamemode: string, userId: number? }
---@return table?
lib.callback.register('career:server:getStats', function(source, payload)
    local userId = subjectUserId(source, payload)

    if not userId then
        return nil
    end

    local mode = gamemodeOf(payload)

    return {
        gamemode = mode,
        season = fetchSeasonStats(userId, mode),
        lifetime = fetchLifetime(userId),
    }
end)

---A point per match for the career graph. `range` caps how far back it goes;
---`metric` picks which number each point carries.
---@param payload { metric: string, range: string }
---@return table[]
lib.callback.register('career:server:getStatSeries', function(source, payload)
    local userId = subjectUserId(source, payload)

    if not userId then
        return {}
    end

    local metric = type(payload) == 'table' and payload.metric or 'elo'
    local limit = 100

    if type(payload) == 'table' and payload.range == '7d' then
        limit = 25
    elseif type(payload) == 'table' and payload.range == '30d' then
        limit = 50
    end

    if not Schema.has('ranked_elo_adjustments') then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT elo_after AS elo, delta, won, UNIX_TIMESTAMP(created_at) AS at
        FROM ranked_elo_adjustments
        WHERE user_id = ?
        ORDER BY created_at DESC
        LIMIT ?
    ]], { userId, limit }) or {}

    local series = {}

    -- Reversed, because the query takes the most recent but a graph reads
    -- oldest to newest.
    for index = #rows, 1, -1 do
        local row = rows[index]
        local value = row.elo

        if metric == 'delta' then
            value = row.delta
        elseif metric == 'wins' then
            value = row.won
        end

        series[#series + 1] = { at = row.at, value = value }
    end

    return series
end)

-- --------------------------------------------------------------- ranks -----

---An event rather than a callback: the client fires it and waits for
---career:client:setRanks to come back.
---@param modeType string
RegisterNetEvent('career:server:fetchRanks', function(modeType)
    local source = source --[[@as number]]
    local mode = type(modeType) == 'string' and modeType or 'hopouts'

    -- Live player counts per tier: every account, placed by its best rating
    -- across the ranked modes; an account with no ranked game yet sits at
    -- the starting rating, which is where the game would put it.
    local counts = {}

    for index = 1, #RANK_TIERS do
        counts[index] = 0
    end

    local rows = Schema.has('ranked_elo') and MySQL.query.await([[
        SELECT COALESCE(MAX(e.elo), ?) AS elo
        FROM users u
        LEFT JOIN ranked_elo e ON e.user_id = u.userId
        GROUP BY u.userId
    ]], { DEFAULT_ELO }) or {}

    for _, row in ipairs(rows) do
        local tier = 1

        for index = 1, #RANK_TIERS do
            if (tonumber(row.elo) or DEFAULT_ELO) >= RANK_TIERS[index].minElo then
                tier = index
            end
        end

        counts[tier] += 1
    end

    -- The panel reads each tier as { rank, name, numPlayers, minElo, maxElo }:
    -- `rank` is the lowercase id its art and colours are keyed on, and it
    -- calls numPlayers.toLocaleString() -- which is what crashed the whole
    -- UI when this sent { name, label, minElo } and nothing else.
    local ranks = {}

    for index = 1, #RANK_TIERS do
        local tier = RANK_TIERS[index]
        local nextTier = RANK_TIERS[index + 1]

        ranks[index] = {
            rank = tier.name:lower(),
            name = tier.name,
            label = tier.name,
            numPlayers = counts[index],
            minElo = tier.minElo,
            maxElo = nextTier and (nextTier.minElo - 1) or nil,
        }
    end

    TriggerClientEvent('career:client:setRanks', source, { gamemode = mode, ranks = ranks })
end)

---@param payload { userId: number? }
---@return table?
lib.callback.register('career:server:getData', function(source, payload)
    local userId = subjectUserId(source, payload)

    if not userId then
        return nil
    end

    local profile = MySQL.single.await([[
        SELECT u.username AS username, p.avatar AS avatar, p.country AS country,
               p.playtime AS playtime, p.metadata AS metadata
        FROM users u
        LEFT JOIN user_profiles p ON p.user_id = u.userId
        WHERE u.userId = ?
    ]], { userId })

    if not profile then
        return nil
    end

    local level = Schema.has('user_levels') and MySQL.single.await(
        'SELECT level, prestige FROM user_levels WHERE user_id = ?', { userId }
    ) or nil

    local metadata = profile.metadata and json.decode(profile.metadata) or {}

    return {
        userId = userId,
        username = profile.username,
        avatar = profile.avatar,
        country = profile.country,
        playtime = profile.playtime or 0,
        level = level and level.level or 1,
        prestige = level and level.prestige or 0,
        bio = metadata.personal_bio or '',
        lifetime = fetchLifetime(userId),
    }
end)
