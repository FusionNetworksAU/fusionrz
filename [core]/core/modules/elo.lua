---@type CoreEloModule
local m = {}

local ROMAN_DIVISIONS = { 'I', 'II', 'III' }

---@param value number
---@return integer
local function round(value)
    return math.floor(value + 0.5)
end

---@param value number
---@param lower number
---@param upper number
---@return number
local function clamp(value, lower, upper)
    return math.max(lower, math.min(upper, value))
end

---@param rankData EloRank
---@return string
function m.formatRankLabel(rankData)
    if not rankData.division then
        return rankData.name
    end

    return ('%s %s'):format(rankData.name, ROMAN_DIVISIONS[rankData.division])
end

---@param ranks EloRank[]
---@param elo integer
---@return EloRank
---@return integer
function m.getRankForElo(ranks, elo)
    for rankIndex = 1, #ranks do
        if ranks[rankIndex].elo > elo then
            local resolvedIndex = math.max(rankIndex - 1, 1)
            return ranks[resolvedIndex], resolvedIndex
        end
    end

    return ranks[#ranks], #ranks
end

---@param ranks EloRank[]
---@param elo integer
---@return EloRank
function m.getNextRank(ranks, elo)
    for rankIndex = 1, #ranks do
        if ranks[rankIndex].elo > elo then
            return ranks[rankIndex]
        end
    end

    return ranks[#ranks]
end

---@param ranks EloRank[]
---@param elo integer
---@param position integer?
---@return EloRank
---@return integer
function m.getRankForPosition(ranks, elo, position)
    local rankData, rankIndex = m.getRankForElo(ranks, elo)

    while rankIndex > 1 and rankData.topPlayers and (not position or position > rankData.topPlayers) do
        rankIndex = rankIndex - 1
        rankData = ranks[rankIndex]
    end

    return rankData, rankIndex
end

---@param ranks EloRank[]
---@param name string
---@return integer?
function m.getRankIndexByName(ranks, name)
    for rankIndex = 1, #ranks do
        if ranks[rankIndex].name == name then
            return rankIndex
        end
    end

    return nil
end

---@param ranks EloRank[]
---@param name string
---@return integer?
function m.getLastRankIndexByName(ranks, name)
    local lastIndex = nil

    for rankIndex = 1, #ranks do
        if ranks[rankIndex].name == name then
            lastIndex = rankIndex
        elseif lastIndex then
            break
        end
    end

    return lastIndex
end

---@param config EloCalculationConfig
---@param elo integer
---@return integer
function m.getWinReward(config, elo)
    local amount, bestMinElo = 0, -1

    for _, reward in pairs(config.winRewards) do
        if elo >= reward.minElo and reward.minElo > bestMinElo then
            amount, bestMinElo = reward.amount, reward.minElo
        end
    end

    return amount
end

---@param config EloCalculationConfig
---@param eloDifference number
---@return integer
function m.getOpponentStrengthAdjustment(config, eloDifference)
    local absDifference = math.abs(eloDifference)
    local magnitude, bestMinDifference = 0, -1

    for _, entry in pairs(config.opponentStrength) do
        if absDifference >= entry.minDifference and entry.minDifference > bestMinDifference then
            magnitude, bestMinDifference = entry.adjustment, entry.minDifference
        end
    end

    return eloDifference > 0 and magnitude or -magnitude
end

---@param config EloCalculationConfig
---@param stats EloPerformanceStats
---@return number
function m.getPerformanceScore(config, stats)
    local performance = config.performance

    local score = stats.kills * performance.killWeight
        + stats.assists * performance.assistWeight
        + stats.deaths * performance.deathWeight
        + stats.damage / performance.damagePerPoint

    return math.max(score, 0)
end

---@param config EloCalculationConfig
---@param score number
---@param meanScore number
---@param numPlayers integer
---@return integer
function m.getPerformanceAdjustment(config, score, meanScore, numPlayers)
    if numPlayers < 2 or meanScore <= 0 then
        return 0
    end

    local maxAdjustment = config.performance.maxAdjustment
    return clamp(round((score / meanScore - 1) * maxAdjustment), -maxAdjustment, maxAdjustment) --[[@as integer]]
end

---@param candidate EloMvpCandidate
---@param current EloMvpCandidate
---@return boolean
function m.isBetterMvp(candidate, current)
    if candidate.score ~= current.score then
        return candidate.score > current.score
    end

    if candidate.kills ~= current.kills then
        return candidate.kills > current.kills
    end

    if candidate.damage ~= current.damage then
        return candidate.damage > current.damage
    end

    return candidate.userId < current.userId
end

---@param config EloCalculationConfig
---@param input EloCalculationInput
---@return EloCalculationResult
function m.calculateEloChange(config, input)
    local base = input.didWin and m.getWinReward(config, input.elo) or (input.isFeared and config.fearedLoss or config.loss)
    local opponent = m.getOpponentStrengthAdjustment(config, input.opposingAverageElo - input.teamAverageElo)
    local performance = m.getPerformanceAdjustment(config, input.score, input.teamMeanScore, input.numTeamPlayers)
    local mvp = input.isMvp and config.mvpBonus or 0

    local eloChange = base + opponent + performance + mvp

    local fullStackMultiplierApplied = false
    if input.didWin and eloChange > 0 and input.partySize >= config.fullStackSize and input.rankIndex >= input.highRankIndex then
        eloChange = math.floor(eloChange * config.fullStackHighRankWinMultiplier)
        fullStackMultiplierApplied = true
    end

    local soloQueueMultiplierApplied = false
    if not input.didWin and eloChange < 0 and input.partySize <= 1 then
        eloChange = math.ceil(eloChange * config.soloQueueLossMultiplier)
        soloQueueMultiplierApplied = true
    end

    local capped = false
    if not input.isFeared then
        local cappedEloChange = clamp(eloChange, config.maxLoss, config.maxGain)
        capped = cappedEloChange ~= eloChange
        eloChange = cappedEloChange
    end

    local minWinApplied = false
    local minWinGain = config.minWinGain
    local minWinRankIndex = input.minWinRankIndex
    if input.didWin and not input.isForfeit and minWinGain and minWinRankIndex and input.rankIndex >= minWinRankIndex then
        local lastRankIndex = input.minWinLastRankIndex or minWinRankIndex
        if input.rankIndex <= lastRankIndex and eloChange < minWinGain then
            eloChange = minWinGain
            minWinApplied = true
        end
    end

    return {
        base = base,
        opponent = opponent,
        performance = performance,
        mvp = mvp,
        fullStackMultiplierApplied = fullStackMultiplierApplied,
        soloQueueMultiplierApplied = soloQueueMultiplierApplied,
        capped = capped,
        minWinApplied = minWinApplied,
        eloChange = math.floor(eloChange),
    }
end

---@param player EloMatchPlayer
---@param score number
---@return EloMvpCandidate
local function toMvpCandidate(player, score)
    return {
        score = score,
        kills = player.kills,
        damage = player.damage,
        userId = player.userId,
    }
end

---@param config EloCalculationConfig
---@param match EloMatch
---@return table<UserID, EloMatchPlayerResult>
---@return table<string, EloMatchTeamSummary>
function m.calculateMatchEloChanges(config, match)
    ---@type table<string, EloMatchTeamSummary>
    local summaries = {}
    ---@type table<UserID, number>
    local scores = {}

    for teamName, teamData in pairs(match.teams) do
        local totalElo, totalScore, numPlayers = 0, 0, 0
        ---@type EloMatchPlayer?
        local mvp = nil

        for _, player in pairs(teamData.players) do
            local score = m.getPerformanceScore(config, player)
            scores[player.userId] = score

            totalElo = totalElo + player.elo
            totalScore = totalScore + score
            numPlayers = numPlayers + 1

            if not mvp or m.isBetterMvp(toMvpCandidate(player, score), toMvpCandidate(mvp, scores[mvp.userId])) then
                mvp = player
            end
        end

        summaries[teamName] = {
            averageElo = numPlayers > 0 and totalElo / numPlayers or 0,
            opposingAverageElo = 0,
            meanScore = numPlayers > 0 and totalScore / numPlayers or 0,
            mvpUserId = (numPlayers >= 2 and mvp) and mvp.userId or nil,
            numPlayers = numPlayers,
        }
    end

    for teamName, summary in pairs(summaries) do
        local total, numTeams = 0, 0

        for otherTeamName, otherSummary in pairs(summaries) do
            if otherTeamName ~= teamName and otherSummary.numPlayers > 0 then
                total = total + otherSummary.averageElo
                numTeams = numTeams + 1
            end
        end

        summary.opposingAverageElo = numTeams > 0 and total / numTeams or summary.averageElo
    end

    ---@type table<UserID, EloMatchPlayerResult>
    local results = {}

    for teamName, teamData in pairs(match.teams) do
        local summary = summaries[teamName]

        ---@type boolean?
        local didWin = nil
        if match.winningTeamName then
            didWin = teamName == match.winningTeamName
        end

        for _, player in pairs(teamData.players) do
            local isMvp = summary.mvpUserId == player.userId

            ---@type EloCalculationResult?
            local change = nil
            if didWin ~= nil then
                change = m.calculateEloChange(config, {
                    didWin = didWin,
                    elo = player.elo,
                    isFeared = player.isFeared,
                    teamAverageElo = summary.averageElo,
                    opposingAverageElo = summary.opposingAverageElo,
                    score = scores[player.userId],
                    teamMeanScore = summary.meanScore,
                    numTeamPlayers = summary.numPlayers,
                    isMvp = isMvp,
                    partySize = player.partySize,
                    rankIndex = player.rankIndex,
                    highRankIndex = match.highRankIndex,
                    isForfeit = match.isForfeit,
                    minWinRankIndex = match.minWinRankIndex,
                    minWinLastRankIndex = match.minWinLastRankIndex,
                })
            end

            results[player.userId] = {
                userId = player.userId,
                teamName = teamName,
                didWin = didWin,
                score = scores[player.userId],
                isMvp = isMvp,
                change = change,
            }
        end
    end

    return results, summaries
end

---@param currentRank EloRank
---@param nextRank EloRank
---@param elo integer
---@return EloDivisionProgress
function m.getDivisionProgress(currentRank, nextRank, elo)
    if nextRank.elo <= currentRank.elo then
        return { isTopRank = true, current = 1, total = 1 }
    end

    return {
        isTopRank = false,
        current = elo - currentRank.elo,
        total = nextRank.elo - currentRank.elo,
    }
end

---@param ranks EloRank[]
---@param getNumPlayers fun(minElo: integer, maxElo: integer?): integer
---@return CareerRankTier[]
function m.groupRanksByTier(ranks, getNumPlayers)
    ---@type CareerRankTier[]
    local tiers = {}
    ---@type CareerRankTier?
    local currentTier = nil

    for index = 1, #ranks do
        local rankData = ranks[index]
        local nextRank = ranks[index + 1]
        local nextRankElo = nextRank and nextRank.elo or nil
        local numPlayers = getNumPlayers(rankData.elo, nextRankElo)

        if rankData.topPlayers and numPlayers > rankData.topPlayers then
            local overflow = numPlayers - rankData.topPlayers
            numPlayers = rankData.topPlayers --[[@as integer]]

            if currentTier then
                currentTier.numPlayers = currentTier.numPlayers + overflow

                local lastDivision = currentTier.divisions and currentTier.divisions[#currentTier.divisions]
                if lastDivision then
                    lastDivision.numPlayers = lastDivision.numPlayers + overflow
                end
            end
        end

        if not currentTier or currentTier.name ~= rankData.name then
            currentTier = {
                rank = string.lower(rankData.name),
                name = rankData.name,
                numPlayers = 0,
                minElo = rankData.elo,
                maxElo = nextRankElo,
                divisions = rankData.division and {} or nil,
            }
            tiers[#tiers + 1] = currentTier
        end

        currentTier.numPlayers = currentTier.numPlayers + numPlayers
        currentTier.maxElo = nextRankElo

        if rankData.division and currentTier.divisions then
            currentTier.divisions[#currentTier.divisions + 1] = {
                label = ROMAN_DIVISIONS[rankData.division],
                minElo = rankData.elo,
                maxElo = nextRankElo,
                numPlayers = numPlayers,
            }
        end
    end

    return tiers
end

return m
