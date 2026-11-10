local count = ...

local function values(a, ...)
    return a, select("#", ...), ...
end

local total = 0
for i = 1, count do
    local a, num, b = values(i, i + 1, i + 2)
    total = total + a + num + b
end

return total
