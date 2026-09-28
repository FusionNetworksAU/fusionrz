---@type CoreBroadcastModule
local m = {}

---@type Source[][]
local pool = {}
local poolSize = 0

---@return Source[]
local function acquire()
    if poolSize == 0 then
        return {}
    end

    local buffer = pool[poolSize]
    pool[poolSize] = nil
    poolSize -= 1

    return buffer
end

---@param buffer Source[]
local function release(buffer)
    table.wipe(buffer)

    poolSize += 1
    pool[poolSize] = buffer
end

---@param _ any
---@param key Source
---@return Source
function m.resolveKey(_, key)
    return key
end

---@generic K, T
---@param eventName string
---@param list table<K, T>
---@param resolve fun(element: T, key: K): Source?
---@param ... any
function m.triggerClientEvent(eventName, list, resolve, ...)
    local sources = acquire()
    local count = 0

    for key, element in pairs(list) do
        local source = resolve(element, key)
        if source then
            count += 1
            sources[count] = source
        end
    end

    if count > 0 then
        lib.triggerClientEvent(eventName, sources, ...)
    end

    release(sources)
end

return m
