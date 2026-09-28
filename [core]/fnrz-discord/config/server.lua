
return {
    guildId = GetConvar('discord:guild', '1551440657543987270'),
    botToken = GetConvar('discord:token', 'MTU1MTU0NjM0MDg1MTMxODc5NA.GPP8kR.UlBSzqqw1Qp7sK5U1LO3B8UGyz3yT3aqp3Csd0'),

    cacheSeconds = GetConvarInt('discord:cacheSeconds', 600),

    ---@type table<string, string>
    roleToPrincipal = {
        -- ['1234567890123456789'] = 'group.admin',
        -- ['9876543210987654321'] = 'group.mod',
    },

    ---@type table<string, string>
    roleLabels = {
        -- ['1234567890123456789'] = 'Supporter',
    },

    requireGuildMembership = GetConvarInt('discord:requireMembership', 0) == 1,
}
