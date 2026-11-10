return function(Rima)
    local cases = {
        { source = "local x = 1\n    return @", diagnostic = "2:12: unexpected symbol" },
        { source = "local x = 1\n    return )", diagnostic = "2:12: expression expected" },
        { source = "local x = 1\n    --[[\nunfinished", diagnostic = "2:5: unfinished long comment" },
        { source = "local x = 1\n    return [[\nunfinished", diagnostic = "2:12: unfinished long string" },
    }

    for _, case in ipairs(cases) do
        local ok, message = pcall(Rima.parse, case.source, "@parse-location")
        assert(not ok, "accepted malformed source " .. string.format("%q", case.source))

        local expected = "@parse-location:" .. case.diagnostic
        assert(
            tostring(message):find(expected, 1, true),
            "expected diagnostic " .. expected .. ", got " .. tostring(message)
        )
    end
end
