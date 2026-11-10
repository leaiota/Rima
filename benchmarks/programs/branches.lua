local count = ...
local value = 0

for i = 1, count do
    if i % 3 == 0 then
        value = value + i

    elseif i % 3 == 1 then
        value = value - i
    else
        value = value + 2
    end
end

return value
