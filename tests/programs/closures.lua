local value = 0

local function makeInc(step)
    return function()
        value = value + step
        return value
    end
end

local first = makeInc(2)
local second = makeInc(3)

return first(), second(), first(), value
