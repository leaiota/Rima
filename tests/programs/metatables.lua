local writes = ""

local value = setmetatable({
    base = 4,
}, {
    __index = function(_, key)
        if key == "missing" then
            return 9
        end
    end,
    __newindex = function(_, key, item)
        writes = writes .. key .. "=" .. item
    end,
    __add = function(left, right)
        return left.base + right
    end,
})

value.answer = 7

return value.missing, value + 3, writes
