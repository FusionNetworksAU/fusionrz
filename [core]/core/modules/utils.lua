local m = {}

---@param t table
---@return number count
function m.getTableSize(t)
    local c = 0
    for _ in pairs(t) do c += 1 end
    return c
end

---@generic T
---@param fn fun(key): unknown
---@param key string
---@param default? T
---@return T
function m.safeGetKvp(fn, key, default)
    local ok, result = pcall(fn, key)

    if not ok then
        return DeleteResourceKvp(key)
    end

    return result or default
end

if IsDuplicityVersion() then
    ---@class FetchResponse
    ---@field errorData? string
    ---@field headers table<string, string>
    ---@field status integer
    ---@field body? string

    ---@class FetchOptions
    ---@field headers? table<string, any>
    ---@field method? string
    ---@field data? string

    ---@class PlayerIdentifiers
    ---@field license? string
    ---@field license2 string
    ---@field fivem? string
    ---@field discord? string
    ---@field steam? string
    ---@field live? string
    ---@field xbl? string

    local PerformHttpRequest = PerformHttpRequest
    local GetNumPlayerIdentifiers = GetNumPlayerIdentifiers
    local GetPlayerIdentifier = GetPlayerIdentifier
    local GetNumPlayerTokens = GetNumPlayerTokens
    local GetPlayerToken = GetPlayerToken

    ---@param entity integer
    function m.deleteEntity(entity)
        if not DoesEntityExist(entity) then
            return
        end

        DeleteEntity(entity)
    end

    ---A simple wrapper around PerformHttpRequest
    ---@param url string
    ---@param options? FetchOptions
    ---@return FetchResponse response
    function m.fetch(url, options)
        local p = promise.new()

        PerformHttpRequest(url, function(status, body, headers, errorData)
            local resp = {
                errorData = errorData,
                headers = headers,
                status = status,
                body = body,
            }

            p:resolve(resp)
        end, options?.method, options?.data, options?.headers)

        return Citizen.Await(p)
    end

    ---Returns all available player identifiers
    ---@param source number | string
    ---@param includeIp? boolean
    ---@return PlayerIdentifiers identifiers
    function m.getIdentifiers(source, includeIp)
        local identifiers = {}
        local stringSrc = source --[[@as string]]

        for i = 0, GetNumPlayerIdentifiers(stringSrc) - 1 do
            local key, value = string.strsplit(':', GetPlayerIdentifier(stringSrc, i))

            if key ~= 'ip' or includeIp then
                identifiers[key] = value
            end
        end

        return identifiers
    end

    ---Returns all available player tokens
    ---@param source number | string
    ---@return string[] tokens
    function m.getTokens(source)
        local tokens = {}
        local stringSrc = source --[[@as string]]

        for i = 0, GetNumPlayerTokens(stringSrc) - 1 do
            tokens[#tokens + 1] = GetPlayerToken(stringSrc, i)
        end

        return tokens
    end
else
    ---@param entity integer
    function m.deleteEntity(entity)
        if not DoesEntityExist(entity) then
            return
        end

        SetEntityAsMissionEntity(entity, false, true)
        DeleteEntity(entity)
    end
end

return m