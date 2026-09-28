fx_version 'cerulean'
game 'gta5'

name 'standalone-ramps'
author 'Syntax'
description 'Standalone 1v1 and 2v2 ramps with best-of-five matches and spectator isolation'
version '1.0.0'

lua54 'yes'

dependency '/onesync'

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}
