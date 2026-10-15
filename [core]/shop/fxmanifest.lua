fx_version 'cerulean'
game 'gta5'

name 'shop'
description 'Shop backend for FusionRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

files {
    'config/data.lua',
    'config/shared.lua',
    'config/categories.lua',
    'config/preview.lua',
    'config/debug.lua',
    -- Clothing pictures from /clothingshots, loaded by the UI as
    -- https://cfx-nui-shop/thumbnails/<id>.webp.
    'thumbnails/*.webp',
}

shared_script '@ox_lib/init.lua'
server_scripts {
    'shared/clothing.lua',
    'shared/emote_audio.lua',
    'shared/emotes.lua',
    'shared/profile.lua',
    'shared/shop.lua',
    'shared/tattoos.lua',
}

client_script 'main.lua'
-- /clothingshots photographer (server/thumbnails.lua drives it).
client_script 'client/thumbnails.lua'
-- Shims for exports this base does not implement; see compat.lua.
client_script 'compat.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
    'server/debug/*.lua',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'

author 'server'
