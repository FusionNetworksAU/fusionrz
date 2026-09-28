local hasInit = false
local submenus = {}

local function mainThread()
    while WarMenu.IsAnyMenuOpened() do
        if WarMenu.Begin('devmenu') then
            WarMenu.End()
        end

        for _, menu in pairs(submenus) do
            if WarMenu.Button(menu.name) then
                menu.openCallback()
                while true do
                    local active = menu.callback()
                    if not active then
                        break
                    end
                    Wait(0)
                end
            end
        end

        Wait(0)
    end
end

RegisterNetEvent('devmenu:open', function()
    if WarMenu.IsAnyMenuOpened() then
        WarMenu.CloseMenu()
        return
    end

    if not hasInit then
        WarMenu.CreateMenu('devmenu', 'Developer Menu', 'Main Menu')
        hasInit = true
    end

    WarMenu.OpenMenu('devmenu')
    Citizen.CreateThread(mainThread)
end)

---@param name string
---@param callback fun()
---@param openCallback fun()
function RegisterSubMenu(name, callback, openCallback)
    table.insert(submenus, {
        name = name,
        resourceName = GetInvokingResource(),
        callback = callback,
        openCallback = openCallback,
    })
end

exports('RegisterSubMenu', RegisterSubMenu)

AddEventHandler('onResourceStop', function(resourceName)
    for index = #submenus, 1, -1 do
        local menu = submenus[index]
        if menu.resourceName == resourceName then
            table.remove(submenus, index)
        end
    end
end)