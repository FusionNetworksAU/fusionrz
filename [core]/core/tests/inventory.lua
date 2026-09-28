local testing = require 'modules.testing'

local describe = testing.describe
local it = testing.it
local expect = testing.expect
local stub = testing.stub
local beforeEach = testing.beforeEach

---@return CorePlayer
local function fakePlayer()
    return {
        source = 1,
        userId = 1,
        username = 'tester',
        license = 'license:test',
        coins = 0,
        metadata = {},
        weapons = {},
        playtime = 0,
        joinedAt = os.time(),
        identifiers = { license2 = 'license2:test' },
        tokens = {},
        dirty = false,
    } --[[@as CorePlayer]]
end

describe('inventory snapshot', function()
    beforeEach(function()
        stub(Core, 'getItem', function(itemId)
            return ({
                card_red = { id = 'card_red', category = 'calling_cards' },
                card_blue = { id = 'card_blue', category = 'calling_cards' },
                skin_gold = { id = 'skin_gold', category = 'weapons' },
            })[itemId]
        end)
    end)

    it('counts one entry per owned copy', function()
        stub(Core.db, 'getInventory', function()
            return {
                { id = 1, itemId = 'card_red', equipped = false, acquiredAt = 0 },
                { id = 2, itemId = 'card_red', equipped = false, acquiredAt = 0 },
            }
        end)

        local inventory = Core.refreshInventory(fakePlayer())

        expect(inventory.ownedTypeIds.card_red).toBe(2)
    end)

    it('drops an entry whose item is not in the catalogue', function()
        stub(Core.db, 'getInventory', function()
            return { { id = 1, itemId = 'gone', equipped = false, acquiredAt = 0 } }
        end)

        local inventory = Core.refreshInventory(fakePlayer())

        expect(inventory.ownedTypeIds.gone).toBeNil()
    end)

    it('records the equipped item against its category', function()
        stub(Core.db, 'getInventory', function()
            return { { id = 1, itemId = 'card_blue', equipped = true, acquiredAt = 0 } }
        end)

        local inventory = Core.refreshInventory(fakePlayer())

        expect(inventory.equipped.calling_cards).toBe('card_blue')
    end)

    it('lists each owned type once in the snapshot', function()
        stub(Core.db, 'getInventory', function()
            return {
                { id = 1, itemId = 'card_red', equipped = false, acquiredAt = 0 },
                { id = 2, itemId = 'card_red', equipped = false, acquiredAt = 0 },
                { id = 3, itemId = 'skin_gold', equipped = false, acquiredAt = 0 },
            }
        end)

        local player = fakePlayer()

        Core.refreshInventory(player)

        expect(Core.buildInventorySnapshot(player).typeIds).toHaveLength(2)
    end)

    it('survives a database error without throwing', function()
        stub(Core.db, 'getInventory', function()
            error('connection lost')
        end)

        local inventory = Core.refreshInventory(fakePlayer())

        expect(inventory.entries).toEqual({})
    end)
end)

describe('coin adjustment', function()
    it('refuses to spend more than the balance and leaves it alone', function()
        stub(Core.db, 'adjustCoins', function()
            return nil
        end)

        local player = setmetatable(fakePlayer(), { __index = Core.CorePlayer })
        local ok, balance = player:removeCoins(100, 'test')

        expect(ok).toBe(false)
        expect(balance).toBe(0)
    end)

    it('treats a zero delta as a no-op', function()
        local called = false

        stub(Core.db, 'adjustCoins', function()
            called = true

            return 0
        end)

        local player = setmetatable(fakePlayer(), { __index = Core.CorePlayer })

        expect(player:adjustCoins(0, 'test')).toBe(true)
        expect(called).toBe(false)
    end)
end)
