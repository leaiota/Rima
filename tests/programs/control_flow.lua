local total = 0
local index = 0

while index < 3 do
    index = index + 1
    total = total + index
end

repeat
    total = total + 1
until total == 7

for value = 1, 5, 2 do
    total = total + value
end

local function iter(limit, control)
    control = control + 1
    if control <= limit then
        return control, control * 2
    end
end

local generic = 0
for key, value in iter, 3, 0 do
    generic = generic + key + value
end

return total, generic
