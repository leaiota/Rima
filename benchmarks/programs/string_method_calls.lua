local count = ...
local text = "Rima benchmark"
local length = #text
local total = 0

for i = 1, count do
    total = total + text:byte((i - 1) % length + 1)
end

return total
