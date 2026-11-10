local count = ...
local value = 1

for i = 1, count do
    value = (value * 33 + i) % 1000003
end

return value
