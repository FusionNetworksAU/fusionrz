---@class LevelsSharedConfig
local config = {
    maxLevel = 100,
    maxPrestige = 6,
    xp = {
        kills = 100,
        headshots = 25,
        wins = 500,
        losses = 100,
    },
    answerTtlSeconds = 45,
}

---@param level integer
---@return integer
function config.xpForNext(level)
    return 4000 + 400 * level
end

---@param level integer
---@param xp integer
---@param prestige integer
---@return CareerLevelState
function config.buildState(level, xp, prestige)
    return {
        level = level,
        xp = xp,
        prestige = prestige,
        xpForNext = config.xpForNext(level),
        maxLevel = config.maxLevel,
        maxPrestige = config.maxPrestige,
    }
end

return config
