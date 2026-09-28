-- Base GTA guns sold in the shop (Weapons tab).
--
-- Each row's id is the weapon name in lower case, in category `weapons`: core
-- builds an item's permission as `<category>.<id>`, which is exactly the `ace`
-- core/data/weapons.lua gives that weapon. Buying `weapon_rpg` therefore
-- unlocks WEAPON_RPG in the Weapons menu, and nothing else.
--
-- Safe to run again: existing rows are updated in place, purchases are kept.

INSERT INTO `items` (`id`, `category`, `label`, `description`, `image`, `rarity`, `price`, `purchasable`, `enabled`, `sort_order`, `data`) VALUES
    ('weapon_pistol_mk2',        'weapons', 'Pistol MK2',            'Semi-automatic sidearm with mk2 upgrades.',            'weapons/weapon_pistol_mk2.webp',        'uncommon',   1800, 1, 1, 10,  NULL),
    ('weapon_revolver_mk2',      'weapons', 'Revolver MK2',          'Heavy revolver. Slow, hits hard.',                     'weapons/weapon_revolver_mk2.webp',      'uncommon',   1800, 1, 1, 11,  NULL),
    ('weapon_smg',               'weapons', 'SMG',                   'Fast-firing submachine gun.',                          'weapons/weapon_smg.webp',               'uncommon',   2500, 1, 1, 20,  NULL),
    ('weapon_assaultsmg',        'weapons', 'Assault SMG',           'SMG with a larger magazine and rifle-like handling.',  'weapons/weapon_assaultsmg.webp',        'uncommon',   2500, 1, 1, 21,  NULL),
    ('weapon_pumpshotgun',       'weapons', 'Pump Shotgun',          'Close-range pump-action shotgun.',                     'weapons/weapon_pumpshotgun.webp',       'rare',       3000, 1, 1, 30,  NULL),
    ('weapon_sawnoffshotgun',    'weapons', 'Sawed-Off Shotgun',     'Short and brutal at point-blank range.',               'weapons/weapon_sawnoffshotgun.webp',    'rare',       3000, 1, 1, 31,  NULL),
    ('weapon_dbshotgun',         'weapons', 'Double Barrel Shotgun', 'Two shells, one decision.',                            'weapons/weapon_dbshotgun.webp',         'rare',       3500, 1, 1, 32,  NULL),
    ('weapon_assaultshotgun',    'weapons', 'Assault Shotgun',       'Fully automatic shotgun.',                             'weapons/weapon_assaultshotgun.webp',    'rare',       4500, 1, 1, 33,  NULL),
    ('weapon_combatshotgun',     'weapons', 'Combat Shotgun',        'Semi-automatic tactical shotgun.',                     'weapons/weapon_combatshotgun.webp',     'rare',       4500, 1, 1, 34,  NULL),
    ('weapon_militaryrifle',     'weapons', 'Military Rifle',        'Hard-hitting service rifle.',                          'weapons/weapon_militaryrifle.webp',     'rare',       4000, 1, 1, 40,  NULL),
    ('weapon_precisionrifle',    'weapons', 'Precision Rifle',       'Bolt-action accuracy at range.',                       'weapons/weapon_precisionrifle.webp',    'epic',       5000, 1, 1, 41,  NULL),
    ('weapon_marksmanrifle_mk2', 'weapons', 'Marksman Rifle MK2',    'Semi-automatic marksman rifle with mk2 upgrades.',     'weapons/weapon_marksmanrifle_mk2.webp', 'epic',       5500, 1, 1, 42,  NULL),
    ('weapon_sniperrifle',       'weapons', 'Sniper Rifle',          'Long-range bolt-action sniper.',                       'weapons/weapon_sniperrifle.webp',       'epic',       6000, 1, 1, 43,  NULL),
    ('weapon_grenadelauncher',   'weapons', 'Grenade Launcher',      'Explosive rounds, indirect fire.',                     'weapons/weapon_grenadelauncher.webp',   'legendary',  9000, 1, 1, 50,  NULL),
    ('weapon_rpg',               'weapons', 'RPG',                   'Rocket launcher. Vehicles hate it.',                   'weapons/weapon_rpg.webp',               'legendary', 10000, 1, 1, 51,  NULL),
    ('weapon_minigun',           'weapons', 'Minigun',               'Six barrels. No subtlety.',                            'weapons/weapon_minigun.webp',           'mythical',  15000, 1, 1, 52,  NULL),
    ('weapon_grenade',           'weapons', 'Grenade',               'Standard frag grenade.',                               'weapons/weapon_grenade.webp',           'common',     750, 1, 1, 60,  NULL),
    ('weapon_pipebomb',          'weapons', 'Pipe Bomb',             'Improvised explosive.',                                'weapons/weapon_pipebomb.webp',          'common',     750, 1, 1, 61,  NULL),
    ('weapon_molotov',           'weapons', 'Molotov',               'Area denial in a bottle.',                             'weapons/weapon_molotov.webp',           'common',     750, 1, 1, 62,  NULL),
    ('weapon_stickybomb',        'weapons', 'Sticky Bomb',           'Remote-detonated charge that sticks to anything.',     'weapons/weapon_stickybomb.webp',        'common',     750, 1, 1, 63,  NULL),
    ('weapon_flare',             'weapons', 'Flare',                 'Lights up an area. Marks a position.',                 'weapons/weapon_flare.webp',             'common',     250, 1, 1, 64,  NULL)
ON DUPLICATE KEY UPDATE
    `category` = VALUES(`category`),
    `label` = VALUES(`label`),
    `description` = VALUES(`description`),
    `image` = VALUES(`image`),
    `rarity` = VALUES(`rarity`),
    `price` = VALUES(`price`),
    `purchasable` = VALUES(`purchasable`),
    `enabled` = VALUES(`enabled`),
    `sort_order` = VALUES(`sort_order`);
