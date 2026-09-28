---@type string
CARD_METADATA_KEY = 'calling_card'
---@type string
---The FNRZ card, shipped with the UI at ui/web/build/cdn/ccs/fnrz_default.webp
---(the NUI serves every card from that folder, as ccs/<id>.<ext>).
DEFAULT_CARD_ID = 'fnrz_default'

---@param cardId string
---@return string extension
function GetCardImageExtension(cardId)
    if cardId:match('_g$') then
        return 'gif'
    end

    return 'webp'
end