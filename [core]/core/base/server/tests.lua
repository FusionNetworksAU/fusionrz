---@diagnostic disable: param-type-mismatch


local testing = require 'modules.testing'

local describe = testing.describe
local it = testing.it
local expect = testing.expect

---@param filter string?
---@return TestResults
function Core.runTests(filter)
    return testing.run(filter)
end

describe('username validation', function()
    it('rejects a name under the minimum length', function()
        local valid = Core.isUsernameShapeValid('ab')

        expect(valid).toBe(false)
    end)

    it('rejects a name over the maximum length', function()
        local valid = Core.isUsernameShapeValid(string.rep('a', Core.config.username.maxLength + 1))

        expect(valid).toBe(false)
    end)

    it('rejects punctuation', function()
        expect(Core.isUsernameShapeValid('bad name')).toBe(false)
        expect(Core.isUsernameShapeValid('bad-name')).toBe(false)
        expect(Core.isUsernameShapeValid('bad.name')).toBe(false)
    end)

    it('accepts letters, digits and underscores', function()
        expect(Core.isUsernameShapeValid('valid_name_09')).toBe(true)
    end)

    it('rejects a non-string', function()
        expect(Core.isUsernameShapeValid(nil)).toBe(false)
        expect(Core.isUsernameShapeValid(12345)).toBe(false)
    end)
end)

describe('country normalisation', function()
    it('upper-cases a known code', function()
        expect(Core.normaliseCountry('gb')).toBe('GB')
    end)

    it('returns nil for an unknown code', function()
        expect(Core.normaliseCountry('ZZ')).toBeNil()
    end)

    it('returns nil for a non-string', function()
        expect(Core.normaliseCountry(nil)).toBeNil()
    end)
end)

describe('weapon resolution', function()
    it('resolves a known name regardless of case', function()
        expect(Core.resolveWeaponId('weapon_appistol')).toBe('WEAPON_APPISTOL')
    end)

    it('resolves a hash back to its name', function()
        expect(Core.resolveWeaponId(joaat('WEAPON_APPISTOL'))).toBe('WEAPON_APPISTOL')
    end)

    it('returns nil for a weapon that is not in the catalogue', function()
        expect(Core.resolveWeaponId('WEAPON_NOT_REAL')).toBeNil()
    end)
end)

describe('weapon whitelist', function()
    local SOURCE = 9999

    it('allows everything when no whitelist is set', function()
        Core.resetWeaponWhitelist(SOURCE)

        expect(Core.isWeaponAllowed(SOURCE, 'WEAPON_APPISTOL')).toBe(true)
    end)

    it('allows only the listed weapons once set', function()
        Core.setWeaponWhitelist(SOURCE, { 'WEAPON_APPISTOL' })

        expect(Core.isWeaponAllowed(SOURCE, 'WEAPON_APPISTOL')).toBe(true)
        expect(Core.isWeaponAllowed(SOURCE, 'WEAPON_MOSIN')).toBe(false)

        Core.resetWeaponWhitelist(SOURCE)
    end)

    it('rejects an unknown weapon while a whitelist is active', function()
        Core.setWeaponWhitelist(SOURCE, { 'WEAPON_APPISTOL' })

        expect(Core.isWeaponAllowed(SOURCE, 'WEAPON_NOT_REAL')).toBe(false)

        Core.resetWeaponWhitelist(SOURCE)
    end)
end)

describe('item aces', function()
    it('builds an ace from the category and id', function()
        expect(Core.buildItemAce('weapons', 'skin_gold')).toBe('weapons.skin_gold')
    end)

    it('will not resolve an ace whose item is not in the catalogue', function()
        expect(Core.getItemIdByAce('weapons.not_a_real_item')).toBeNil()
    end)

    it('returns nil for a string with no dot in it', function()
        expect(Core.getItemIdByAce('nodot')).toBeNil()
    end)

    it('returns nil for a non-string', function()
        expect(Core.getItemIdByAce(nil)).toBeNil()
    end)
end)

describe('rate limiter', function()
    it('allows a burst up to capacity then refuses', function()
        local limiter = Core.RateLimiter.new(3, 0)

        expect(limiter:consume(1)).toBe(true)
        expect(limiter:consume(1)).toBe(true)
        expect(limiter:consume(1)).toBe(true)
        expect(limiter:consume(1)).toBe(false)
    end)

    it('tracks each source separately', function()
        local limiter = Core.RateLimiter.new(1, 0)

        expect(limiter:consume(1)).toBe(true)
        expect(limiter:consume(2)).toBe(true)
        expect(limiter:consume(1)).toBe(false)
    end)

    it('forgets a source on reset', function()
        local limiter = Core.RateLimiter.new(1, 0)

        limiter:consume(1)
        limiter:reset(1)

        expect(limiter:consume(1)).toBe(true)
    end)
end)

describe('ban messages', function()
    it('says permanent when there is no expiry', function()
        local message = Core.formatBanMessage({ id = 1, reason = 'cheating' })

        expect(message).toContain('permanently banned')
        expect(message).toContain('cheating')
    end)

    it('rounds a remaining duration up to whole hours', function()
        local message = Core.formatBanMessage({ id = 2, reason = 'x', expiresAt = os.time() + 3601 })

        expect(message).toContain('2 hour(s)')
    end)

    it('never reports zero hours for a ban that is still live', function()
        local message = Core.formatBanMessage({ id = 3, reason = 'x', expiresAt = os.time() + 5 })

        expect(message).toContain('1 hour(s)')
    end)
end)

describe('drop reasons', function()
    it('falls back to invalid_state for an unknown key', function()
        expect(Core.getDropReason('not_a_key')).toBe(Core.dropReasons.invalid_state)
    end)

    it('appends the detail when one is given', function()
        expect(Core.getDropReason('server_restart', 'scheduled')).toContain('scheduled')
    end)
end)
