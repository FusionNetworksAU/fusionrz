local hopouts = exports.hopouts

---@param leftVisible boolean
---@param rightVisible boolean
local function setHopoutsTeammatesVisible(leftVisible, rightVisible)
    SendNUIMessage({
        action = 'setHopoutsTeammatesVisible',
        data = {
            left = leftVisible,
            right = rightVisible,
        }
    })
end

exports('setHopoutsTeammatesVisible', setHopoutsTeammatesVisible)

---@param leftData table
---@param rightData table
local function setHopoutsTeammatesData(leftData, rightData)
    SendNUIMessage({
        action = 'setHopoutsTeammatesData',
        data = {
            left = leftData or {},
            right = rightData or {},
        }
    })
end

exports('setHopoutsTeammatesData', setHopoutsTeammatesData)

---@param isVisible boolean
local function setHopoutsGameStatsVisible(isVisible)
    SendNUIMessage({ action = 'setHopoutsGameStatsVisible', data = isVisible })
end

exports('setHopoutsGameStatsVisible', setHopoutsGameStatsVisible)

---@param isVisible boolean
local function setHopoutsGameStatsTimeFrozen(isVisible)
    SendNUIMessage({ action = 'setHopoutsGameStatsTimeFrozen', data = isVisible })
end

exports('setHopoutsGameStatsTimeFrozen', setHopoutsGameStatsTimeFrozen)

---@param data table
local function setHopoutsGameStatsData(data)
    SendNUIMessage({ action = 'setHopoutsGameStatsData', data = data })
end

exports('setHopoutsGameStatsData', setHopoutsGameStatsData)

---@param isVisible boolean
local function setHopoutsHotbarVisible(isVisible)
    SendNUIMessage({ action = 'setHopoutsHotbarVisible', data = isVisible })
end

exports('setHopoutsHotbarVisible', setHopoutsHotbarVisible)

---Slots the hotbar always draws, and reads unguarded: always sent.
local HOTBAR_SLOTS = {
    pistol = '2',
    axe = '3',
    vest = '4',
    medkit = '5',
    blunt = '6',
}

---Slots the hotbar only draws when present (`r.rifle && ...`). Sent only when
---the sender included them -- filling them in regardless is what put an empty
---rifle slot on the hotbar through every pistol-only round.
local OPTIONAL_HOTBAR_SLOTS = {
    rifle = '1',
    repairkit = '7',
    smoke = '8',
}

local LEGACY_COUNTS = {
    armour = 'vest',
    medkits = 'medkit',
    smokes = 'smoke',
    blunts = 'blunt',
    repairkits = 'repairkit',
}

---@param data table?
---@return table
local function normaliseHotbar(data)
    data = type(data) == 'table' and data or {}

    local out = {}

    ---@param src table
    ---@param defaultKey string
    ---@return table
    local function slot(src, defaultKey)
        return {
            selected = src.selected == true,
            keybind = tostring(src.keybind or defaultKey),
            count = tonumber(src.count) or 0,
            currentAmmo = tonumber(src.currentAmmo) or 0,
            totalAmmo = tonumber(src.totalAmmo) or 0,
        }
    end

    for name, defaultKey in pairs(HOTBAR_SLOTS) do
        out[name] = slot(type(data[name]) == 'table' and data[name] or {}, defaultKey)
    end

    for name, defaultKey in pairs(OPTIONAL_HOTBAR_SLOTS) do
        if type(data[name]) == 'table' then
            out[name] = slot(data[name], defaultKey)
        end
    end

    for legacyKey, name in pairs(LEGACY_COUNTS) do
        local count = tonumber(data[legacyKey])

        if count then
            -- An optional slot only appears through a legacy count if there is
            -- actually something in it.
            if not out[name] and OPTIONAL_HOTBAR_SLOTS[name] and count > 0 then
                out[name] = slot({}, OPTIONAL_HOTBAR_SLOTS[name])
            end

            if out[name] then
                out[name].count = count
            end
        end
    end

    return out
end

