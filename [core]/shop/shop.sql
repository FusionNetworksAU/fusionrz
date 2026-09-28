CREATE TABLE IF NOT EXISTS `shop_purchases` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`      INT UNSIGNED NOT NULL,
    `item_id`      VARCHAR(64)  NOT NULL,
    `price`        INT UNSIGNED NOT NULL,
    `creator_code` VARCHAR(32)  DEFAULT NULL,
    `gifted_to`    INT UNSIGNED DEFAULT NULL,
    `refunded_at`  DATETIME     DEFAULT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `shop_purchases_user` (`user_id`, `created_at`),
    KEY `shop_purchases_code` (`creator_code`, `created_at`),
    CONSTRAINT `shop_purchases_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `shop_gifts` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `sender_id`    INT UNSIGNED NOT NULL,
    `recipient_id` INT UNSIGNED NOT NULL,
    `item_id`      VARCHAR(64)  NOT NULL,
    `message`      VARCHAR(256) DEFAULT NULL,
    `claimed_at`   DATETIME     DEFAULT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `shop_gifts_recipient` (`recipient_id`, `claimed_at`),
    CONSTRAINT `shop_gifts_sender` FOREIGN KEY (`sender_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE,
    CONSTRAINT `shop_gifts_recipient` FOREIGN KEY (`recipient_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `shop_creator_codes` (
    `code`       VARCHAR(32)  NOT NULL,
    `user_id`    INT UNSIGNED NOT NULL,
    `share`      DECIMAL(5,4) NOT NULL DEFAULT 0.0500,
    `enabled`    TINYINT(1)   NOT NULL DEFAULT 1,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`code`),
    UNIQUE KEY `shop_creator_codes_user` (`user_id`),
    CONSTRAINT `shop_creator_codes_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
