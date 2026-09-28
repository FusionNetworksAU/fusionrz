local m = {}

---@param position vector3
---@param boxMin vector3
---@param boxMax vector3
function m.isPositionInAxisAlignedBox(position, boxMin, boxMax)
    return position.x >= boxMin.x and position.x <= boxMax.x and position.y >= boxMin.y and position.y < boxMax.y and position.z >= boxMin.z and position.z <= boxMax.z
end

---@param origin number
---@param direction number
---@param boxMin number
---@param boxMax number
---@return number
---@return number
local function computeSlapIntervalsForComponent(origin, direction, boxMin, boxMax)
    local tA = (boxMin - origin) * direction
    local tB = (boxMax - origin) * direction
    if tA <= tB then
        return tA, tB
    else
        return tB, tA
    end
end

---@param rayOrigin vector3
---@param direction vector3
---@param rayDistance number
---@param boxMin vector3
---@param boxMax vector3
---@return boolean doesIntercept
---@return number|nil enterDistance
---@return number|nil exitDistance
function m.doesRayInterceptAxisAlignedBox(rayOrigin, direction, rayDistance, boxMin, boxMax)
    local reciprocalDirection = 1 / direction

    local txMin, txMax = computeSlapIntervalsForComponent(rayOrigin.x, reciprocalDirection.x, boxMin.x, boxMax.x)
    if txMin == nil then return false end

    local tyMin, tyMax = computeSlapIntervalsForComponent(rayOrigin.y, reciprocalDirection.y, boxMin.y, boxMax.y)
    if tyMin == nil then return false end

    local tzMin, tzMax = computeSlapIntervalsForComponent(rayOrigin.z, reciprocalDirection.z, boxMin.z, boxMax.z)
    if tzMin == nil then return false end

    local tEnter = math.max(txMin, tyMin, tzMin)
    local tExit  = math.min(txMax, tyMax, tzMax)

    if tEnter <= tExit and tExit >= 0.0 and tEnter <= rayDistance then
        if tEnter < 0.0 then
            tEnter = 0.0
        end

        if tExit > rayDistance then
            tExit = rayDistance
        end

        return true, tEnter, tExit
    end

    return false
end

return m