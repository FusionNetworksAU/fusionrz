---@type CoreTestingModule
local m = {}

---@type TestSuite[]
local rootSuites = {}

---@type TestSuite[]
local suiteStack = {}

---@type (fun())[]?
local activeCleanups = nil

---@return TestSuite?
local function getCurrentSuite()
    return suiteStack[#suiteStack]
end

---@param value any
---@return string
local function serialize(value)
    local valueType = type(value)

    if valueType == 'string' then
        return ('%q'):format(value)
    end

    if valueType == 'table' then
        local ok, encoded = pcall(json.encode, value)
        if ok and encoded then
            return encoded
        end
    end

    return tostring(value)
end

---@param lhs any
---@param rhs any
---@return boolean
local function deepEqual(lhs, rhs)
    if lhs == rhs then
        return true
    end

    if type(lhs) ~= 'table' or type(rhs) ~= 'table' then
        return false
    end

    for key, value in pairs(lhs) do
        if not deepEqual(value, rhs[key]) then
            return false
        end
    end

    for key in pairs(rhs) do
        if lhs[key] == nil then
            return false
        end
    end

    return true
end

---@param expectation TestExpectation
---@param passed boolean
---@param description string
local function check(expectation, passed, description)
    if passed ~= expectation.negated then
        return
    end

    error(setmetatable({
        assertion = true,
        message = ('%s: expected %s %sto %s'):format(expectation.location or '?', serialize(expectation.value), expectation.negated and 'not ' or '', description),
    }, {
        __tostring = function(failure)
            return failure.message
        end,
    }), 0)
end

---@type table<string, fun(expectation: TestExpectation, ...: any)>
local matchers = {}

---@param self TestExpectation
---@param expected any
function matchers.toBe(self, expected)
    check(self, rawequal(self.value, expected) or self.value == expected, 'be ' .. serialize(expected))
end

---@param self TestExpectation
---@param expected any
function matchers.toEqual(self, expected)
    check(self, deepEqual(self.value, expected), 'equal ' .. serialize(expected))
end

---@param self TestExpectation
function matchers.toBeNil(self)
    check(self, self.value == nil, 'be nil')
end

---@param self TestExpectation
function matchers.toBeTruthy(self)
    check(self, self.value and true or false, 'be truthy')
end

---@param self TestExpectation
function matchers.toBeFalsy(self)
    check(self, not self.value, 'be falsy')
end

---@param self TestExpectation
---@param typeName string
function matchers.toBeType(self, typeName)
    check(self, type(self.value) == typeName, 'be of type ' .. typeName)
end

---@param self TestExpectation
---@param expected number
---@param tolerance number?
function matchers.toBeCloseTo(self, expected, tolerance)
    tolerance = tolerance or 1e-6
    check(self, type(self.value) == 'number' and math.abs(self.value - expected) <= tolerance, ('be within %s of %s'):format(tolerance, expected))
end

---@param self TestExpectation
---@param expected number
function matchers.toBeGreaterThan(self, expected)
    check(self, type(self.value) == 'number' and self.value > expected, 'be greater than ' .. serialize(expected))
end

---@param self TestExpectation
---@param expected number
function matchers.toBeGreaterThanOrEqual(self, expected)
    check(self, type(self.value) == 'number' and self.value >= expected, 'be greater than or equal to ' .. serialize(expected))
end

---@param self TestExpectation
---@param expected number
function matchers.toBeLessThan(self, expected)
    check(self, type(self.value) == 'number' and self.value < expected, 'be less than ' .. serialize(expected))
end

---@param self TestExpectation
---@param expected number
function matchers.toBeLessThanOrEqual(self, expected)
    check(self, type(self.value) == 'number' and self.value <= expected, 'be less than or equal to ' .. serialize(expected))
end

---@param self TestExpectation
---@param item any
function matchers.toContain(self, item)
    local found = false

    if type(self.value) == 'string' then
        found = self.value:find(tostring(item), 1, true) ~= nil
    elseif type(self.value) == 'table' then
        for _, value in pairs(self.value) do
            if deepEqual(value, item) then
                found = true
                break
            end
        end
    end

    check(self, found, 'contain ' .. serialize(item))
end

---@param self TestExpectation
---@param expected integer
function matchers.toHaveLength(self, expected)
    local valueType = type(self.value)
    local length = (valueType == 'string' or valueType == 'table') and #self.value or nil
    check(self, length == expected, 'have length ' .. serialize(expected))
end

---@param self TestExpectation
---@param pattern string?
function matchers.toThrow(self, pattern)
    local threw, err = false, nil

    if type(self.value) == 'function' then
        local ok, result = pcall(self.value)
        threw, err = not ok, result
    end

    local matches = threw and (not pattern or tostring(err):find(pattern, 1, true) ~= nil)
    check(self, matches, pattern and ('throw an error containing %s (got %s)'):format(serialize(pattern), serialize(tostring(err))) or 'throw an error')
end

local expectationMetatable = {}

---@param value any
---@param negated boolean
---@return TestExpectation
local function createExpectation(value, negated)
    local expectation = {
        value = value,
        negated = negated,
    }

    return setmetatable(expectation, expectationMetatable) --[[@as TestExpectation]]
end

---@param self TestExpectation
---@param key string
---@return any
expectationMetatable.__index = function(self, key)
    if key == 'never' then
        return createExpectation(rawget(self, 'value'), not rawget(self, 'negated'))
    end

    local matcher = matchers[key]
    if not matcher then
        return nil
    end

    return function(...)
        local info = debug.getinfo(2, 'Sl')
        rawset(self, 'location', info and ('%s:%s'):format(info.short_src, info.currentline) or '?')
        return matcher(self, ...)
    end
end

---@param value any
---@return TestExpectation
function m.expect(value)
    return createExpectation(value, false)
end

---@param name string
---@param fn fun()
function m.describe(name, fn)
    local parent = getCurrentSuite()

    ---@type TestSuite
    local suite = {
        name = name,
        parent = parent,
        suites = {},
        tests = {},
        beforeEach = {},
        afterEach = {},
    }

    if parent then
        parent.suites[#parent.suites + 1] = suite
    else
        rootSuites[#rootSuites + 1] = suite
    end

    suiteStack[#suiteStack + 1] = suite
    fn()
    suiteStack[#suiteStack] = nil
end

---@param name string
---@param fn fun()
function m.it(name, fn)
    local suite = assert(getCurrentSuite(), 'it() must be called inside describe()')
    suite.tests[#suite.tests + 1] = { name = name, fn = fn, skipped = false }
end

---@param name string
---@param fn fun()
function m.xit(name, fn)
    local suite = assert(getCurrentSuite(), 'xit() must be called inside describe()')
    suite.tests[#suite.tests + 1] = { name = name, fn = fn, skipped = true }
end

---@param fn fun()
function m.beforeEach(fn)
    local suite = assert(getCurrentSuite(), 'beforeEach() must be called inside describe()')
    suite.beforeEach[#suite.beforeEach + 1] = fn
end

---@param fn fun()
function m.afterEach(fn)
    local suite = assert(getCurrentSuite(), 'afterEach() must be called inside describe()')
    suite.afterEach[#suite.afterEach + 1] = fn
end

---@param tbl table
---@param key any
---@param value any
function m.stub(tbl, key, value)
    local cleanups = assert(activeCleanups, 'stub() must be called while a test is running')

    local original = rawget(tbl, key)
    local hadOriginal = original ~= nil

    tbl[key] = value

    cleanups[#cleanups + 1] = function()
        if hadOriginal then
            tbl[key] = original
        else
            tbl[key] = nil
        end
    end
end

---@param fn function?
---@return TestSpy
function m.spy(fn)
    local spy = { calls = {} }

    return setmetatable(spy, {
        __call = function(self, ...)
            self.calls[#self.calls + 1] = table.pack(...)

            if fn then
                return fn(...)
            end
        end,
    })
end

---@param err any
---@return TestFailure
local function errorHandler(err)
    if type(err) == 'table' and err.assertion then
        return { name = '', message = err.message }
    end

    return { name = '', message = tostring(err), traceback = debug.traceback('', 2) }
end

---@param suite TestSuite
---@return TestSuite[] chain leaf first
local function getSuiteChain(suite)
    ---@type TestSuite[]
    local chain = {}

    ---@type TestSuite?
    local current = suite
    while current do
        chain[#chain + 1] = current
        current = current.parent
    end

    return chain
end

---@param suite TestSuite
---@param test TestCase
---@param fullName string
---@param results TestRunResults
local function runTest(suite, test, fullName, results)
    results.total += 1

    if test.skipped then
        results.skipped += 1
        print(('  ^3SKIP^7 %s'):format(fullName))
        return
    end

    local chain = getSuiteChain(suite)

    ---@type (fun())[]
    local cleanups = {}
    activeCleanups = cleanups

    local startTime = GetGameTimer()

    local ok, failure = xpcall(function()
        for index = #chain, 1, -1 do
            local hooks = chain[index].beforeEach
            for hookIndex = 1, #hooks do
                hooks[hookIndex]()
            end
        end

        test.fn()
    end, errorHandler)

    local hooksOk, hookFailure = xpcall(function()
        for index = 1, #chain do
            local hooks = chain[index].afterEach
            for hookIndex = 1, #hooks do
                hooks[hookIndex]()
            end
        end
    end, errorHandler)

    for index = #cleanups, 1, -1 do
        pcall(cleanups[index])
    end

    activeCleanups = nil

    local durationMs = GetGameTimer() - startTime

    ---@type TestFailure?
    local finalFailure = (not ok and failure) or (not hooksOk and hookFailure) or nil

    if finalFailure then
        finalFailure.name = fullName
        results.failed += 1
        results.failures[#results.failures + 1] = finalFailure

        print(('  ^1FAIL^7 %s (%sms)\n       %s'):format(fullName, durationMs, finalFailure.message))
        if finalFailure.traceback then
            print(finalFailure.traceback)
        end
    else
        results.passed += 1
        print(('  ^2PASS^7 %s (%sms)'):format(fullName, durationMs))
    end
end

---@param suite TestSuite
---@param prefix string?
---@param filter string?
---@param results TestRunResults
local function runSuite(suite, prefix, filter, results)
    local suiteName = prefix and ('%s > %s'):format(prefix, suite.name) or suite.name

    for index = 1, #suite.tests do
        local test = suite.tests[index]
        local fullName = ('%s > %s'):format(suiteName, test.name)

        if not filter or fullName:lower():find(filter:lower(), 1, true) then
            runTest(suite, test, fullName, results)
        end
    end

    for index = 1, #suite.suites do
        runSuite(suite.suites[index], suiteName, filter, results)
    end
end

---@param filter string?
---@return TestRunResults
function m.run(filter)
    ---@type TestRunResults
    local results = {
        total = 0,
        passed = 0,
        failed = 0,
        skipped = 0,
        durationMs = 0,
        failures = {},
    }

    local startTime = GetGameTimer()

    print(('^3[core tests]^7 running %s'):format(filter and ('tests matching %q'):format(filter) or 'all tests'))

    for index = 1, #rootSuites do
        runSuite(rootSuites[index], nil, filter, results)
    end

    results.durationMs = GetGameTimer() - startTime

    local summaryColor = results.failed > 0 and '^1' or '^2'
    print(('%s[core tests]^7 %s passed, %s failed, %s skipped (%s total) in %sms'):format(summaryColor, results.passed, results.failed, results.skipped, results.total, results.durationMs))

    for index = 1, #results.failures do
        local failure = results.failures[index]
        print(('  ^1%s^7\n       %s'):format(failure.name, failure.message))
    end

    return results
end

---@return TestSuite[]
function m.getSuites()
    return rootSuites
end

function m.reset()
    table.wipe(rootSuites)
    table.wipe(suiteStack)
    activeCleanups = nil
end

return m
