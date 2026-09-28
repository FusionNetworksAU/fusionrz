local currentTitle = nil
local isOpen = false

---@param data { title: string; subtitle: string }
local function setTextUI(data)
    currentTitle = data.title

    SendNUIMessage({ action = 'setTextUI', data = data })
    isOpen = true
end

exports('setTextUI', setTextUI)

local function hideTextUI()
    SendNUIMessage({ action = 'hideTextUI', data = true })
    currentTitle = nil
    isOpen = false
end

exports('hideTextUI', hideTextUI)

---@return boolean, string | nil
local function isTextUIOpen()
    return isOpen, currentTitle
end

exports('isTextUIOpen', isTextUIOpen)
