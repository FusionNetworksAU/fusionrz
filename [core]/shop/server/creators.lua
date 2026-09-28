---Creator codes.
---
---A code does two things: it is stored on the buyer so it rides along with
---every purchase, and it is what the creator's dashboard aggregates over.
---Both read the same `shop_purchases` rows -- there is no separate earnings
---ledger to drift out of step with what was actually bought.

---@param code string?
---@return string?
function Shop.normaliseCreatorCode(code)
    if type(code) ~= 'string' then
        return nil
    end

    local trimmed = code:gsub('^%s+', ''):gsub('%s+$', '')

    if #trimmed < Shop.tuning.creators.codeMinLength or #trimmed > Shop.tuning.creators.codeMaxLength then
        return nil
    end

    return trimmed
end

---@param code string
---@return table?
local function fetchCode(code)
    return MySQL.single.await(
        'SELECT code, user_id AS userId, share FROM shop_creator_codes WHERE code = ? AND enabled = 1',
        { code }
    )
end

---@alias CreatorTimespan '7d' | '30d' | '90d' | 'all'

---@param timespan CreatorTimespan?
---@return integer days 0 means all time
local function timespanDays(timespan)
    return Shop.tuning.creators.timespans[timespan] or 0
end

---A WHERE fragment plus its bindings. Built here rather than inline so every
---dashboard query filters on exactly the same definition of "earnings": not
---refunded, and carrying this code. `prefix` is the table alias the query
---uses, so the joined variant below can say `p.` without rewriting the
---clause afterwards.
---@param code string
---@param timespan CreatorTimespan?
---@param prefix string?
---@return string clause
---@return table bindings
local function earningsFilter(code, timespan, prefix)
    local column = prefix and (prefix .. '.') or ''
    local days = timespanDays(timespan)

    local clause = ('%screator_code = ? AND %srefunded_at IS NULL'):format(column, column)

    if days <= 0 then
        return clause, { code }
    end

    return ('%s AND %screated_at >= DATE_SUB(NOW(), INTERVAL ? DAY)'):format(clause, column), { code, days }
end

---@param code string
---@return boolean valid
---@return string? error
lib.callback.register('shop:server:validateCreatorCode', function(source, code)
    local normalised = Shop.normaliseCreatorCode(code)

    if not normalised then
        return false, 'That code is not valid.'
    end

    local row = fetchCode(normalised)

    if not row then
        return false, 'No creator uses that code.'
    end

    if row.userId == Shop.getUserId(source) then
        return false, 'You cannot support yourself.'
    end

    return true
end)

---The client saves the code locally for instant feedback; this is what makes
---it stick, and it is re-validated here because the client's copy is a
---suggestion.
---@param code string?
RegisterNetEvent('shop:server:setCreatorCode', function(code)
    local source = source --[[@as Source]]

    if not Shop.getUserId(source) then
        return
    end

    local normalised = Shop.normaliseCreatorCode(code)

    if not normalised then
        Shop.set(source, Shop.keys.creatorCode, nil)

        return
    end

    local row = fetchCode(normalised)

    if not row or row.userId == Shop.getUserId(source) then
        return
    end

    Shop.set(source, Shop.keys.creatorCode, row.code)
end)

-- -------------------------------------------------------------- dashboard --

---What the creator sees about their own code, or nil if they do not have one.
---@param source Source
function Shop.pushCreatorSelfInfo(source)
    local userId = Shop.getUserId(source)

    if not userId then
        return
    end

    local row = MySQL.single.await(
        'SELECT code, share FROM shop_creator_codes WHERE user_id = ? AND enabled = 1',
        { userId }
    )

    if not row then
        return TriggerClientEvent('shop:setCreatorSelfInfo', source, nil)
    end

    local clause, bindings = earningsFilter(row.code, 'all')

    local totals = MySQL.single.await(([[
        SELECT COUNT(*) AS purchases, COALESCE(SUM(price), 0) AS gross
        FROM shop_purchases WHERE %s
    ]]):format(clause), bindings)

    TriggerClientEvent('shop:setCreatorSelfInfo', source, {
        code = row.code,
        share = row.share,
        totalPurchases = totals and totals.purchases or 0,
        totalEarnings = math.floor((totals and totals.gross or 0) * row.share),
    })
