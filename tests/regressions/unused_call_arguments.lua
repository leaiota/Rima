return function(Rima)
    local weak = setmetatable({}, { __mode = "v" })

    local function makeArgument()
        local argument = {}
        weak[1] = argument
        return argument
    end

    local caller = Rima.run([[
return function()
    local function pause()
        coroutine.yield()
    end

    pause(makeArgument())
end
]], nil, { coroutine = coroutine, makeArgument = makeArgument })

    local callerThread = coroutine.create(caller)
    assert(coroutine.resume(callerThread))
    assert(coroutine.status(callerThread) == "suspended")

    collectgarbage("collect")
    assert(weak[1] == nil, "suspended script call retained an unused argument")

    assert(coroutine.resume(callerThread))
    assert(coroutine.status(callerThread) == "dead")
end
