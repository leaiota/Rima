local function checkCallResults(count, ok, ...)
    assert(ok, (...))
    assert(select("#", ...) == count and (...) == 1 and select(2, ...) == nil)
end

local function testMethodReceiver(Rima)
    local weak = setmetatable({}, { __mode = "v" })

    local function makeReceiver(method)
        local receiver = { pause = method }
        weak[1] = receiver
        return receiver
    end

    local methodCaller = Rima.run([[
return function(singleResult)
    local function pause(self)
        self = nil
        coroutine.yield()
        return 1, nil
    end

    local function forward(...)
        return ...
    end

    if singleResult then
        return forward((makeReceiver(pause):pause()))
    end
    return forward(makeReceiver(pause):pause())
end
]], nil, { coroutine = coroutine, makeReceiver = makeReceiver })

    for _, singleResult in ipairs({ false, true }) do
        local methodThread = coroutine.create(methodCaller)
        assert(coroutine.resume(methodThread, singleResult))
        assert(coroutine.status(methodThread) == "suspended")

        collectgarbage("collect")
        assert(weak[1] == nil, "suspended method call retained its temporary receiver")

        checkCallResults(singleResult and 1 or 2, coroutine.resume(methodThread))
        assert(coroutine.status(methodThread) == "dead")
    end
end

local function testNativeMethodReceiver(Rima)
    local weak = setmetatable({}, { __mode = "v" })

    local function makeReceiver()
        local receiver = { pause = coroutine.yield }
        weak[1] = receiver
        return receiver
    end

    local caller = Rima.run([[
return function(singleResult)
    local function forward(...)
        return ...
    end

    if singleResult then
        return forward((makeReceiver():pause()))
    end
    return forward(makeReceiver():pause())
end
]], nil, { makeReceiver = makeReceiver })

    local function checkYieldedReceiver(ok, receiver)
        assert(ok, receiver)
        assert(receiver ~= nil and receiver == weak[1], "native method changed its receiver")
    end

    for _, singleResult in ipairs({ false, true }) do
        local thread = coroutine.create(caller)
        checkYieldedReceiver(coroutine.resume(thread, singleResult))
        assert(coroutine.status(thread) == "suspended")

        collectgarbage("collect")
        assert(weak[1] == nil, "suspended native method retained its temporary receiver")

        checkCallResults(singleResult and 1 or 2, coroutine.resume(thread, 1, nil))
        assert(coroutine.status(thread) == "dead")
    end
end

return function(Rima)
    testMethodReceiver(Rima)
    testNativeMethodReceiver(Rima)
end
