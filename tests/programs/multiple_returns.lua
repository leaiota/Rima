local function values()
    return 1, nil, 3, nil
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local expanded = pack(values())
local collapsed = pack((values()))
local list = { 0, values() }

return expanded.n, expanded[1], expanded[2], expanded[3], expanded[4],
    collapsed.n, collapsed[1], list[1], list[2], list[3], list[4], list[5]
