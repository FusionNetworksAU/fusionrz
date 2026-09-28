CREATE TABLE IF NOT EXISTS `users` (
    `userId`     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `username`   VARCHAR(64)  NOT NULL,
    `license`    VARCHAR(128) NOT NULL,
    `license2`   VARCHAR(128) DEFAULT NULL,
    `fivem`      VARCHAR(128) DEFAULT NULL,
    `discord`    VARCHAR(128) DEFAULT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`userId`),
    UNIQUE KEY `users_license` (`license`),
    KEY `users_license2` (`license2`),
    KEY `users_fivem` (`fivem`),
    KEY `users_discord` (`discord`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_profiles` (
    `user_id`    INT UNSIGNED NOT NULL,
    `country`    CHAR(2)      DEFAULT NULL,
    `avatar`     VARCHAR(256) DEFAULT NULL,
    `coins`      INT          NOT NULL DEFAULT 0,
    `metadata`   LONGTEXT     DEFAULT NULL,
    `playtime`   INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`),
    KEY `user_profiles_last_seen` (`last_seen`),
    CONSTRAINT `user_profiles_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_bans` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`    INT UNSIGNED DEFAULT NULL,
    `license`    VARCHAR(50)  NOT NULL,
    `token`      VARCHAR(128) DEFAULT NULL,
    `reason`     VARCHAR(512) NOT NULL,
    `expires_at` DATETIME     DEFAULT NULL,
    `staff`      VARCHAR(64)  DEFAULT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `user_bans_license` (`license`),
    KEY `user_bans_token` (`token`),
    KEY `user_bans_expires` (`expires_at`),
    CONSTRAINT `user_bans_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_identifiers` (
    `user_id`   INT UNSIGNED NOT NULL,
    `type`      VARCHAR(16)  NOT NULL,
    `value`     VARCHAR(128) NOT NULL,
    `last_seen` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`, `type`, `value`),
    KEY `user_identifiers_lookup` (`type`, `value`),
    CONSTRAINT `user_identifiers_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_hardware` (
    `user_id`     INT UNSIGNED NOT NULL,
    `fingerprint` VARCHAR(128) NOT NULL,
    `payload`     LONGTEXT     DEFAULT NULL,
    `first_seen`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`, `fingerprint`),
    KEY `user_hardware_fingerprint` (`fingerprint`),
    CONSTRAINT `user_hardware_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `items` (
    `id`          VARCHAR(64)  NOT NULL,
    `category`    VARCHAR(32)  NOT NULL,
    `label`       VARCHAR(128) NOT NULL,
    `description` VARCHAR(512) DEFAULT NULL,
    `image`       VARCHAR(256) DEFAULT NULL,
    `rarity`      VARCHAR(32)  DEFAULT NULL,
    `price`       INT UNSIGNED DEFAULT NULL,
    `purchasable` TINYINT(1)   NOT NULL DEFAULT 0,
    `enabled`     TINYINT(1)   NOT NULL DEFAULT 1,
    `sort_order`  INT          NOT NULL DEFAULT 0,
    `data`        LONGTEXT     DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `items_category` (`category`, `enabled`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `hand_items` (
    `id`         VARCHAR(64)  NOT NULL,
    `label`      VARCHAR(128) NOT NULL,
    `model`      VARCHAR(64)  NOT NULL,
    `bone`       INT          DEFAULT NULL,
    `offset_x`   FLOAT        DEFAULT NULL,
    `offset_y`   FLOAT        DEFAULT NULL,
    `offset_z`   FLOAT        DEFAULT NULL,
    `rotation_x` FLOAT        DEFAULT NULL,
    `rotation_y` FLOAT        DEFAULT NULL,
    `rotation_z` FLOAT        DEFAULT NULL,
    `enabled`    TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_inventory` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id` INT UNSIGNED NOT NULL,
    `item_id` VARCHAR(64) NOT NULL,
    `equipped` TINYINT(1) NOT NULL DEFAULT 0,
    `acquired_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `user_inventory_user` (`user_id`),
    KEY `user_inventory_item` (`item_id`),
    CONSTRAINT `user_inventory_user_fk` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_appearance` (
    `user_id`    INT UNSIGNED NOT NULL,
    `appearance` LONGTEXT     NOT NULL,
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`),
    CONSTRAINT `user_appearance_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

INSERT INTO `user_profiles` (`user_id`)
SELECT `userId` FROM `users`
WHERE `userId` NOT IN (SELECT `user_id` FROM `user_profiles`);
