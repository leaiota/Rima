local function checkCallResults(count, ok, ...)
    assert(ok, (...))
    assert(select("#", ...) == count and (...) == 1 and select(2, ...) == nil)
end

local function testCallbackLifetime(Rima)
    local weak = setmetatable({}, { __mode = "v" })

    local function startCallback()
        local callback = Rima.run("return function() coroutine.yield() end", nil, { coroutine = coroutine })
        local thread = coroutine.create(callback)
        local argument = {}
        weak[1], weak[2] = argument, callback
        assert(coroutine.resume(thread, argument))
        return thread
    end

    local thread = startCallback()
    assert(coroutine.status(thread) == "suspended")

    collectgarbage("collect")
    assert(weak[1] == nil, "suspended callback retained an unused argument")
    assert(weak[2] ~= nil, "suspended callback was collected")

    assert(coroutine.resume(thread))
    assert(coroutine.status(thread) == "dead")

    collectgarbage("collect")
    assert(weak[2] == nil, "finished callback was retained")
end

local function testScriptFunctionLifetime(Rima)
    local weak = setmetatable({}, { __mode = "v" })

    local function remember(callback)
        weak[1] = callback
        return callback
    end

    local caller = Rima.run([[
return function(singleResult)
    local function makeCallback()
        return remember(function()
            coroutine.yield()
            return 1, nil
        end)
    end

    local function forward(...)
        return ...
    end

    if singleResult then
        return (makeCallback()())
    end
    return forward(makeCallback()())
end
]], nil, { coroutine = coroutine, remember = remember })

    for _, singleResult in ipairs({ false, true }) do
        local thread = coroutine.create(caller)

        assert(coroutine.resume(thread, singleResult))
        assert(coroutine.status(thread) == "suspended")

        collectgarbage("collect")
        assert(weak[1] ~= nil, "suspended script function was collected")

        checkCallResults(singleResult and 1 or 2, coroutine.resume(thread))
        assert(coroutine.status(thread) == "dead")

        collectgarbage("collect")
        assert(weak[1] == nil, "finished script function was retained")
    end
end

return function(Rima)
    testCallbackLifetime(Rima)
    testScriptFunctionLifetime(Rima)
end
