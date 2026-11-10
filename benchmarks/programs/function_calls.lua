local count = ...

local function mix(a, b)
    return (a * 17 + b) % 1000003
end

local value = 1
for i = 1, count do
    value = mix(value, i)
end

return value
