---Podium leaderboards.
---
---Rows are cached and refreshed on a timer instead of being read per client:
---a podium is decoration, so a few minutes of staleness costs nothing and a
---full table scan per connecting player would not be free.

local BOARDS = require 'top3.config'

---Columns a board is allowed to sort on. The board key is interpolated into
---the SQL, so it never comes from anywhere but this table.
---@type table<string, true>
local SORTABLE = {
    kills = true,
    deaths = true,
    wins = true,
    losses = true,
}

local REFRESH_INTERVAL = 5 * 60 * 1000

---@param board table
---@return string
local function boardKey(board)
    return ('%s:%s'):format(board.category, board.column)
end

---@type table<string, { userId: integer, username: string, value: integer }[]>
local cache = {}

---@param board table
---@return { userId: integer, username: string, value: integer }[]
local function fetchBoard(board)
    if not SORTABLE[board.column] then
        lib.print.error(('[top3] board "%s" sorts on unknown column "%s"'):format(board.label, board.column))

        return {}
    end

    local rows = MySQL.query.await(([[
        SELECT s.user_id AS userId, u.username AS username, s.%s AS value
        FROM user_game_stats s
        INNER JOIN users u ON u.userId = s.user_id
        WHERE s.category = ? AND s.%s > 0
        ORDER BY s.%s DESC, u.username ASC
        LIMIT 3
    ]]):format(board.column, board.column, board.column), {
        board.category,
    })

    return rows or {}
end

---misc.sql is imported by hand, and until it is there is nothing to read. A
---missing table is a setup step rather than a fault, so it is reported once
---and the podiums simply stay empty -- fourteen failing queries every five
---minutes would bury whatever the owner is actually looking at in the console.
---@return boolean
local function hasStatsTable()
    local exists = MySQL.scalar.await([[
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'user_game_stats'
    ]])

    return exists ~= nil
end

local tableChecked = false
local tableExists = false

local function refresh()
    if not tableChecked then
        tableChecked = true
        tableExists = hasStatsTable()

        if not tableExists then
            lib.print.warn('[top3] `user_game_stats` does not exist -- import misc/misc.sql to populate the podiums.')
        end
    end

    if not tableExists then
        return
    end

    local next = {}

    for index = 1, #BOARDS do
        local board = BOARDS[index]

        next[boardKey(board)] = fetchBoard(board)
    end

    cache = next
end

---@return table<string, { userId: integer, username: string, value: integer }[]>
lib.callback.register('misc:server:getLeaderboards', function()
    return cache
end)

---Lets a gamemode push a podium forward the moment a match ends, rather than
---leaving the winner off it until the next tick.
exports('RefreshLeaderboards', function()
    CreateThread(function()
        refresh()

        TriggerClientEvent('misc:client:leaderboards', -1, cache)
    end)
end)

CreateThread(function()
    while true do
        refresh()

        TriggerClientEvent('misc:client:leaderboards', -1, cache)

        Wait(REFRESH_INTERVAL)
    end
end)
