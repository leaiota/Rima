local count = ...
local values = {}

for i = 1, count do
    values[i] = i % 97
end

local total = 0
for i = 1, count do
    total = total + values[i]
end

return total
