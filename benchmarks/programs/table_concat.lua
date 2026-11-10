local count = ...
local parts = {}

for i = 1, count do
    parts[i] = tostring(i % 10)
end

return #table.concat(parts)