---@param data table
local function setHopoutsHotbarData(data)
    SendNUIMessage({ action = 'setHopoutsHotbarData', data = normaliseHotbar(data) })
end

exports('setHopoutsHotbarData', setHopoutsHotbarData)

---@param isVisible boolean
local function setWarsHotbarVisible(isVisible)
    SendNUIMessage({ action = 'setWarsHotbarVisible', data = isVisible })
end

exports('setWarsHotbarVisible', setWarsHotbarVisible)

---@param data table
local function setWarsHotbarData(data)
    SendNUIMessage({ action = 'setWarsHotbarData', data = data })
end

exports('setWarsHotbarData', setWarsHotbarData)

---@param isVisible boolean
local function setRifleFfaHotbarVisible(isVisible)
    SendNUIMessage({ action = 'setRifleFfaHotbarVisible', data = isVisible })
end

exports('setRifleFfaHotbarVisible', setRifleFfaHotbarVisible)

---@param data table
local function setRifleFfaHotbarData(data)
    SendNUIMessage({ action = 'setRifleFfaHotbarData', data = data })
end

exports('setRifleFfaHotbarData', setRifleFfaHotbarData)

---@param isVisible boolean
local function setGasMovingVisible(isVisible)
    SendNUIMessage({ action = 'setGasMovingVisible', data = isVisible })
end

exports('setGasMovingVisible', setGasMovingVisible)

---@param isVisible boolean
local function setSpectateVisible(isVisible)
    SendNUIMessage({ action = 'setSpectateVisible', data = isVisible })
end

exports('setSpectateVisible', setSpectateVisible)

---@param data table
local function setSpectateData(data)
    SendNUIMessage({ action = 'setSpectateData', data = data })
end

exports('setSpectateData', setSpectateData)

local scoreboardVisible = false
local hasScoreboardThread = false

---@param isVisible boolean
---@param isWinner boolean
---@param keepControls boolean?
---@param noFocus boolean? a glance (hold-TAB during a round): no cursor, no
---blur, no control lock -- the player is still fighting
local function setHopoutScoreboardVisible(isVisible, isWinner, keepControls, noFocus)
    SendNUIMessage({
        action = 'setHopoutScoreboardVisible',
        data = {
            isVisible = isVisible,
            isWinner = isWinner,
        }
    })

    if noFocus then
        return
    end

    SetNuiFocus(isVisible, isVisible)
    if keepControls then
        SetNuiFocusKeepInput(isVisible)
    end

    if isVisible then TriggerScreenblurFadeIn(0) else TriggerScreenblurFadeOut(0) end

    scoreboardVisible = isVisible

    if scoreboardVisible and not hasScoreboardThread then
        hasScoreboardThread = true
        Citizen.CreateThreadNow(function()
            while scoreboardVisible do
                for i = 1, 6 do
                    DisableControlAction(0, i, true)
                end

                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 257, true)

                Wait(0)
            end

            hasScoreboardThread = false
        end)
    end
end

exports('setHopoutScoreboardVisible', setHopoutScoreboardVisible)

