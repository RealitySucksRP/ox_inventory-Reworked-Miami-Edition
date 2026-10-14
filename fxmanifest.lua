fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
game 'gta5'

-- Modified by RealitySucksRP on 2026-08-24.
-- Based on ox_inventory 2.47.9 by Overextended.
-- Changes include the Miami Edition NUI, item catalogue, shop stock, cash-as-item
-- support, weapon-component handling, and server-side inventory validation.
-- Distributed as complete source under GPL-3.0; see LICENSE and NOTICE.md.

name 'ox_inventory'
author 'Overextended; modified by RealitySucksRP'
version '2.47.9-rs-miami.8-qbx-production-guard'
description 'ox_inventory 2.47.9 RealitySucksRP Miami Edition with Qbox production security, persistence and transaction guards'

dependencies {
    '/server:6116',
    '/onesync',
    'oxmysql',
    'ox_lib',
}

shared_script '@ox_lib/init.lua'

ox_libs {
    'locale',
    'table',
    'math',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'init.lua'
}

client_script 'init.lua'

-- RealitySucksRP Miami Edition UI.
ui_page 'web/rs-ui/index.html'

files {
    'web/rs-ui/index.html',
    'web/rs-ui/main.css',
    'web/rs-ui/app.js',
    'web/rs-ui/image-aliases.js',
    'web/rs-ui/rs-ox-adapter.js',
    'web/rs-ui/vendor/*.js',
    'web/rs-ui/vendor/*.css',
    'web/rs-ui/art/*.webp',
    'client.lua',
    'server.lua',
    'locales/*.json',
    'web/images/*.png',
    'web/images/*.PNG',
    'web/images/*.webp',
    'modules/**/shared.lua',
    'modules/**/client.lua',
    'modules/bridge/**/client.lua',
    'data/*.lua',
}
