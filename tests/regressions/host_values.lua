return function(Rima)
    local expected = {
        {},
        nil,
        function() end,
        newproxy(),
        coroutine.create(function() end),
        false,
        nil,
        n = 7,
    }

    local function checkValues(direction, ...)
        local count = select("#", ...)
        assert(count == expected.n, direction .. " expected " .. expected.n .. " values, got " .. count)

        for index = 1, count do
            local actual = select(index, ...)
            assert(rawequal(actual, expected[index]), direction .. " changed value " .. index)
        end
    end

    local calls = 0
    local function echo(...)
        calls = calls + 1
        checkValues("host callback", ...)
        return ...
    end

    checkValues(
        "returned results",
        Rima.run(
            "return echo(...)",
            "@host-values",
            { echo = echo },
            unpack(expected, 1, expected.n)
        )
    )

    assert(calls == 1, "host callback ran " .. calls .. " times")
end
