local function two()
    return nil, 2
end

local first = { nil, 2 }
local second = { 1, nil, 3 }
local dynamic = { 9, two() }
local keyed = { [3] = 1, two() }

return boundary(first), boundary(second), boundary(dynamic), boundary(keyed),
    dynamic[1], dynamic[2], dynamic[3], keyed[1], keyed[2], keyed[3]
