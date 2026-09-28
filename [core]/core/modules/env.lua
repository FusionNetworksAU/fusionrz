local m = {}

---@return string env
function m.getEnv()
    return GetConvar('env', 'production')
end

return m