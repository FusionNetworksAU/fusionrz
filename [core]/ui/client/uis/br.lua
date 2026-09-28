local function setBrHotbarVisible(visible)
    SendNUIMessage({ action = 'setBrHotbarVisible', data = visible })
end

exports('setBrHotbarVisible', setBrHotbarVisible)

local function setBrHotbarData(data)
    SendNUIMessage({ action = 'setBrHotbarData', data = data })
end

exports('setBrHotbarData', setBrHotbarData)

local function setBrMatchEndVisible(visible)
    SendNUIMessage({ action = 'setBrMatchEndVisible', data = visible })
end

exports('setBrMatchEndVisible', setBrMatchEndVisible)

local function setBrMatchEndData(data)
    SendNUIMessage({ action = 'setBrMatchEndData', data = data })
end

exports('setBrMatchEndData', setBrMatchEndData)

local function setBrGameHudVisible(visible)
    SendNUIMessage({ action = 'setBrGameHudVisible', data = visible })
end

exports('setBrGameHudVisible', setBrGameHudVisible)

local function setBrGameHudData(data)
    SendNUIMessage({ action = 'setBrGameHudData', data = data })
end

exports('setBrGameHudData', setBrGameHudData)

local function setBrSquadVisible(visible)
    SendNUIMessage({ action = 'setBrSquadVisible', data = visible })
end

exports('setBrSquadVisible', setBrSquadVisible)

local function setBrSquadData(data)
    SendNUIMessage({ action = 'setBrSquadData', data = data })
end

exports('setBrSquadData', setBrSquadData)

local function setBrAltimeterVisible(visible)
    SendNUIMessage({ action = 'setBrAltimeterVisible', data = visible })
end

exports('setBrAltimeterVisible', setBrAltimeterVisible)

local function setBrAltimeterData(data)
    SendNUIMessage({ action = 'setBrAltimeterData', data = data })
end

exports('setBrAltimeterData', setBrAltimeterData)
