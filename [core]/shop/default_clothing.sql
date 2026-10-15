-- Free vanilla GTA clothing every player gets in Profile > Clothing.
--
-- `free` in data makes every player own the row (shared/shop.lua Shop.owns),
-- and with no price and purchasable 0 it never shows in the store. Each row is
-- one component on the freemode ped: `component`, `drawable`, `texture`, plus
-- `extra` components put on with it.
--
-- Shirts are colourways of top 0, the same top the Default piece uses, worn
-- with arms 0 and undershirt 0 like Default: those three are made for each
-- other on both the male and female ped, so no gaps at the sleeves. Pants and
-- shoes are different vanilla pieces; the same drawable number is a different
-- piece on the female ped, which is why they are labelled by number rather
-- than described. A piece or colour a ped does not have is skipped on the
-- client (main.lua validComponents), not applied broken.
--
-- Safe to run again: existing rows are updated in place.

INSERT INTO `items` (`id`, `category`, `label`, `description`, `image`, `rarity`, `price`, `purchasable`, `enabled`, `sort_order`, `data`) VALUES
    ('free_shirt_01', 'clothing', 'Basic Tee 1',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1001, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":0,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_02', 'clothing', 'Basic Tee 2',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1002, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":1,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_03', 'clothing', 'Basic Tee 3',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1003, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":2,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_04', 'clothing', 'Basic Tee 4',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1004, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":3,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_05', 'clothing', 'Basic Tee 5',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1005, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":4,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_06', 'clothing', 'Basic Tee 6',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1006, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":5,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_07', 'clothing', 'Basic Tee 7',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1007, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":7,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_08', 'clothing', 'Basic Tee 8',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1008, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":8,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_09', 'clothing', 'Basic Tee 9',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1009, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":10,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),
    ('free_shirt_10', 'clothing', 'Basic Tee 10', 'Standard issue.', NULL, 'common', NULL, 0, 1, 1010, '{"free":true,"slot":"shirts","component":11,"drawable":0,"texture":11,"extra":[{"component":3,"drawable":0},{"component":8,"drawable":0}]}'),

    ('free_pants_01', 'clothing', 'Pants 1',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1101, '{"free":true,"slot":"pants","component":4,"drawable":1,"texture":0}'),
    ('free_pants_02', 'clothing', 'Pants 2',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1102, '{"free":true,"slot":"pants","component":4,"drawable":3,"texture":0}'),
    ('free_pants_03', 'clothing', 'Pants 3',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1103, '{"free":true,"slot":"pants","component":4,"drawable":4,"texture":0}'),
    ('free_pants_04', 'clothing', 'Pants 4',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1104, '{"free":true,"slot":"pants","component":4,"drawable":5,"texture":0}'),
    ('free_pants_05', 'clothing', 'Pants 5',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1105, '{"free":true,"slot":"pants","component":4,"drawable":7,"texture":0}'),
    ('free_pants_06', 'clothing', 'Pants 6',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1106, '{"free":true,"slot":"pants","component":4,"drawable":9,"texture":0}'),
    ('free_pants_07', 'clothing', 'Pants 7',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1107, '{"free":true,"slot":"pants","component":4,"drawable":10,"texture":0}'),
    ('free_pants_08', 'clothing', 'Pants 8',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1108, '{"free":true,"slot":"pants","component":4,"drawable":12,"texture":0}'),
    ('free_pants_09', 'clothing', 'Pants 9',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1109, '{"free":true,"slot":"pants","component":4,"drawable":24,"texture":0}'),
    ('free_pants_10', 'clothing', 'Pants 10', 'Standard issue.', NULL, 'common', NULL, 0, 1, 1110, '{"free":true,"slot":"pants","component":4,"drawable":26,"texture":0}'),

    ('free_shoes_01', 'clothing', 'Shoes 1',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1201, '{"free":true,"slot":"shoes","component":6,"drawable":1,"texture":0}'),
    ('free_shoes_02', 'clothing', 'Shoes 2',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1202, '{"free":true,"slot":"shoes","component":6,"drawable":3,"texture":0}'),
    ('free_shoes_03', 'clothing', 'Shoes 3',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1203, '{"free":true,"slot":"shoes","component":6,"drawable":4,"texture":0}'),
    ('free_shoes_04', 'clothing', 'Shoes 4',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1204, '{"free":true,"slot":"shoes","component":6,"drawable":7,"texture":0}'),
    ('free_shoes_05', 'clothing', 'Shoes 5',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1205, '{"free":true,"slot":"shoes","component":6,"drawable":8,"texture":0}'),
    ('free_shoes_06', 'clothing', 'Shoes 6',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1206, '{"free":true,"slot":"shoes","component":6,"drawable":9,"texture":0}'),
    ('free_shoes_07', 'clothing', 'Shoes 7',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1207, '{"free":true,"slot":"shoes","component":6,"drawable":10,"texture":0}'),
    ('free_shoes_08', 'clothing', 'Shoes 8',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1208, '{"free":true,"slot":"shoes","component":6,"drawable":12,"texture":0}'),
    ('free_shoes_09', 'clothing', 'Shoes 9',  'Standard issue.', NULL, 'common', NULL, 0, 1, 1209, '{"free":true,"slot":"shoes","component":6,"drawable":15,"texture":0}'),
    ('free_shoes_10', 'clothing', 'Shoes 10', 'Standard issue.', NULL, 'common', NULL, 0, 1, 1210, '{"free":true,"slot":"shoes","component":6,"drawable":25,"texture":0}')
ON DUPLICATE KEY UPDATE
    `category` = VALUES(`category`),
    `label` = VALUES(`label`),
    `description` = VALUES(`description`),
    `rarity` = VALUES(`rarity`),
    `price` = VALUES(`price`),
    `purchasable` = VALUES(`purchasable`),
    `enabled` = VALUES(`enabled`),
    `sort_order` = VALUES(`sort_order`),
    `data` = VALUES(`data`);
