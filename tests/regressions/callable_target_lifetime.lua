local function checkCallResults(count, ok, ...)
    assert(ok, (...))
    assert(select("#", ...) == count and (...) == 1 and select(2, ...) == nil)
end

return function(Rima)
    local weak = setmetatable({}, { __mode = "v" })

    local function makeCallable(method)
        local target = setmetatable({ marker = 1 }, { __call = method })
        weak[1] = target
        return target
    end

    local caller = Rima.run([[
return function(singleResult)
    local function pause(self)
        local marker = self.marker
        self = nil
        coroutine.yield()
        return marker, nil
    end

    local function forward(...)
        return ...
    end

    if singleResult then
        return forward((makeCallable(pause)()))
    end
    return forward(makeCallable(pause)())
end
]], nil, { coroutine = coroutine, makeCallable = makeCallable })

    for _, singleResult in ipairs({ false, true }) do
        local thread = coroutine.create(caller)

        assert(coroutine.resume(thread, singleResult))
        assert(coroutine.status(thread) == "suspended")

        collectgarbage("collect")
        assert(weak[1] == nil, "suspended call retained its temporary callable table")

        checkCallResults(singleResult and 1 or 2, coroutine.resume(thread))
        assert(coroutine.status(thread) == "dead")
    end
end
