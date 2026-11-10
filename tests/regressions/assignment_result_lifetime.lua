return function(Rima)
    local weak = setmetatable({}, { __mode = "v" })
    local calls = 0

    local function makeExtra()
        calls = calls + 1
        local extra = {}
        weak[1] = extra
        return extra
    end

    local retained = {}
    local proxy = setmetatable({}, {
        __newindex = function(_, key, value)
            assert(value == 7, "extra RHS results must not change the assigned value")
            collectgarbage("collect")
            retained[key] = weak[1] ~= nil
        end,
    })

    Rima.run([[
local function makeValues()
    return 7, makeExtra()
end

proxy.expanded = makeValues()
proxy.discarded = 7, makeExtra()
proxy.explicit = 7, (makeExtra())
]], "@assignment-results", { proxy = proxy, makeExtra = makeExtra })

    assert(calls == 3, "all RHS calls must run")
    assert(retained.expanded == false, "assignment retained an unused expanded result")
    assert(retained.discarded == false, "assignment retained a fully discarded call result")
    assert(retained.explicit == true, "assignment released an explicit RHS result too early")
end
