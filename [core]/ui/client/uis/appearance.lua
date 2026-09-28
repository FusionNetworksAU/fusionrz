local appearance = exports.appearance

local isVisible = false

---@param toggle boolean
exports('setAppearanceVisible', function(toggle)
    SendNUIMessage({ action = 'setAppearanceVisible', data = toggle })
    SetNuiFocus(toggle, toggle)

    isVisible = toggle

    CreateThread(function()
        while isVisible do
            local coords = GetEntityCoords(cache.ped)

            local _, headZoneX, headZoneY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 0.7)
            local _, bodyZoneX, bodyZoneY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
            local _, shoeZoneX, shoeZoneY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z - 0.8)

            SendNUIMessage({
                action = 'updateCameraZones',
                data = {
                    head = { x = headZoneX, y = headZoneY },
                    body = { x = bodyZoneX, y = bodyZoneY },
                    shoes = { x = shoeZoneX, y = shoeZoneY },
                }
            })

            Wait(1000)
        end
    end)
end)

RegisterNUICallback('hideAppearance', function(_, cb)
    cb({})

    appearance:hideMenu()
end)

RegisterNUICallback('apprGetSettingsAndData', function(_, cb)
    local data = appearance:getSettingsAndData()

    cb(data)
end)

---@param data table
RegisterNUICallback('rotateCharacter', function(data, cb)
    SetEntityHeading(cache.ped, GetEntityHeading(cache.ped) + data.rotation)

    cb({})
end)

---@param camera string
RegisterNUICallback('apprSetCamera', function(camera, cb)
    appearance:setCamera(camera)

    cb({})
end)

RegisterNUICallback('apprTurnAround', function(_, cb)
    appearance:turnAround()

    cb({})
end)

---@param direction 'left' | 'right'
RegisterNUICallback('apprRotateCamera', function(direction, cb)
    appearance:rotateCamera(direction)

    cb({})
end)

---@param model string
RegisterNUICallback('apprChangeModel', function(model, cb)
    local data = appearance:changeModel(model)

    cb(data)
end)

---@param component table
RegisterNUICallback('apprChangeComponent', function(component, cb)
    local data = appearance:changeComponent(component, true)

    cb(data)
end)

---@param prop table
RegisterNUICallback('apprChangeProp', function(prop, cb)
    local data = appearance:changeProp(prop, true)

    cb(data)
end)

---@param headBlend table
RegisterNUICallback('apprChangeHeadBlend', function(headBlend, cb)
    appearance:changeHeadBlend(headBlend)

    cb({})
end)

---@param faceFeatures table
RegisterNUICallback('apprChangeFaceFeature', function(faceFeatures, cb)
    appearance:changeFaceFeature(faceFeatures)

    cb({})
end)

---@param headOverlays table
RegisterNUICallback('apprChangeHeadOverlay', function(headOverlays, cb)
    appearance:changeHeadOverlay(headOverlays)

    cb({})
end)

---@param hair table
RegisterNUICallback('apprChangeHair', function(hair, cb)
    local data = appearance:changeHair(hair)

    cb(data)
end)

---@param eyeColor number
RegisterNUICallback('apprChangeEyeColor', function(eyeColor, cb)
    appearance:changeEyeColor(eyeColor)

    cb({})
end)

---@param data table
RegisterNUICallback('apprApplyTattoo', function(data, cb)
    appearance:applyTattoo(data)

    cb({})
end)

---@param previewTattoo table
RegisterNUICallback('apprPreviewTattoo', function(previewTattoo, cb)
    appearance:previewTattoo(previewTattoo)

    cb({})
end)

---@param data table
RegisterNUICallback('apprDeleteTattoo', function(data, cb)
    appearance:deleteTattoo(data)

    cb({})
end)

---@param dataWearClothes table
RegisterNUICallback('apprWearClothes', function(dataWearClothes, cb)
    appearance:wearClothes(dataWearClothes)

    cb({})
end)

---@param clothes string
RegisterNUICallback('apprRemoveClothes', function(clothes, cb)
    appearance:removeClothes(clothes)

    cb({})
end)

RegisterNUICallback('resetAppearance', function(_, cb)
    local data = appearance:resetAppearance()

    cb(data)
end)

---@param appearanceData PedAppearance
RegisterNUICallback('saveAppearance', function(appearanceData, cb)
    appearance:saveAppearance(appearanceData)

    cb({})
end)

local FREEMODE_MALE = `mp_m_freemode_01`
local FREEMODE_FEMALE = `mp_f_freemode_01`

---@param model string|number|nil
---@return string|nil
local function normalizeAllowedFreemodeModel(model)
    if type(model) == 'string' then
        if model == 'mp_m_freemode_01' or model == 'mp_f_freemode_01' then
            return model
        end
    elseif type(model) == 'number' then
        if model == FREEMODE_MALE then
            return 'mp_m_freemode_01'
        elseif model == FREEMODE_FEMALE then
            return 'mp_f_freemode_01'
        end
    end

    return nil
end

---@param appearanceData PedAppearance | PedAppearanceExport
---@return PedAppearanceExport
local function filterExportAppearance(appearanceData)
    local filtered = {
        headBlend = appearanceData.headBlend,
        faceFeatures = appearanceData.faceFeatures,
        headOverlays = appearanceData.headOverlays,
        hair = appearanceData.hair,
        eyeColor = appearanceData.eyeColor,
    }

    local model = normalizeAllowedFreemodeModel(appearanceData.model)
    if model then
        filtered.model = model
    end

    return filtered
end

---@param current PedAppearance
---@param imported PedAppearanceExport
---@return PedAppearance
local function mergeImportAppearance(current, imported)
    local filtered = filterExportAppearance(imported)

    ---@type PedAppearance
    local merged = {
        model = filtered.model or current.model,
        headBlend = filtered.headBlend,
        faceFeatures = filtered.faceFeatures,
        headOverlays = filtered.headOverlays,
        hair = filtered.hair,
        eyeColor = filtered.eyeColor,
        components = current.components,
        props = current.props,
        tattoos = current.tattoos,
    }

    return merged
end

RegisterNUICallback('getJSONAppearance', function(_, cb)
    local appearanceData = appearance:getAppearance()

    cb(filterExportAppearance(appearanceData))
end)

---@param appearanceData PedAppearanceExport
RegisterNUICallback('setJSONAppearance', function(appearanceData, cb)
    local current = appearance:getAppearance()
    local merged = mergeImportAppearance(current, appearanceData)
    local modelChanged = merged.model ~= current.model

    appearance:setPlayerAppearance(merged)

    if modelChanged then
        local settingsAndData = appearance:getSettingsAndData()

        cb({
            appearanceData = settingsAndData.appearanceData,
            appearanceSettings = settingsAndData.appearanceSettings,
            collections = settingsAndData.collections,
            modelChanged = true,
        })
        return
    end

    cb({ appearanceData = merged })
end)