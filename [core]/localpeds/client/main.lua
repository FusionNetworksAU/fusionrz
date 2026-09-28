---@param entity integer
local function cleanupPed(entity)
    if not DoesEntityExist(entity) then
        return
    end

    SetEntityAsMissionEntity(entity, false, true)
    DeleteEntity(entity)
end

---@param self CPoint
local function onEnter(self)
    if self.entity then
        return
    end

    local model = lib.requestModel(self.model)
    self.entity = CreatePed(1, model, self.coords.x, self.coords.y, self.coords.z, self.heading, false, true)
    SetModelAsNoLongerNeeded(model)

    lib.waitFor(function()
        if DoesEntityExist(self.entity) then
            return true
        end
    end)

    SetBlockingOfNonTemporaryEvents(self.entity, true)
    FreezeEntityPosition(self.entity, true)
    SetEntityInvincible(self.entity, true)
    SetPedDefaultComponentVariation(self.entity)

    if self.weapon then
        GiveWeaponToPed(self.entity, self.weapon.model, self.weapon.ammo or 5, true, true)
    end

    if self.scenario then
        local playEnter = self.scenario.playEnter == nil and true or self.scenario.playEnter

        ClearPedTasksImmediately(self.entity)
        TaskStartScenarioInPlace(self.entity, self.scenario.name, 0, playEnter)
    end

    if self.onSpawn then
        pcall(self.onSpawn, self.entity)
    end
end

---@param self CPoint
local function onExit(self)
    if not self.entity then
        return
    end

    if self.onDespawn then
        self.onDespawn(self.entity)
    end

    cleanupPed(self.entity)

    self.entity = nil
end

---@class PedScenario
---@field name string
---@field playEnter? boolean

---@class PedData
---@field model number | string
---@field coords vector4
---@field renderDistance number
---@field weapon? { ammo?: number, model: number; }
---@field scenario? PedScenario
---@field marker? MarkerProps
---@field onSpawn? fun(entity: integer)
---@field onDespawn? fun(entity: integer)
---@field onNearby? fun(self: CPoint)

---@param data PedData
local function createPedPoint(data)
    local point = lib.points.new({
        model = data.model,
        coords = data.coords.xyz,
        heading = data.coords.w,
        distance = data.renderDistance,
        weapon = data.weapon,
        scenario = data.scenario,
        onDespawn = data.onDespawn,
        onSpawn = data.onSpawn,
        onEnter = onEnter,
        onExit = onExit,
    })

    local marker = data.marker and lib.marker.new(data.marker)

    if marker?.draw or data.onNearby then
        function point:nearby()
            local entity = self.entity
            if not entity then
                return
            end

            if marker then
                pcall(marker.draw, marker)
            end

            if data.onNearby then
                pcall(data.onNearby, self)
            end
        end
    end

    local resource = GetInvokingResource() or cache.resource

    ---@param name string
    AddEventHandler('onResourceStop', function(name)
        if resource == name or cache.resource == name then
            if not point then
                return
            end

            if point.entity then
                cleanupPed(point.entity)
                point.entity = nil
            end

            point:remove()
        end
    end)

    return point
end

exports('CreatePedPoint', createPedPoint)