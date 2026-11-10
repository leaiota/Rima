local thread = coroutine.create(function(value)
    local resumed = coroutine.yield(value + 1, nil)
    return resumed + 2
end)

local firstOk, first, hole = coroutine.resume(thread, 5)
local secondOk, second = coroutine.resume(thread, 10)

local iteratorThread = coroutine.create(function()
    local function iterator()
        coroutine.yield("unexpected yield")
    end

    for _ in iterator do end
end)

local iteratorOk, iteratorError = coroutine.resume(iteratorThread)
assert(iteratorOk == false, "generic for iterator must not yield")
assert(iteratorError:find("attempt to yield across metamethod/C-call boundary", 1, true))
assert(coroutine.status(iteratorThread) == "dead")

return firstOk, first, hole, secondOk, second, coroutine.status(thread)
