return function(_, compareProgram)
    compareProgram([[
local values = {10, 20}
local index = 1

local function changeIndex()
    index = 2
    return 7
end

values[index] = changeIndex()
assert(
    values[1] == 10 and values[2] == 7,
    "the RHS can change a live index"
)

values[2] = 20
index = 1
values[index], index = changeIndex(), 3
assert(
    values[1] == 7 and values[2] == 20 and index == 3,
    "a later assignment target freezes the index"
)

local writes = ""
local proxy = setmetatable({}, {
    __newindex = function(_, key)
        writes = writes .. key
    end,
})
proxy.left, proxy.right = 1, 2
assert(writes == "rightleft", "writes are performed right to left")

return values[1], values[2], index, writes

]], "tests/regressions/assignment_order.lua")
end
