---/ff: a team votes to forfeit the match.
---
---  /ff          start a vote, or vote YES on your team's open vote
---  /ff no       vote NO
---
---Rules:
---  * only from round 2 on, while a round is being played or set up
---  * one vote per team per half (sides swap at half-time, so a team gets a
---    second chance after the swap -- and never more than one per round)
---  * passes on MIN_YES_VOTES yes votes; a team smaller than that needs every
---    member (a 1v1 player forfeits alone, a duo needs both)
---  * fails as soon as enough NOs make the target unreachable, or on timeout
---
---A passed vote ends the match with the other team as the winner, through the
---normal matchend state -- so the scoreboard, stats, XP and ranked ELO all
---treat it as a real loss.

Hopouts = Hopouts or {}

local MIN_YES_VOTES = 3
local VOTE_DURATION_MSEC = 30000

---States in which a vote may be called or cast.
local VOTABLE_STATES = { preround = true, live = true, roundend = true }

---@param match HopOutMatch
---@param side string
---@return HopOutPlayer[]
local function connectedTeam(match, side)
    local team = {}

    for _, player in ipairs(Hopouts.getPlayers(match, side)) do
        if player.connected ~= false and GetPlayerName(player.source --[[@as string]]) then
            team[#team + 1] = player
        end
    end

    return team
end

---@param match HopOutMatch
---@param side string
---@param event string
---@param ... any
local function toTeam(match, side, event, ...)
    for _, player in ipairs(Hopouts.getPlayers(match, side)) do
        TriggerClientEvent(event, player.source, ...)
    end
end

---@param match HopOutMatch
---@param side string
---@return string
local function otherSide(match, side)
    for index = 1, #match.sides do
        if match.sides[index] ~= side then
            return match.sides[index]
        end
    end

    return side
end

---@param source Source
---@param text string
---@param kind string?
local function tell(source, text, kind)
    TriggerClientEvent('hopouts:client:ffNotify', source, { text = text, type = kind or 'inform' })
end

---@param match HopOutMatch
---@param side string
---@return table vote
local function tally(match, side)
    local vote = match.ffVote and match.ffVote[side]
    local team = connectedTeam(match, side)
    local yes, no = 0, 0

    for _, player in ipairs(team) do
        local choice = vote and vote.votes[player.source]

        if choice == true then
            yes += 1
        elseif choice == false then
            no += 1
        end
    end

    return {
        yes = yes,
        no = no,
        teamSize = #team,
        required = math.min(MIN_YES_VOTES, math.max(#team, 1)),
    }
end

---@param match HopOutMatch
---@param side string
local function pushStatus(match, side)
    local vote = match.ffVote and match.ffVote[side]

    if not vote then
        return
    end

    local count = tally(match, side)

    toTeam(match, side, 'hopouts:client:ffVote', {
        active = true,
        starter = vote.starter,
        yes = count.yes,
        no = count.no,
        required = count.required,
        teamSize = count.teamSize,
        endsIn = math.max(0, vote.endsAt - GetGameTimer()),
    })
end

---@param match HopOutMatch
---@param side string
---@param reason string
local function closeVote(match, side, reason)
    if not (match.ffVote and match.ffVote[side]) then
        return
    end

    match.ffVote[side] = nil

    toTeam(match, side, 'hopouts:client:ffVote', { active = false })
    toTeam(match, side, 'hopouts:client:ffNotify', { text = reason, type = 'error' })
end

---@param match HopOutMatch
---@param side string
local function forfeit(match, side)
    match.ffVote[side] = nil
    match.forfeitSide = side

    toTeam(match, side, 'hopouts:client:ffVote', { active = false })

    for _, player in pairs(match.players) do
        TriggerClientEvent('hopouts:client:ffNotify', player.source, {
            text = player.side == side and 'Your team forfeited the match.' or 'The enemy team forfeited. You win!',
            type = player.side == side and 'error' or 'success',
        })
    end

    lib.print.info(('[hopouts] match %s: side %s forfeited'):format(match.id, side))

    Hopouts.setState(match, 'matchend', Hopouts.sharedConfig.winnerPreviewDurationMsec)
end

---Settles a vote as soon as the outcome is certain.
---@param match HopOutMatch
---@param side string
local function evaluate(match, side)
    local count = tally(match, side)

    if count.yes >= count.required then
        return forfeit(match, side)
    end

    -- Enough NOs that even every remaining YES could not reach the target.
    if count.teamSize - count.no < count.required then
        return closeVote(match, side, ('Forfeit vote failed (%d yes / %d no).'):format(count.yes, count.no))
    end

    pushStatus(match, side)
end

---@param source Source
---@param wantsYes boolean
local function handle(source, wantsYes)
    local match = Hopouts.getMatchForPlayer(source)
    local player = match and match.players[source]

    if not match or not player then
        return tell(source, 'You are not in a match.', 'error')
    end

    local side = player.side
    match.ffVote = match.ffVote or {}
    match.ffUsed = match.ffUsed or {}

    local vote = match.ffVote[side]

    -- Casting a vote on the team's open one.
    if vote then
        if vote.votes[source] ~= nil then
            return tell(source, 'You have already voted.', 'error')
        end

        vote.votes[source] = wantsYes

        return evaluate(match, side)
    end

    if not wantsYes then
        return tell(source, 'There is no forfeit vote to vote on.', 'error')
    end

    -- Starting a new one.
    if not VOTABLE_STATES[match.state] then
        return tell(source, 'You cannot forfeit right now.', 'error')
    end

    if (match.round or 0) < 2 then
        return tell(source, 'You can only forfeit after round 1.', 'error')
    end

    local half = match.swapped and 2 or 1
    local usedKey = ('%s:%d'):format(side, half)

    if match.ffUsed[usedKey] then
        return tell(source, 'Your team has already called a forfeit vote this half.', 'error')
    end

    match.ffUsed[usedKey] = true

    match.ffVote[side] = {
        starter = player.username,
        votes = { [source] = true },
        endsAt = GetGameTimer() + VOTE_DURATION_MSEC,
    }

    toTeam(match, side, 'hopouts:client:ffNotify', {
        text = ('%s wants to forfeit. Type /ff to vote YES or /ff no to vote NO.'):format(player.username),
        type = 'inform',
    })

    local startedRound = match.round

    SetTimeout(VOTE_DURATION_MSEC, function()
        local open = match.ffVote and match.ffVote[side]

        -- Still the same vote (not passed, failed or replaced).
        if open and open.endsAt <= GetGameTimer() + 50 and match.state ~= 'matchend' then
            local count = tally(match, side)

            closeVote(match, side, ('Forfeit vote timed out (%d/%d yes).'):format(count.yes, count.required))
        end
    end)

    lib.print.info(('[hopouts] match %s round %s: %s started a forfeit vote for side %s'):format(
        match.id, startedRound, player.username, side
    ))

    evaluate(match, side)
end

lib.addCommand('ff', {
    help = 'Vote to forfeit the hopouts match (/ff = yes, /ff no = no)',
    params = {
        { name = 'vote', type = 'string', help = 'yes / no', optional = true },
    },
}, function(source, args)
    local choice = type(args.vote) == 'string' and args.vote:lower() or 'yes'

    handle(source, not (choice == 'no' or choice == 'n' or choice == 'false'))
end)

---Who won a match that ended by forfeit: the side that did not give up.
---@param match HopOutMatch
---@return string?
function Hopouts.getForfeitWinner(match)
    if not match.forfeitSide then
        return nil
    end

    return otherSide(match, match.forfeitSide)
end

-- A player leaving mid-vote changes the team size; re-check so the vote can
-- still pass (or fail) instead of hanging on a vote that will never come.
AddEventHandler('core:server:onPlayerDropped', function(source)
    local match = Hopouts.getMatchForPlayer(source)
    local player = match and match.players[source]

    if not player or not match.ffVote or not match.ffVote[player.side] then
        return
    end

    local side = player.side

    match.ffVote[side].votes[source] = nil

    SetTimeout(0, function()
        if match.ffVote and match.ffVote[side] and match.state ~= 'matchend' then
            evaluate(match, side)
        end
    end)
end)