local function setHopoutScoreboardData(data)
    data = type(data) == 'table' and data or {}

    local teams = type(data.teams) == 'table' and data.teams or {}

    local colours = { 'blue', 'red' }

    if type(teams.yellow) == 'table' then
        colours[3] = 'yellow'
    end

    for _, colour in ipairs(colours) do
        local team = type(teams[colour]) == 'table' and teams[colour] or {}
        local players = {}

        for index, player in ipairs(type(team.players) == 'table' and team.players or {}) do
            if type(player) == 'table' then
                player.id = player.id or player.userId or index
                player.username = tostring(player.username or ('Player %d'):format(index))
                player.kills = tonumber(player.kills) or 0
                player.deaths = tonumber(player.deaths) or 0
                player.damage = tonumber(player.damage) or 0
                player.headshotPercent = tonumber(player.headshotPercent) or 0
                player.winStreak = tonumber(player.winStreak) or 0
                player.ping = tonumber(player.ping) or 0
                player.level = tonumber(player.level) or 1
                player.prestige = tonumber(player.prestige) or 0
                player.isTalking = player.isTalking == true
                player.isMuted = player.isMuted == true

                players[#players + 1] = player
            end
        end

        team.players = players
        team.score = tonumber(team.score) or 0
        team.displayName = team.displayName or (colour:sub(1, 1):upper() .. colour:sub(2))

        teams[colour] = team
    end

    data.teams = teams
    data.currentRound = tonumber(data.currentRound) or 0
    data.roundsToWin = tonumber(data.roundsToWin) or 5

    SendNUIMessage({ action = 'setHopoutScoreboardData', data = data })
end

exports('setHopoutScoreboardData', setHopoutScoreboardData)

---@param isVisible boolean
local function setRoundMvpVisible(isVisible)
    SendNUIMessage({ action = 'setRoundMvpVisible', data = isVisible })
end

exports('setRoundMvpVisible', setRoundMvpVisible)

---@param data table
local function setRoundMvpData(data)
    SendNUIMessage({ action = 'setRoundMvpData', data = data })
end

exports('setRoundMvpData', setRoundMvpData)

---@param isVisible boolean
local function setSwitchSizesVisible(isVisible)
    SendNUIMessage({ action = 'setSwitchSizesVisible', data = isVisible })
end

exports('setSwitchSizesVisible', setSwitchSizesVisible)

---@param data table
local function setSwitchSidesData(data)
    local players = {}

    if type(data) == 'table' and data[1] ~= nil then
        for index, entry in ipairs(data) do
            if type(entry) == 'table' then
                players[#players + 1] = {
                    name = tostring(entry.name or entry.username or ('Player %d'):format(index)),
                    profileImage = entry.profileImage or entry.avatar,
                    bannerImage = entry.bannerImage or 'ccs/fnrz_default.webp',
                    gang = entry.gang,
                    mvp = entry.mvp == true,
                }
            end
        end
    end

    SendNUIMessage({ action = 'setSwitchSidesData', data = players })
end

exports('setSwitchSidesData', setSwitchSidesData)

RegisterNUICallback('voteToKick', function(targetUserId, cb)
    TriggerEvent('ui:voteToKickRequested', targetUserId)
    cb(true)
end)

RegisterNUICallback('togglePlayerMute', function(targetUserId, cb)
    local isMuted = hopouts:togglePlayerMute(targetUserId)
    cb(isMuted)
end)

---@param isVisible boolean
local function setCombatReportVisible(isVisible)
    SendNUIMessage({ action = 'setCombatReportVisible', data = isVisible })
end

exports('setCombatReportVisible', setCombatReportVisible)

---@param data table
local function setCombatReportData(data)
    SendNUIMessage({ action = 'setCombatReportData', data = data })
end

exports('setCombatReportData', setCombatReportData)

---@param isVisible boolean
local function setMatchWinnerVisible(isVisible)
    SendNUIMessage({ action = 'setMatchWinnerVisible', data = isVisible })
end

exports('setMatchWinnerVisible', setMatchWinnerVisible)

---@param data table
---Where each winner card sits, in CSS px: one centred row. Used whenever the
---caller has no layout of its own (hopouts has none in its config, so it sent
---nil and the screen crashed indexing it).
---@param count integer
---@return table[]
local function defaultWinnerPositions(count)
    local width, height = GetActiveScreenResolution()
    local spacing = math.min(260, (width * 0.8) / math.max(count, 1))
    local positions = {}

    for index = 1, count do
        positions[index] = {
            x = width / 2 + (index - (count + 1) / 2) * spacing,
            y = height * 0.62,
            scale = 1,
        }
    end

    return positions
end

local winnerPositionsGiven = false

---The winner screen reads { title, color, players = { { name, gang, kills,
---damage, profileImage, bannerImage, mvp } } } and maps `players`
---unguarded. hopouts sent { winningSide, winners, scores }, which crashed the
---whole UI the moment a match ended. Either shape is accepted.
---@param data table
local function setMatchWinnerData(data)
    data = type(data) == 'table' and data or {}

    local source = type(data.players) == 'table' and data.players
        or type(data.winners) == 'table' and data.winners
        or {}

    local players = {}

    for index = 1, #source do
        local row = source[index]

        if type(row) == 'table' then
            players[#players + 1] = {
                name = tostring(row.name or row.username or 'Player'),
                gang = tostring(row.gang or 'FNRZ'),
                kills = tonumber(row.kills) or 0,
                damage = tonumber(row.damage) or 0,
                profileImage = row.profileImage or row.avatar or '',
                bannerImage = row.bannerImage or 'ccs/fnrz_default.webp',
                mvp = row.mvp == true or index == 1,
            }
        end
    end

    SendNUIMessage({
        action = 'setMatchWinnerData',
        data = {
            title = tostring(data.title or 'MATCH OVER'),
            color = data.color or '#2695FC',
            players = players,
            bannerTopRem = tonumber(data.bannerTopRem),
        },
    })

    if not winnerPositionsGiven then
        SendNUIMessage({ action = 'setMatchWinnerPositions', data = defaultWinnerPositions(#players) })
    end

    winnerPositionsGiven = false
end

exports('setMatchWinnerData', setMatchWinnerData)

---@param positions table?
local function setMatchWinnerPositions(positions)
    if type(positions) ~= 'table' or #positions == 0 then
        return
    end

    winnerPositionsGiven = true

    SendNUIMessage({ action = 'setMatchWinnerPositions', data = positions })
end

exports('setMatchWinnerPositions', setMatchWinnerPositions)

---@param isVisible boolean
---@param canInteract boolean?
local function setRequestDoubleVisible(isVisible, canInteract)
    SendNUIMessage({ action = 'setRequestDoubleVisible', data = isVisible })

    local hasFocus = isVisible and canInteract == true
    SetNuiFocus(hasFocus, hasFocus)
end

exports('setRequestDoubleVisible', setRequestDoubleVisible)

---@param data table
local function setRequestDoubleTeams(data)
    SendNUIMessage({ action = 'setRequestDoubleTeams', data = data })
end

exports('setRequestDoubleTeams', setRequestDoubleTeams)

---@param teamId string
---@param numAccepted integer
local function setRequestDoubleTeamCount(teamId, numAccepted)
    SendNUIMessage({
        action = 'setRequestDoubleTeamCount',
        data = {
            id = teamId,
            numAccepted = numAccepted,
        }
    })
end

exports('setRequestDoubleTeamCount', setRequestDoubleTeamCount)

---@param countdown integer
local function setRequestDoubleCountdown(countdown)
    SendNUIMessage({ action = 'setRequestDoubleCountdown', data = countdown })
end

exports('setRequestDoubleCountdown', setRequestDoubleCountdown)

---@param vote boolean
RegisterNUICallback('submitRequestDoubleVote', function(vote, cb)
    local success = hopouts:submitRequestDoubleVote(vote)
    cb(success)
end)

---@param mapId string
RegisterNUICallback('voteForDoubleMapBan', function(mapId, cb)
    local success = lib.callback.await('hopouts:server:voteForDoubleMapBan', nil, mapId)
    cb(success)
end)

RegisterNUICallback('skipDoubleMapBanVote', function(_, cb)
    local success = lib.callback.await('hopouts:server:voteForDoubleMapSkip', nil)
    cb(success)
end)

---@param enabled boolean
local function setSpeakingListEnabled(enabled)
    SendNUIMessage({ action = 'setSpeakingListEnabled', data = enabled })
end

exports('setSpeakingListEnabled', setSpeakingListEnabled)

---@param speaker table
local function addSpeakingListSpeaker(speaker)
    SendNUIMessage({ action = 'addSpeakingListSpeaker', data = speaker })
end

exports('addSpeakingListSpeaker', addSpeakingListSpeaker)

---@param id integer
local function removeSpeakingListSpeaker(id)
    SendNUIMessage({ action = 'removeSpeakingListSpeaker', data = id })
end

exports('removeSpeakingListSpeaker', removeSpeakingListSpeaker)