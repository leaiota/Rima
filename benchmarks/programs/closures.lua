local count = ...
local value = 0

local function update(amount)
    value = (value + amount) % 1000003
    return value
end

for i = 1, count do
    update(i)
end

return value
