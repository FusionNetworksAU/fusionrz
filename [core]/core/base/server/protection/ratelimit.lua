---Shared token bucket used by every detector in this folder.
---
---Server-side protection is only ever a backstop: a client that lies is
---caught here, but nothing here is a substitute for the server owning the
---decision in the first place.

---@class RateLimiter
---@field capacity integer
---@field refillPerSecond number
---@field buckets table<Source, { tokens: number, updatedAt: number }>
local RateLimiter = {}
RateLimiter.__index = RateLimiter

Core.RateLimiter = RateLimiter

---@param capacity integer burst allowance
---@param refillPerSecond number sustained rate
---@return RateLimiter
function RateLimiter.new(capacity, refillPerSecond)
    return setmetatable({
        capacity = capacity,
        refillPerSecond = refillPerSecond,
        buckets = {},
    }, RateLimiter)
end

---@param source Source
---@return boolean allowed
---@return number remaining
function RateLimiter:consume(source)
    local now = os.clock()
    local bucket = self.buckets[source]

    if not bucket then
        bucket = { tokens = self.capacity, updatedAt = now }
        self.buckets[source] = bucket
    end

    bucket.tokens = math.min(self.capacity, bucket.tokens + (now - bucket.updatedAt) * self.refillPerSecond)
    bucket.updatedAt = now

    if bucket.tokens < 1 then
        return false, bucket.tokens
    end

    bucket.tokens -= 1

    return true, bucket.tokens
end

---@param source Source
function RateLimiter:reset(source)
    self.buckets[source] = nil
end

---@type RateLimiter[]
local registry = {}

---@param capacity integer
---@param refillPerSecond number
---@return RateLimiter
function Core.createRateLimiter(capacity, refillPerSecond)
    local limiter = RateLimiter.new(capacity, refillPerSecond)

    registry[#registry + 1] = limiter

    return limiter
end

AddEventHandler('playerDropped', function()
    local source = source --[[@as Source]]

    for index = 1, #registry do
        registry[index]:reset(source)
    end
end)
