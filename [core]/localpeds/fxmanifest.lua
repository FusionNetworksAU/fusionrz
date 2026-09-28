fx_version 'cerulean'
game 'gta5'

name 'localpeds'
description 'Local ped manager for TMFRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

client_scripts {
    '@ox_lib/init.lua',
    'client/main.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'