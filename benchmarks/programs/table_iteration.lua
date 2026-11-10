local count = ...
local values = {}

for i = 1, 100 do
    values[i] = i
end

local total = 0
for _ = 1, math.max(1, math.floor(count / 100)) do
    for _, value in pairs(values) do
        total = total + value
    end
end

return total
