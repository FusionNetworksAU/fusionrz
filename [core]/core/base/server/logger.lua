local utils = Core.utils

---@type table<string, string>
local webhookCache = {}

---@type table<string, integer>
local channelColours = {
    connections = 3066993,
    coins = 15844367,
    bans = 15158332,
    commands = 3447003,
    protection = 10038562,
    items = 9807270,
}

local DEFAULT_COLOUR = 9807270

local MAX_DESCRIPTION = 1900

---@param channel string
---@return string? url
local function getWebhook(channel)
    local cached = webhookCache[channel]

    if cached ~= nil then
        return cached ~= '' and cached or nil
    end

    local url = GetConvar(('core:webhook:%s'):format(channel), '')
    webhookCache[channel] = url

    return url ~= '' and url or nil
end

---@param channel string
---@param message string
---@param fields table[]?
function Core.log(channel, message, fields)
    if Core.env.getEnv() ~= 'production' then
        lib.print.info(('[%s] %s'):format(channel, message))
    end

    local url = getWebhook(channel)

    if not url then
        return
    end

    if #message > MAX_DESCRIPTION then
        message = message:sub(1, MAX_DESCRIPTION) .. '...'
    end

    CreateThread(function()
        utils.fetch(url, {
            method = 'POST',
            headers = { ['Content-Type'] = 'application/json' },
            data = json.encode({
                username = 'core',
                embeds = { {
                    title = channel,
                    description = message,
                    color = channelColours[channel] or DEFAULT_COLOUR,
                    fields = fields,
                    footer = { text = os.date('%Y-%m-%d %H:%M:%S') },
                } },
            }),
        })
    end)
end

---@param channel string
---@param url string
function Core.setWebhook(channel, url)
    webhookCache[channel] = url
end

exports('Log', Core.log)
