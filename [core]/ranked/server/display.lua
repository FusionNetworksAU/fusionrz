Ranked = Ranked or {}

local core = exports.core

local RANK_TIERS = {
    { name = 'bronze', elo = 0 },
    { name = 'silver', elo = 900 },
    { name = 'gold', elo = 1100 },
    { name = 'platinum', elo = 1300 },
    { name = 'diamond', elo = 1500 },
    { name = 'feared', elo = 1750 },
    { name = 'god', elo = 2000 },
}

-- The FNRZ card, shipped with the UI at ui/web/build/cdn/ccs/.
local DEFAULT_BANNER = 'ccs/fnrz_default.webp'

---@param userId integer
---@param mode string
---@return string
function Ranked.getRankName(userId, mode)
    local elo = Ranked.getElo(userId, mode)
    local name = RANK_TIERS[1].name

    for index = 1, #RANK_TIERS do
        if elo >= RANK_TIERS[index].elo then
            name = RANK_TIERS[index].name
        end
    end

    return name
end

---@param elo integer
---@return integer
function Ranked.getNextTierElo(elo)
    for index = 1, #RANK_TIERS do
        if elo < RANK_TIERS[index].elo then
            return RANK_TIERS[index].elo
        end
    end

    return RANK_TIERS[#RANK_TIERS].elo
end

---The threshold of the tier `elo` is in, so the mode card's bar can show
---progress through that tier rather than elo / next-threshold (which put a
---fresh 1000 at 91% full while it sat halfway through silver).
---@param elo integer
---@return integer
function Ranked.getTierFloorElo(elo)
    local floor = RANK_TIERS[1].elo

    for index = 1, #RANK_TIERS do
        if elo >= RANK_TIERS[index].elo then
            floor = RANK_TIERS[index].elo
        end
    end

    -- At the top tier there is no next threshold to fill towards; the card
    -- shows a full bar rather than an empty one.
    if floor == RANK_TIERS[#RANK_TIERS].elo then
        return floor - 1
    end

    return floor
end

---Where an elo sits in the tiers: its tier, the one above it, and how far
---through the gap it is. What the match-ended screen draws its bar from.
---@param elo integer
---@return { rank: string, label: string, nextRank: string, nextRankLabel: string, intoTier: integer, tierSize: integer, isTop: boolean }
function Ranked.getRankProgress(elo)
    local index = 1

    for i = 1, #RANK_TIERS do
        if elo >= RANK_TIERS[i].elo then
            index = i
        end
    end

    local tier = RANK_TIERS[index]
    local nextTier = RANK_TIERS[index + 1]
    local isTop = nextTier == nil

    ---@param name string
    local function label(name)
        return name:sub(1, 1):upper() .. name:sub(2)
    end

    return {
        rank = tier.name,
        label = label(tier.name),
        nextRank = (nextTier or tier).name,
        nextRankLabel = label((nextTier or tier).name),
        intoTier = elo - tier.elo,
        -- The top tier has no ceiling; give the bar a nominal one to fill.
        tierSize = isTop and 250 or (nextTier.elo - tier.elo),
        isTop = isTop,
    }
end

---@param userId integer
---@return integer
function Ranked.getPing(userId)
    local playerSource = Ranked.getSource(userId)

    return playerSource and GetPlayerPing(playerSource --[[@as string]]) or 0
end

---@param userId integer
---@return integer
function Ranked.getLevel(userId)
    local playerSource = Ranked.getSource(userId)

    if not playerSource or GetResourceState('levels') ~= 'started' then
        return 1
    end

    local record = exports.levels:GetLevel(playerSource)

    return record and record.level or 1
end

---@param userId integer
---@return integer?
function Ranked.getPrestige(userId)
    local playerSource = Ranked.getSource(userId)

    if not playerSource or GetResourceState('levels') ~= 'started' then
        return nil
    end

    local record = exports.levels:GetLevel(playerSource)

    if not record or not record.prestige or record.prestige < 1 then
        return nil
    end

    return record.prestige
end

---@param userId integer
---@return string
function Ranked.getBanner(userId)
    local playerSource = Ranked.getSource(userId)

    if not playerSource then
        return DEFAULT_BANNER
    end

    local itemId = core:GetMetadata(playerSource, 'equipped_background')

    if not itemId then
        return DEFAULT_BANNER
    end

    local item = core:GetItem(itemId)

    return item and item.image or DEFAULT_BANNER
end

---@param userId integer
---@return string?
function Ranked.getGangTag(userId)
    local playerSource = Ranked.getSource(userId)

    if not playerSource then
        return nil
    end

    -- core's gang callbacks are still stubs, so the tag comes from the
    -- player's own metadata until a gang system lands.
    local tag = core:GetMetadata(playerSource, 'gang_tag')

    return type(tag) == 'string' and #tag > 0 and tag or nil
end

---Consecutive wins in this mode. Read off the adjustment log rather than
---stored separately, so it can never disagree with the rating history.
---@param userId integer
---@param mode string
---@return integer
function Ranked.getWinStreak(userId, mode)
    local rows = MySQL.query.await([[
        SELECT won FROM ranked_elo_adjustments
        WHERE user_id = ? AND mode = ?
        ORDER BY created_at DESC
        LIMIT 25
    ]], { userId, mode }) or {}

    local streak = 0

    for index = 1, #rows do
        if rows[index].won ~= 1 then
            break
        end

        streak += 1
    end

    return streak
end

---A rough wait estimate: how long the parties currently queued in this mode
---have already been waiting. With nobody queued it is zero, which the NUI
---renders as "--" rather than a number.
---@param mode string
---@return integer seconds
function Ranked.getEstimatedQueueSeconds(mode)
    local total, count = 0, 0

    for _, party in pairs(Ranked.getAllParties()) do
        if party.mode == mode and party.queuedAt then
            total += os.time() - party.queuedAt
            count += 1
        end
    end

    if count == 0 then
        return 0
    end

    return math.floor(total / count)
end
