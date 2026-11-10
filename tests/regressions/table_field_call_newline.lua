return function(Rima, compareProgram)
    local path = "tests/regressions/table_field_call_newline.lua"
    compareProgram([[
local function two()
    return nil, 2
end

local continued = {
    two
    ()
}

return continued[2]
]], path)

    local chunkName = "@" .. path
    local ok, message = pcall(Rima.parse, "return { two()\n    () }", chunkName)
    assert(not ok, "accepted an ambiguous chained call in a table field")

    local expected = chunkName .. ":2:5: ambiguous syntax"
    assert(tostring(message):find(expected, 1, true), "expected diagnostic " .. expected .. ", got " .. tostring(message))
end