end

RegisterNetEvent('shop:server:refreshCreatorSelfInfo', function()
    Shop.pushCreatorSelfInfo(source --[[@as Source]])
end)

---@param source Source
---@return string?
local function getOwnCode(source)
    local userId = Shop.getUserId(source)

    if not userId then
        return nil
    end

    return MySQL.scalar.await(
        'SELECT code FROM shop_creator_codes WHERE user_id = ? AND enabled = 1',
        { userId }
    )
end

---@param timespan CreatorTimespan
---@return table?
lib.callback.register('shop:server:getCreatorTimespanStats', function(source, timespan)
    local code = getOwnCode(source)

    if not code then
        return nil
    end

    local clause, bindings = earningsFilter(code, timespan)

    local row = MySQL.single.await(([[
        SELECT COUNT(*) AS purchases,
               COUNT(DISTINCT user_id) AS supporters,
               COALESCE(SUM(price), 0) AS gross
        FROM shop_purchases WHERE %s
    ]]):format(clause), bindings)

    local share = MySQL.scalar.await('SELECT share FROM shop_creator_codes WHERE code = ?', { code }) or Shop.tuning.creators.defaultShare

    return {
        purchases = row and row.purchases or 0,
        supporters = row and row.supporters or 0,
        earnings = math.floor((row and row.gross or 0) * share),
    }
end)

---One point per day, oldest first, for the dashboard's graph. All-time falls
---back to ninety days here -- a graph needs a bounded x axis, and a creator
---with two years of history does not want two years of points.
---@param timespan CreatorTimespan
---@return table[]?
lib.callback.register('shop:server:getCreatorTimespanEarnings', function(source, timespan)
    local code = getOwnCode(source)

    if not code then
        return nil
    end

    local days = timespanDays(timespan)

    if days <= 0 then
        days = 90
    end

    local share = MySQL.scalar.await('SELECT share FROM shop_creator_codes WHERE code = ?', { code }) or Shop.tuning.creators.defaultShare

    local rows = MySQL.query.await([[
        SELECT DATE(created_at) AS day, COALESCE(SUM(price), 0) AS gross
        FROM shop_purchases
        WHERE creator_code = ? AND refunded_at IS NULL
          AND created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
        GROUP BY DATE(created_at)
        ORDER BY day ASC
    ]], { code, days }) or {}

    local points = {}

    for index = 1, #rows do
        points[index] = {
            date = tostring(rows[index].day),
            earnings = math.floor(rows[index].gross * share),
        }
    end

    return points
end)

---@param page integer
---@param timespan CreatorTimespan
---@return table?
lib.callback.register('shop:server:getCreatorTopSpenders', function(source, page, timespan)
    local code = getOwnCode(source)

    if not code then
        return nil
    end

    local pageSize = Shop.tuning.creators.topSpendersPageSize
    local pageIndex = math.max(1, math.floor(tonumber(page) or 1))
    local offset = (pageIndex - 1) * pageSize

    local clause, bindings = earningsFilter(code, timespan)

    local total = MySQL.scalar.await(([[
        SELECT COUNT(DISTINCT user_id) FROM shop_purchases WHERE %s
    ]]):format(clause), bindings) or 0

    local joinedClause, joinedBindings = earningsFilter(code, timespan, 'p')

    joinedBindings[#joinedBindings + 1] = pageSize
    joinedBindings[#joinedBindings + 1] = offset

    local rows = MySQL.query.await(([[
        SELECT p.user_id AS userId, u.username AS username,
               COUNT(*) AS purchases, COALESCE(SUM(p.price), 0) AS spent
        FROM shop_purchases p
        LEFT JOIN users u ON u.userId = p.user_id
        WHERE %s
        GROUP BY p.user_id, u.username
        ORDER BY spent DESC
        LIMIT ? OFFSET ?
    ]]):format(joinedClause), joinedBindings) or {}

    return {
        page = pageIndex,
        pageCount = math.max(1, math.ceil(total / pageSize)),
        total = total,
        entries = rows,
    }
end)
