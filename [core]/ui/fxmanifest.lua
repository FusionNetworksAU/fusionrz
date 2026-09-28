fx_version 'cerulean'
game 'gta5'

name 'ui'
description 'UI for FUSIONRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

files {
    'config/shared.lua',
}

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    '@core/modules/playerdata.lua',
    'client/main.lua',
    'client/minimap_anchor.lua',
    'client/minimap.lua',
    'client/uis/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/uis/*.lua'
}

ui_page 'web/build/index.html'

files {
    'web/build/index.html',
    'web/build/**/*'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'