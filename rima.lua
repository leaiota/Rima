--============================================================
-- Rima: a pure Lua 5.1 AST interpreter.
--============================================================
-- Copyright (C) 2026 Ex
-- SPDX-License-Identifier: MPL-2.0
--
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file,
-- You can obtain one at https://mozilla.org/MPL/2.0/.

local Rima = {}

--============================================================
-- Utils
--============================================================

local DEFAULT_CHUNK_NAME = "@rima"
local MAX_SOURCE_SIZE = 8 * 1024 * 1024
local MAX_ACTIVE_LOCALS = 200           -- PUC Lua 5.1 LUAI_MAXVARS.
local MAX_UPVALUES = 60                 -- PUC Lua 5.1 LUAI_MAXUPVALUES.
local MAX_SYNTAX_DEPTH = 200            -- PUC Lua 5.1 LUAI_MAXCCALLS.
local INITIAL_SYNTAX_DEPTH = 2          -- PUC protected-parser call baseline.

local function failAt(chunkName, line, column, message, level)
    error(string.format("%s:%d:%d: %s", chunkName, line, column, message), (level or 1) + 1)
end

local function expectType(value, expected, name, level)
    if type(value) ~= expected then
        error(string.format("bad argument '%s' (%s expected, got %s)", name, expected, type(value)), (level or 1) + 1)
    end
end

local function finishNode(node, first, last)
    node.line = first.line
    node.column = first.column
    node.endLine = last.endLine
    return node
end

local function isDigit(character)
    return character ~= "" and character >= "0" and character <= "9"
end

local function isHexDigit(character)
    return isDigit(character)
        or (character >= "a" and character <= "f")
        or (character >= "A" and character <= "F")
end

local function isNameStart(character)
    return character ~= "" and (character == "_" or string.find(character, "^%a$") ~= nil)
end

local function isNamePart(character)
    return character ~= "" and (character == "_" or string.find(character, "^%w$") ~= nil)
end

local function packed(...)
    return { n = select("#", ...), ... }
end

local function unpackPacked(values, first, last)
    first = first or 1
    last = last or values.n

    if first > last then
        return
    end

    -- Return full batches before using host unpack, which limits its result count.
    if last - first >= 63 then
        return values[first], values[first + 1], values[first + 2], values[first + 3],
            values[first + 4], values[first + 5], values[first + 6], values[first + 7],
            values[first + 8], values[first + 9], values[first + 10], values[first + 11],
            values[first + 12], values[first + 13], values[first + 14], values[first + 15],
            values[first + 16], values[first + 17], values[first + 18], values[first + 19],
            values[first + 20], values[first + 21], values[first + 22], values[first + 23],
            values[first + 24], values[first + 25], values[first + 26], values[first + 27],
            values[first + 28], values[first + 29], values[first + 30], values[first + 31],
            values[first + 32], values[first + 33], values[first + 34], values[first + 35],
            values[first + 36], values[first + 37], values[first + 38], values[first + 39],
            values[first + 40], values[first + 41], values[first + 42], values[first + 43],
            values[first + 44], values[first + 45], values[first + 46], values[first + 47],
            values[first + 48], values[first + 49], values[first + 50], values[first + 51],
            values[first + 52], values[first + 53], values[first + 54], values[first + 55],
            values[first + 56], values[first + 57], values[first + 58], values[first + 59],
            values[first + 60], values[first + 61], values[first + 62], values[first + 63],
            unpackPacked(values, first + 64, last)
    end

    return unpack(values, first, last)
end

local function binaryValue(operator, left, right)
    if operator == "+" then
        return left + right

    elseif operator == "-" then
        return left - right

    elseif operator == "*" then
        return left * right

    elseif operator == "/" then
        return left / right

    elseif operator == "%" then
        return left % right

    elseif operator == "^" then
        return left ^ right

    elseif operator == ".." then
        return left .. right

    elseif operator == "==" then
        return left == right

    elseif operator == "~=" then
        return left ~= right

    elseif operator == "<" then
        return left < right

    elseif operator == "<=" then
        return left <= right

    elseif operator == ">" then
        return right < left

    elseif operator == ">=" then
        return right <= left
    end
end

--============================================================
-- Lexer
--============================================================

local KEYWORDS = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local ESCAPES = {
    a = "\a",
    b = "\b",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
    v = "\v",
    ["\\"] = "\\",
    ['"'] = '"',
    ["'"] = "'",
}

local SYMBOLS = {
    ["+"] = true,
    ["-"] = true,
    ["*"] = true,
    ["/"] = true,
    ["%"] = true,
    ["^"] = true,
    ["=="] = true,
    ["~="] = true,
    ["<="] = true,
    [">="] = true,
    ["<"] = true,
    [">"] = true,
    ["("] = true,
    [")"] = true,
    ["{"] = true,
    ["}"] = true,
    ["["] = true,
    ["]"] = true,
    ["#"] = true,
    ["="] = true,
    [";"] = true,
    [":"] = true,
    [","] = true,
    ["."] = true,
    [".."] = true,
    ["..."] = true,
}

local Lexer = {}
Lexer.__index = Lexer

function Lexer.new(source, chunkName)
    return setmetatable({
        source = source,
        chunkName = chunkName,
        index = 1,
        line = 1,
        column = 1,
        tokens = {},
    }, Lexer)
end

function Lexer:peek(offset)
    local index = self.index + (offset or 0)
    return string.sub(self.source, index, index)
end

function Lexer:advance()
    local character = self:peek()

    if character == "" then
        return ""
    end

    self.index = self.index + 1

    if character == "\r" or character == "\n" then
        local following = self:peek()
        if (character == "\r" and following == "\n") or (character == "\n" and following == "\r") then
            self.index = self.index + 1
        end

        self.line = self.line + 1
        self.column = 1
        return "\n"
    end

    self.column = self.column + 1
    return character
end

function Lexer:location()
    return {
        line = self.line,
        column = self.column,
    }
end

function Lexer:errorAt(line, column, message)
    failAt(self.chunkName, line, column, message, 2)
end

function Lexer:addToken(kind, value, start)
    self.tokens[#self.tokens + 1] = {
        kind = kind,
        value = value,
        line = start.line,
        column = start.column,
        endLine = self.line,
    }
end

function Lexer:longDelimiter(bracket)
    if self:peek() ~= bracket then
        return nil
    end

    local offset = 1

    while self:peek(offset) == "=" do
        offset = offset + 1
    end

    if self:peek(offset) == bracket then
        return offset - 1, false
    end

    return nil, offset > 1
end

function Lexer:consumeLong(level, start, collect)
    local width = level + 2
    for _ = 1, width do
        self:advance()
    end

    if self:peek() == "\n" or self:peek() == "\r" then
        self:advance()
    end

    local pieces = {}
    while true do
        local character = self:peek()

        if character == "" then
            local message = collect and "unfinished long string" or "unfinished long comment"
            self:errorAt(start.line, start.column, message)
        end

        if level == 0 and character == "[" and self:peek(1) == "[" then
            self:errorAt(self.line, self.column, "nesting of [[...]] is deprecated")
        end

        if character == "]" and self:longDelimiter("]") == level then
            for _ = 1, width do
                self:advance()
            end
            break
        end

        local consumed = self:advance()
        if collect then
            pieces[#pieces + 1] = consumed
        end
    end

    if collect then
        return table.concat(pieces)
    end
end

function Lexer:skipWhitespaceAndComments()
    while true do
        local character = self:peek()

        if character ~= "" and string.find(character, "^%s$") then
            self:advance()

        elseif character == "-" and self:peek(1) == "-" then
            local start = self:location()
            self:advance()
            self:advance()

            local level = self:longDelimiter("[")
            if level ~= nil then
                self:consumeLong(level, start, false)
            else
                while self:peek() ~= "" and self:peek() ~= "\r" and self:peek() ~= "\n" do
                    self:advance()
                end
            end
        else
            return
        end
    end
end

function Lexer:scanName(start, startIndex)
    while isNamePart(self:peek()) do
        self:advance()
    end

    local raw = string.sub(self.source, startIndex, self.index - 1)
    if KEYWORDS[raw] then
        self:addToken(raw, nil, start)
    else
        self:addToken("name", raw, start)
    end
end

function Lexer:scanNumber(start, startIndex)
    local isHex = false
    local hasExponent = false

    if self:peek() == "0" and (self:peek(1) == "x" or self:peek(1) == "X") then
        isHex = true
        self:advance()
        self:advance()

        if not isHexDigit(self:peek()) then
            self:errorAt(start.line, start.column, "malformed number")
        end

        while isHexDigit(self:peek()) do
            self:advance()
        end
    else
        if self:peek() == "." then
            self:advance()
        end

        while isDigit(self:peek()) do
            self:advance()
        end

        if self:peek() == "." and self:peek(1) ~= "." then
            self:advance()

            while isDigit(self:peek()) do
                self:advance()
            end
        end

        if self:peek() == "e" or self:peek() == "E" then
            hasExponent = true
            self:advance()

            if self:peek() == "+" or self:peek() == "-" then
                self:advance()
            end

            if not isDigit(self:peek()) then
                self:errorAt(start.line, start.column, "malformed number")
            end

            while isDigit(self:peek()) do
                self:advance()
            end
        end
    end

    -- An extra dot in the mantissa makes the number malformed in Lua 5.1.
    -- After the exponent, '..' can start the next token.
    if isNamePart(self:peek()) or (not isHex and not hasExponent and self:peek() == ".") then
        self:errorAt(start.line, start.column, "malformed number")
    end

    local raw = string.sub(self.source, startIndex, self.index - 1)
    local value = tonumber(raw)

    if value == nil and not isHex then
        -- Lua source always uses '.', while the host's numeric conversion uses its current locale.
        -- Formatting an exact fraction reveals that separator without changing the locale or depending on the os library.
        local point = string.find(raw, ".", 1, true)
        if point then
            local separator = string.sub(string.format("%.1f", 0.5), 2, -2)
            value = tonumber(string.sub(raw, 1, point - 1) .. separator .. string.sub(raw, point + 1))
        end
    end

    if value == nil then
        self:errorAt(start.line, start.column, "malformed number")
    end

    self:addToken("number", value, start)
end

function Lexer:scanShortString(start)
    local quote = self:advance()
    local pieces = {}

    while true do
        local character = self:peek()

        if character == "" then
            self:errorAt(start.line, start.column, "unfinished string")

        elseif character == "\r" or character == "\n" then
            self:errorAt(self.line, self.column, "unfinished string")

        elseif character == quote then
            self:advance()
            break

        elseif character ~= "\\" then
            pieces[#pieces + 1] = self:advance()
        else
            self:advance()
            local escaped = self:peek()

            if escaped == "" then
                self:errorAt(start.line, start.column, "unfinished string")

            elseif isDigit(escaped) then
                local first = self.index
                for _ = 1, 3 do
                    if not isDigit(self:peek()) then
                        break
                    end
                    self:advance()
                end

                local byte = tonumber(string.sub(self.source, first, self.index - 1))
                if byte > 255 then
                    self:errorAt(self.line, self.column, "escape sequence too large")
                end

                pieces[#pieces + 1] = string.char(byte)

            else
                local value = self:advance()
                pieces[#pieces + 1] = ESCAPES[value] or value
            end
        end
    end

    self:addToken("string", table.concat(pieces), start)
end

function Lexer:scanSymbol(start)
    local kind = self:advance()
    local second = self:peek()

    if kind == "." and second == "." then
        self:advance()
        kind = ".."

        if self:peek() == "." then
            self:advance()
            kind = "..."
        end

    elseif (kind == "=" or kind == "~" or kind == "<" or kind == ">") and second == "=" then
        self:advance()
        kind = kind .. "="
    end

    if not SYMBOLS[kind] then
        self:errorAt(start.line, start.column, string.format("unexpected symbol '%s'", kind))
    end

    self:addToken(kind, nil, start)
end

function Lexer:run()
    while true do
        self:skipWhitespaceAndComments()

        local start = self:location()
        local startIndex = self.index
        local character = self:peek()

        if character == "" then
            self:addToken("eof", nil, start)
            return self.tokens

        elseif isNameStart(character) then
            self:scanName(start, startIndex)

        elseif isDigit(character) or (character == "." and isDigit(self:peek(1))) then
            self:scanNumber(start, startIndex)

        elseif character == "\"" or character == "'" then
            self:scanShortString(start)

        elseif character == "[" then
            local level, invalid = self:longDelimiter("[")

            if invalid then
                self:errorAt(start.line, start.column, "invalid long string delimiter")

            elseif level ~= nil then
                local value = self:consumeLong(level, start, true)
                self:addToken("string", value, start)
            else
                self:scanSymbol(start)
            end
        else
            self:scanSymbol(start)
        end
    end
end

local function tokenize(source, chunkName)
    return Lexer.new(source, chunkName):run()
end

--============================================================
-- Parser
--============================================================

local BINARY_PRIORITY = {
    ["or"] = { 1, 1 },
    ["and"] = { 2, 2 },
    ["<"] = { 3, 3 },
    [">"] = { 3, 3 },
    ["<="] = { 3, 3 },
    [">="] = { 3, 3 },
    ["~="] = { 3, 3 },
    ["=="] = { 3, 3 },
    [".."] = { 5, 4 },
    ["+"] = { 6, 6 },
    ["-"] = { 6, 6 },
    ["*"] = { 7, 7 },
    ["/"] = { 7, 7 },
    ["%"] = { 7, 7 },
    ["^"] = { 10, 9 },
}

local UNARY_PRIORITY = 8

local UNARY_OPERATORS = {
    ["not"] = true,
    ["-"] = true,
    ["#"] = true,
}

local BLOCK_TERMINATORS = {
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["until"] = true,
    ["eof"] = true,
}

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens, chunkName)
    return setmetatable({
        tokens = tokens,
        chunkName = chunkName,
        index = 1,
        varargAllowed = true,
        syntaxDepth = INITIAL_SYNTAX_DEPTH,
    }, Parser)
end

function Parser:current()
    return self.tokens[self.index]
end

function Parser:previous()
    return self.tokens[self.index - 1] or self.tokens[1]
end

function Parser:peek(offset)
    return self.tokens[self.index + (offset or 0)] or self.tokens[#self.tokens]
end

function Parser:check(kind)
    return self:current().kind == kind
end

function Parser:advance()
    local token = self:current()
    if token.kind ~= "eof" then
        self.index = self.index + 1
    end
    return token
end

function Parser:match(kind)
    if self:check(kind) then
        return self:advance()
    end
    return nil
end

function Parser:errorAt(token, message)
    failAt(self.chunkName, token.line, token.column, message, 2)
end

function Parser:consume(kind, message)
    if self:check(kind) then
        return self:advance()
    end
    self:errorAt(self:current(), message or ("'" .. kind .. "' expected"))
end

function Parser:enterSyntax(token)
    self.syntaxDepth = self.syntaxDepth + 1
    if self.syntaxDepth > MAX_SYNTAX_DEPTH then
        self:errorAt(token, "syntax nesting limit exceeded")
    end
end

function Parser:leaveSyntax()
    self.syntaxDepth = self.syntaxDepth - 1
end

function Parser:literal(value, literalKind, token)
    return finishNode({
        kind = "Literal",
        value = value,
        literalKind = literalKind,
    }, token, token)
end

function Parser:nameExpression(token)
    return finishNode({
        kind = "Name",
        name = token.value,
    }, token, token)
end

function Parser:nameDeclaration(token)
    return finishNode({
        kind = "NameDeclaration",
        name = token.value,
    }, token, token)
end

function Parser:parseExpressionList()
    local expressions = { self:parseExpression() }
    while self:match(",") do
        expressions[#expressions + 1] = self:parseExpression()
    end
    return expressions
end

function Parser:parseTable()
    local first = self:consume("{")
    local fields = {}

    while not self:check("}") do
        local field
        local fieldFirst = self:current()
        local lookahead = fieldFirst.kind == "name" and self:peek(1)

        if self:match("[") then
            local key = self:parseExpression()
            self:consume("]")
            self:consume("=")

            local value = self:parseExpression()

            field = finishNode({
                kind = "RecordField",
                key = key,
                value = value,
            }, fieldFirst, value)

        elseif lookahead and lookahead.kind == "=" then
            local name = self:advance()
            self:advance()

            local value = self:parseExpression()
            local key = self:literal(name.value, "string", name)

            field = finishNode({
                kind = "RecordField",
                key = key,
                value = value,
            }, name, value)
        else
            if lookahead and lookahead.kind == "(" then
                -- PUC Lua 5.1's field lookahead advances the line used for this call.
                lookahead.allowNewlineBeforeCall = true
            end
            local value = self:parseExpression()

            field = finishNode({
                kind = "ListField",
                value = value,
            }, value, value)
        end

        fields[#fields + 1] = field

        if not self:match(",") and not self:match(";") then
            break
        end
    end

    local last = self:consume("}")

    return finishNode({
        kind = "Table",
        fields = fields,
    }, first, last)
end

function Parser:parseArguments(previousEndLine)
    local token = self:current()
    if token.kind == "(" and token.line > previousEndLine and not token.allowNewlineBeforeCall then
        self:errorAt(token, "ambiguous syntax (function call x new statement)")
    end

    if self:match("(") then
        local arguments = {}
        if not self:check(")") then
            arguments = self:parseExpressionList()
        end
        local last = self:consume(")")
        return arguments, last

    elseif self:check("{") then
        local argument = self:parseTable()
        return { argument }, argument

    elseif self:check("string") then
        local token = self:advance()
        local argument = self:literal(token.value, "string", token)
        return { argument }, argument
    end

    self:errorAt(self:current(), "function arguments expected")
end

function Parser:parsePrefixExpression()
    local expression

    if self:check("name") then
        expression = self:nameExpression(self:advance())

    elseif self:match("(") then
        local first = self:previous()
        local inner = self:parseExpression()
        local last = self:consume(")")

        expression = finishNode({
            kind = "Paren",
            expression = inner,
        }, first, last)
    else
        self:errorAt(self:current(), "expression expected")
    end

    while true do
        if self:match("[") then
            local key = self:parseExpression()
            local last = self:consume("]")

            expression = finishNode({
                kind = "Index",
                base = expression,
                key = key,
            }, expression, last)

        elseif self:match(".") then
            local name = self:consume("name", "field name expected")
            local key = self:literal(name.value, "string", name)

            expression = finishNode({
                kind = "Index",
                base = expression,
                key = key,
            }, expression, name)

        elseif self:match(":") then
            local name = self:consume("name", "method name expected")
            local arguments, last = self:parseArguments(name.endLine)

            expression = finishNode({
                kind = "MethodCall",
                base = expression,
                method = name.value,
                arguments = arguments,
            }, expression, last)

        elseif self:check("(") or self:check("{") or self:check("string") then
            local arguments, last = self:parseArguments(expression.endLine)

            expression = finishNode({
                kind = "Call",
                callee = expression,
                arguments = arguments,
            }, expression, last)
        else
            return expression
        end
    end
end

function Parser:parseFunctionBody(first, method)
    self:consume("(")

    local parameters = {}
    local isVararg = false

    if not self:check(")") then
        repeat
            if self:match("...") then
                isVararg = true
                break
            end

            local name = self:consume("name", "parameter name expected")
            parameters[#parameters + 1] = self:nameDeclaration(name)

        until not self:match(",")
    end
    self:consume(")")

    if method then
        local selfParameter = finishNode({
            kind = "NameDeclaration",
            name = "self",
        }, first, first)

        table.insert(parameters, 1, selfParameter)
    end

    local previousVararg = self.varargAllowed
    self.varargAllowed = isVararg

    local body = self:parseBlock({
        ["end"] = true,
    })
    local last = self:consume("end")

    self.varargAllowed = previousVararg

    return finishNode({
        kind = "Function",
        parameters = parameters,
        isVararg = isVararg,
        body = body,
    }, first, last)
end

function Parser:parseSimpleExpression()
    local token = self:current()

    if self:match("nil") then
        return self:literal(nil, "nil", token)

    elseif self:match("false") then
        return self:literal(false, "boolean", token)

    elseif self:match("true") then
        return self:literal(true, "boolean", token)

    elseif self:match("number") then
        return self:literal(token.value, "number", token)

    elseif self:match("string") then
        return self:literal(token.value, "string", token)

    elseif self:match("...") then
        if not self.varargAllowed then
            self:errorAt(token, "cannot use '...' outside a vararg function")
        end

        return finishNode({
            kind = "Vararg",
        }, token, token)

    elseif self:match("function") then
        return self:parseFunctionBody(token, false)

    elseif self:check("{") then
        return self:parseTable()

    elseif self:check("name") or self:check("(") then
        return self:parsePrefixExpression()
    end

    self:errorAt(token, "expression expected")
end

function Parser:parseSubexpression(limit)
    self:enterSyntax(self:current())

    local expression
    local token = self:current()

    if UNARY_OPERATORS[token.kind] then
        self:advance()
        local operand = self:parseSubexpression(UNARY_PRIORITY)

        expression = finishNode({
            kind = "Unary",
            operator = token.kind,
            expression = operand,
        }, token, operand)
    else
        expression = self:parseSimpleExpression()
    end

    while true do
        token = self:current()

        local priority = BINARY_PRIORITY[token.kind]
        if not priority or priority[1] <= limit then
            break
        end

        self:advance()
        local right = self:parseSubexpression(priority[2])

        expression = finishNode({
            kind = "Binary",
            operator = token.kind,
            left = expression,
            right = right,
        }, expression, right)
    end

    self:leaveSyntax()
    return expression
end

function Parser:parseExpression()
    return self:parseSubexpression(0)
end

function Parser:parseDoStatement()
    local first = self:consume("do")
    local body = self:parseBlock({
        ["end"] = true,
    })
    local last = self:consume("end")

    return finishNode({
        kind = "Do",
        body = body,
    }, first, last)
end

function Parser:parseWhileStatement()
    local first = self:consume("while")
    local condition = self:parseExpression()
    self:consume("do")
    local body = self:parseBlock({
        ["end"] = true,
    })
    local last = self:consume("end")

    return finishNode({
        kind = "While",
        condition = condition,
        body = body,
    }, first, last)
end

function Parser:parseRepeatStatement()
    local first = self:consume("repeat")
    local body = self:parseBlock({
        ["until"] = true,
    })
    self:consume("until")
    local condition = self:parseExpression()

    return finishNode({
        kind = "Repeat",
        body = body,
        condition = condition,
    }, first, condition)
end

function Parser:parseIfStatement()
    local first = self:consume("if")
    local clauses = {}

    repeat
        local condition = self:parseExpression()
        self:consume("then")
        local body = self:parseBlock({
            ["elseif"] = true,
            ["else"] = true,
            ["end"] = true,
        })

        clauses[#clauses + 1] = finishNode({
            kind = "IfClause",
            condition = condition,
            body = body,
        }, condition, body)

    until not self:match("elseif")

    local elseBody
    if self:match("else") then
        elseBody = self:parseBlock({
            ["end"] = true,
        })
    end
    local last = self:consume("end")

    return finishNode({
        kind = "If",
        clauses = clauses,
        elseBody = elseBody,
    }, first, last)
end

function Parser:parseForStatement()
    local first = self:consume("for")
    local name = self:consume("name", "for variable expected")

    if self:match("=") then
        local initial = self:parseExpression()

        self:consume(",")
        local limit = self:parseExpression()

        local step
        if self:match(",") then
            step = self:parseExpression()
        end

        self:consume("do")
        local body = self:parseBlock({
            ["end"] = true,
        })
        local last = self:consume("end")

        return finishNode({
            kind = "NumericFor",
            variable = self:nameDeclaration(name),
            initial = initial,
            limit = limit,
            step = step,
            body = body,
        }, first, last)
    end

    local names = {
        self:nameDeclaration(name),
    }

    while self:match(",") do
        name = self:consume("name", "for variable expected")
        names[#names + 1] = self:nameDeclaration(name)
    end

    self:consume("in")
    local expressions = self:parseExpressionList()

    self:consume("do")
    local body = self:parseBlock({
        ["end"] = true,
    })
    local last = self:consume("end")

    return finishNode({
        kind = "GenericFor",
        variables = names,
        expressions = expressions,
        body = body,
    }, first, last)
end

function Parser:parseFunctionStatement()
    local first = self:consume("function")
    local name = self:consume("name", "function name expected")
    local target = self:nameExpression(name)
    local method = false

    while self:match(".") do
        name = self:consume("name", "field name expected")

        target = finishNode({
            kind = "Index",
            base = target,
            key = self:literal(name.value, "string", name),
        }, target, name)
    end

    if self:match(":") then
        name = self:consume("name", "method name expected")

        target = finishNode({
            kind = "Index",
            base = target,
            key = self:literal(name.value, "string", name),
        }, target, name)
        method = true
    end

    local value = self:parseFunctionBody(first, method)

    return finishNode({
        kind = "Assign",
        targets = { target },
        values = { value },
    }, first, value)
end

function Parser:parseLocalStatement()
    local first = self:consume("local")

    if self:match("function") then
        local name = self:consume("name", "function name expected")
        local declaration = self:nameDeclaration(name)
        local value = self:parseFunctionBody(first, false)

        return finishNode({
            kind = "LocalFunction",
            variable = declaration,
            value = value,
        }, first, value)
    end

    local name = self:consume("name", "local variable name expected")
    local names = {
        self:nameDeclaration(name),
    }

    while self:match(",") do
        name = self:consume("name", "local variable name expected")
        names[#names + 1] = self:nameDeclaration(name)
    end

    local values = {}
    local last = names[#names]

    if self:match("=") then
        values = self:parseExpressionList()
        last = values[#values]
    end

    return finishNode({
        kind = "Local",
        variables = names,
        values = values,
    }, first, last)
end

function Parser:isAssignable(expression)
    return expression.kind == "Name" or expression.kind == "Index"
end

function Parser:parseAssignmentOrCall()
    local first = self:current()
    local expression = self:parsePrefixExpression()

    if self:check("=") or self:check(",") then
        if not self:isAssignable(expression) then
            self:errorAt(first, "assignment target expected")
        end

        local targets = {
            expression,
        }

        while self:match(",") do
            local targetFirst = self:current()
            local target = self:parsePrefixExpression()

            if not self:isAssignable(target) then
                self:errorAt(targetFirst, "assignment target expected")
            end

            targets[#targets + 1] = target
        end

        self:consume("=")
        local values = self:parseExpressionList()

        return finishNode({
            kind = "Assign",
            targets = targets,
            values = values,
        }, first, values[#values])
    end

    if expression.kind ~= "Call" and expression.kind ~= "MethodCall" then
        self:errorAt(first, "function call expected")
    end

    return finishNode({
        kind = "CallStatement",
        expression = expression,
    }, first, expression)
end

function Parser:parseReturnStatement()
    local first = self:consume("return")
    local values = {}

    if not BLOCK_TERMINATORS[self:current().kind] and not self:check(";") then
        values = self:parseExpressionList()
    end

    local last = values[#values] or first

    return finishNode({
        kind = "Return",
        values = values,
    }, first, last)
end

function Parser:parseStatement()
    local kind = self:current().kind

    if kind == "do" then
        return self:parseDoStatement()

    elseif kind == "while" then
        return self:parseWhileStatement()

    elseif kind == "repeat" then
        return self:parseRepeatStatement()

    elseif kind == "if" then
        return self:parseIfStatement()

    elseif kind == "for" then
        return self:parseForStatement()

    elseif kind == "function" then
        return self:parseFunctionStatement()

    elseif kind == "local" then
        return self:parseLocalStatement()

    elseif kind == "return" then
        return self:parseReturnStatement(), true

    elseif kind == "break" then
        local token = self:advance()
        return finishNode({
            kind = "Break",
        }, token, token), true

    elseif kind == "name" or kind == "(" then
        return self:parseAssignmentOrCall()
    end

    self:errorAt(self:current(), "statement expected")
end

function Parser:parseBlock(stoppers)
    self:enterSyntax(self:current())

    local first = self:current()
    local statements = {}
    local last = first

    while not stoppers[self:current().kind] do
        local statement, isLast = self:parseStatement()

        statements[#statements + 1] = statement
        last = statement

        if self:match(";") then
            last = self:previous()
        end

        if isLast then
            if not stoppers[self:current().kind] then
                self:errorAt(self:current(), "unexpected statement after " .. string.lower(statement.kind))
            end
            break
        end
    end

    local block = finishNode({
        kind = "Block",
        statements = statements,
    }, first, last)

    self:leaveSyntax()
    return block
end

function Parser:run()
    local first = self:current()
    local body = self:parseBlock({
        ["eof"] = true,
    })
    local last = self:consume("eof")

    return finishNode({
        kind = "Chunk",
        parameters = {},
        isVararg = true,
        body = body,
    }, first, last)
end

local function parseTokens(tokens, chunkName)
    return Parser.new(tokens, chunkName):run()
end

--============================================================
-- Resolver
--============================================================

local Resolver = {}
Resolver.__index = Resolver

function Resolver.new(chunkName)
    return setmetatable({
        chunkName = chunkName,
    }, Resolver)
end

function Resolver:errorAt(node, message)
    failAt(self.chunkName, node.line, node.column, message, 2)
end

function Resolver:newFunctionContext(node, parent)
    return {
        node = node,
        parent = parent,
        scopes = {},
        loopDepth = 0,
        upvalues = {},
        upvalueMap = {},
        nextSlot = 0,
    }
end

function Resolver:enterScope(context)
    local scope = {
        baseSlot = context.nextSlot,
        locals = {},
    }
    context.scopes[#context.scopes + 1] = scope
end

function Resolver:leaveScope(context, block)
    local scope = context.scopes[#context.scopes]
    context.scopes[#context.scopes] = nil
    block.firstSlot = scope.baseSlot
    block.limitSlot = context.nextSlot
    context.nextSlot = scope.baseSlot
end

function Resolver:declareLocal(context, declaration)
    if context.nextSlot >= MAX_ACTIVE_LOCALS then
        self:errorAt(declaration, "too many active local variables")
    end

    local scope = context.scopes[#context.scopes]
    local binding = {
        kind = "local",
        slot = context.nextSlot,
    }
    context.nextSlot = context.nextSlot + 1
    scope.locals[declaration.name] = binding
    declaration.binding = binding
end

function Resolver:reserveHiddenLocals(context, node, count)
    if context.nextSlot + count > MAX_ACTIVE_LOCALS then
        self:errorAt(node, "too many active local variables")
    end
    context.nextSlot = context.nextSlot + count
end

function Resolver:findLocal(context, name)
    for index = #context.scopes, 1, -1 do
        local binding = context.scopes[index].locals[name]
        if binding then
            return binding
        end
    end
    return nil
end

function Resolver:addUpvalue(context, kind, index)
    local key = kind .. ":" .. tostring(index)
    local existing = context.upvalueMap[key]

    if existing ~= nil then
        return existing
    end

    if #context.upvalues >= MAX_UPVALUES then
        self:errorAt(context.node, "too many upvalues")
    end

    local upvalueIndex = #context.upvalues
    context.upvalues[#context.upvalues + 1] = {
        kind = kind,
        index = index,
    }
    context.upvalueMap[key] = upvalueIndex

    return upvalueIndex
end

function Resolver:captureFromParent(context, name)
    local parent = context.parent
    if not parent then
        return nil
    end

    local binding = self:findLocal(parent, name)
    if binding then
        return self:addUpvalue(context, "local", binding.slot)
    end

    local parentUpvalue = self:captureFromParent(parent, name)
    if parentUpvalue ~= nil then
        return self:addUpvalue(context, "upvalue", parentUpvalue)
    end

    return nil
end

function Resolver:resolveName(context, node)
    local binding = self:findLocal(context, node.name)
    if binding then
        node.binding = binding
        return
    end

    local upvalue = self:captureFromParent(context, node.name)
    if upvalue ~= nil then
        node.binding = {
            kind = "upvalue",
            index = upvalue,
        }
    else
        node.binding = {
            kind = "global",
            name = node.name,
        }
    end
end

function Resolver:resolveExpression(context, node)
    local pending = { node }
    while #pending > 0 do
        node = pending[#pending]
        pending[#pending] = nil
        local kind = node.kind

        if kind == "Name" then
            self:resolveName(context, node)

        elseif kind == "Paren" or kind == "Unary" then
            pending[#pending + 1] = node.expression

        elseif kind == "Binary" then
            pending[#pending + 1] = node.right
            pending[#pending + 1] = node.left

        elseif kind == "Index" then
            pending[#pending + 1] = node.key
            pending[#pending + 1] = node.base

        elseif kind == "Call" or kind == "MethodCall" then
            for index = #node.arguments, 1, -1 do
                pending[#pending + 1] = node.arguments[index]
            end
            pending[#pending + 1] = node.callee or node.base

        elseif kind == "Function" then
            self:resolveFunction(node, context)

        elseif kind == "Table" then
            for index = #node.fields, 1, -1 do
                local field = node.fields[index]
                pending[#pending + 1] = field.value

                if field.kind == "RecordField" then
                    pending[#pending + 1] = field.key
                end
            end
        end
    end
end

function Resolver:resolveTarget(context, node)
    if node.kind == "Name" then
        self:resolveName(context, node)
    else
        self:resolveExpression(context, node.base)
        self:resolveExpression(context, node.key)
    end
end

function Resolver:resolveBlockStatements(context, block)
    for index = 1, #block.statements do
        self:resolveStatement(context, block.statements[index])
    end
end

function Resolver:resolveBlock(context, block)
    self:enterScope(context)
    self:resolveBlockStatements(context, block)
    self:leaveScope(context, block)
end

function Resolver:resolveStatement(context, node)
    local kind = node.kind

    if kind == "Assign" then
        for index = 1, #node.targets do
            self:resolveTarget(context, node.targets[index])
        end

        for index = 1, #node.values do
            self:resolveExpression(context, node.values[index])
        end

    elseif kind == "Local" then
        for index = 1, #node.values do
            self:resolveExpression(context, node.values[index])
        end

        for index = 1, #node.variables do
            self:declareLocal(context, node.variables[index])
        end

    elseif kind == "LocalFunction" then
        self:declareLocal(context, node.variable)
        self:resolveExpression(context, node.value)

    elseif kind == "CallStatement" then
        self:resolveExpression(context, node.expression)

    elseif kind == "Do" then
        self:resolveBlock(context, node.body)

    elseif kind == "If" then
        for index = 1, #node.clauses do
            local clause = node.clauses[index]
            self:resolveExpression(context, clause.condition)
            self:resolveBlock(context, clause.body)
        end

        if node.elseBody then
            self:resolveBlock(context, node.elseBody)
        end

    elseif kind == "While" then
        self:resolveExpression(context, node.condition)
        context.loopDepth = context.loopDepth + 1

        self:resolveBlock(context, node.body)
        context.loopDepth = context.loopDepth - 1

    elseif kind == "Repeat" then
        self:enterScope(context)
        context.loopDepth = context.loopDepth + 1

        self:resolveBlockStatements(context, node.body)
        self:resolveExpression(context, node.condition)
        context.loopDepth = context.loopDepth - 1

        self:leaveScope(context, node.body)

    elseif kind == "NumericFor" then
        self:resolveExpression(context, node.initial)
        self:resolveExpression(context, node.limit)

        if node.step then
            self:resolveExpression(context, node.step)
        end

        self:enterScope(context)

        self:reserveHiddenLocals(context, node, 3)
        self:declareLocal(context, node.variable)
        context.loopDepth = context.loopDepth + 1

        self:resolveBlockStatements(context, node.body)
        context.loopDepth = context.loopDepth - 1

        self:leaveScope(context, node.body)

    elseif kind == "GenericFor" then
        for index = 1, #node.expressions do
            self:resolveExpression(context, node.expressions[index])
        end

        self:enterScope(context)

        self:reserveHiddenLocals(context, node, 3)
        for index = 1, #node.variables do
            self:declareLocal(context, node.variables[index])
        end
        context.loopDepth = context.loopDepth + 1

        self:resolveBlockStatements(context, node.body)
        context.loopDepth = context.loopDepth - 1

        self:leaveScope(context, node.body)

    elseif kind == "Break" then
        if context.loopDepth == 0 then
            self:errorAt(node, "break outside loop")
        end

    elseif kind == "Return" then
        for index = 1, #node.values do
            self:resolveExpression(context, node.values[index])
        end
    end
end

function Resolver:resolveFunction(node, parent)
    local context = self:newFunctionContext(node, parent)
    self:enterScope(context)

    local parameters = node.parameters
    for index = 1, #parameters do
        self:declareLocal(context, parameters[index])
    end

    self:resolveBlockStatements(context, node.body)
    self:leaveScope(context, node.body)

    node.resolution = {
        upvalues = context.upvalues,
    }
end

function Resolver:run(ast)
    self:resolveFunction(ast, nil)
end

--============================================================
-- Lua 5.1 semantic annotations
--============================================================

-- Preserve the observable numeric folding and deferred-local semantics of Lua 5.1
-- without retaining its instructions, registers, or constant pool.
local function annotateLua51Semantics(ast)
    -- onTrue/onFalse: pending short-circuit branches, not known truth values.
    local visitFunction

    local function arithmetic(operator)
        return operator == "+"
            or operator == "-"
            or operator == "*"
            or operator == "/"
            or operator == "%"
            or operator == "^"
    end

    local function fold(operator, left, right)
        if (operator == "/" or operator == "%") and right == 0 then
            return false
        end

        local value = binaryValue(operator, left, right)
        return value == value, value
    end

    local function numeral(value)
        return value.kind == "number" and not value.onTrue and not value.onFalse
    end

    local function truth(value)
        if value.kind == "number" or value.kind == "string" then
            return true, true

        elseif value.kind == "boolean" then
            return true, value.value

        elseif value.kind == "nil" then
            return true, false
        end

        return false
    end

    visitFunction = function(fn)
        -- PUC Lua 5.1 stores both zero signs as one constant per function.
        -- The first zero added to the constant table determines its sign.
        local firstZero
        local expression, block

        local function materializeRaw(value)
            if value.kind == "number" then
                local number = value.value

                if number == 0 then
                    if firstZero == nil then
                        firstZero = number
                    end

                    number = firstZero
                end

                value.origin.numericValue = number
            end
        end

        local function materialize(value)
            materializeRaw(value)
            value.onTrue, value.onFalse = nil, nil
        end

        local function operand(value)
            if not (
                (value.kind == "local" or value.kind == "runtime")
                and not value.onTrue
                and not value.onFalse
            ) then
                materialize(value)
                value.kind = "runtime"
            end
        end

        local function expressionList(nodes)
            for index = 1, #nodes do
                materialize(expression(nodes[index]))
            end
        end

        local function finish(node, left)
            local kind = node.kind
            local result = {
                kind = "runtime",
            }

            if kind == "Literal" then
                result = {
                    kind = node.literalKind,
                    value = node.value,
                    origin = node,
                }

            elseif kind == "Name" and node.binding.kind == "local" then
                result.kind = "local"

            elseif kind == "Paren" then
                result = left

            elseif kind == "Function" then
                visitFunction(node)

            elseif kind == "Table" then
                for index = 1, #node.fields do
                    local field = node.fields[index]

                    if field.kind == "RecordField" then
                        operand(expression(field.key))
                        operand(expression(field.value))
                    else
                        materialize(expression(field.value))
                    end
                end

            elseif kind == "Call" or kind == "MethodCall" then
                materialize(left)
                expressionList(node.arguments)

            elseif kind == "Index" then
                operand(left)
                operand(expression(node.key))

            elseif kind == "Unary" then
                if node.operator == "not" then
                    local known, value = truth(left)
                    if known then
                        result = {
                            kind = "boolean",
                            value = not value,
                        }
                    else
                        materializeRaw(left)
                    end

                    result.onTrue, result.onFalse = left.onFalse, left.onTrue

                elseif node.operator == "-" and numeral(left) and -left.value == -left.value then
                    result = {
                        kind = "number",
                        value = -left.value,
                        origin = node,
                    }
                else
                    operand(left)
                end

            elseif kind == "Binary" then
                local operator = node.operator

                if operator == "and" or operator == "or" then
                    local known, value = truth(left)
                    local branch = not (known and value ~= (operator == "or"))

                    if branch and left.kind ~= "local" and left.kind ~= "runtime" then
                        materializeRaw(left)
                    end

                    result = expression(node.right)
                    if operator == "and" then
                        result.onFalse = result.onFalse or left.onFalse or branch
                    else
                        result.onTrue = result.onTrue or left.onTrue or branch
                    end

                    node.liveResult = result.kind == "local" and not result.onTrue and not result.onFalse

                elseif operator == ".." then
                    materialize(left)
                    materialize(expression(node.right))
                else
                    if not arithmetic(operator) or not numeral(left) then
                        operand(left)
                    end

                    local right = expression(node.right)
                    local folded, number

                    if arithmetic(operator) and numeral(left) and numeral(right) then
                        folded, number = fold(operator, left.value, right.value)
                    end

                    if folded then
                        result = {
                            kind = "number",
                            value = number,
                            origin = node,
                        }
                    else
                        operand(right)
                        operand(left)
                    end
                end
            end

            return result
        end

        expression = function(node)
            -- Walk flat chains iteratively to keep Lua call depth independent of chain length.
            local pending = {}

            while true do
                local child, kind = nil, node.kind
                if kind == "Binary" then
                    child = node.left

                elseif kind == "Unary" or kind == "Paren" then
                    child = node.expression

                elseif kind == "Index" or kind == "MethodCall" then
                    child = node.base

                elseif kind == "Call" then
                    child = node.callee
                end

                if not child then
                    break
                end

                pending[#pending + 1] = node
                node = child
            end

            local result = finish(node)
            for index = #pending, 1, -1 do
                result = finish(pending[index], result)
            end

            return result
        end

        local function condition(node)
            local value = expression(node)
            local known = truth(value)

            if not known then
                materialize(value)
            end
        end

        block = function(body)
            for index = 1, #body.statements do
                local node = body.statements[index]
                local kind = node.kind

                if kind == "Assign" then
                    for targetIndex = 1, #node.targets do
                        local target = node.targets[targetIndex]
                        if target.kind == "Index" then
                            operand(expression(target.base))
                            operand(expression(target.key))
                        end
                    end
                    expressionList(node.values)

                elseif kind == "Local" or kind == "Return" then
                    expressionList(node.values)

                elseif kind == "LocalFunction" then
                    materialize(expression(node.value))

                elseif kind == "CallStatement" then
                    materialize(expression(node.expression))

                elseif kind == "Do" then
                    block(node.body)

                elseif kind == "If" then
                    for clauseIndex = 1, #node.clauses do
                        local clause = node.clauses[clauseIndex]
                        condition(clause.condition)
                        block(clause.body)
                    end

                    if node.elseBody then
                        block(node.elseBody)
                    end

                elseif kind == "While" then
                    condition(node.condition)
                    block(node.body)

                elseif kind == "Repeat" then
                    block(node.body)
                    condition(node.condition)

                elseif kind == "NumericFor" then
                    materialize(expression(node.initial))
                    materialize(expression(node.limit))
                    if node.step then
                        materialize(expression(node.step))
                    end
                    block(node.body)

                elseif kind == "GenericFor" then
                    expressionList(node.expressions)
                    block(node.body)
                end
            end
        end

        block(fn.body)
    end

    visitFunction(ast)
end

--============================================================
-- Interpreter
--============================================================

local evalOperand
local evalExpression
local evalMany
local executeBlock
local newFunction

-- A cell defers reading a local until the operation uses it.
-- PUC Lua 5.1 can observe changes made by another operand in the meantime.
local function readOperand(value, cell)
    if cell then
        return cell.value
    end
    return value
end

local function isMultiResult(node)
    return node.kind == "Call" or node.kind == "MethodCall" or node.kind == "Vararg"
end

local function evalExpressionList(nodes, frame, resultLimit)
    local values = { n = 0 }
    for index = 1, #nodes do
        local node = nodes[index]
        if index == #nodes and isMultiResult(node) then
            local last = evalMany(node, frame)
            local count = last.n
            if resultLimit then
                count = math.max(0, math.min(count, resultLimit - values.n))
            end
            for offset = 1, count do
                values[values.n + offset] = last[offset]
            end
            values.n = values.n + count
        else
            values.n = values.n + 1
            values[values.n] = evalExpression(node, frame)
        end
    end
    return values
end

local function takeCallTarget(holder)
    local target = holder.target
    holder.target = nil
    return target
end

local function callMethod(node, frame, holder)
    -- Look up the method before handing its receiver to the call's temporary arguments.
    return holder.target[node.method](takeCallTarget(holder), unpackPacked(evalExpressionList(node.arguments, frame)))
end

local function evalTable(node, frame)
    local object = {}
    local nextIndex = 1

    for index = 1, #node.fields do
        local field = node.fields[index]

        if field.kind == "RecordField" then
            local key, cell = evalOperand(field.key, frame)
            local value = evalExpression(field.value, frame)
            object[readOperand(key, cell)] = value

        elseif index == #node.fields and isMultiResult(field.value) then
            local values = evalMany(field.value, frame)
            for offset = 1, values.n do
                object[nextIndex + offset - 1] = values[offset]
            end
        else
            object[nextIndex] = evalExpression(field.value, frame)
            nextIndex = nextIndex + 1
        end
    end

    return object
end

local function evalNode(node, frame, prefix, prefixCell)
    local kind = node.kind

    if kind == "Literal" then
        return node.value

    elseif kind == "Name" then
        local binding = node.binding

        if binding.kind == "global" then
            return frame.env[binding.name]
        elseif binding.kind == "local" then
            return nil, frame.locals[binding.slot]
        else
            return frame.upvalues[binding.index].value
        end

    elseif kind == "Vararg" then
        return frame.varargs[1]

    elseif kind == "Function" then
        local upvalues = {}
        for index = 1, #node.resolution.upvalues do
            local descriptor = node.resolution.upvalues[index]
            if descriptor.kind == "local" then
                upvalues[index - 1] = frame.locals[descriptor.index]
            else
                upvalues[index - 1] = frame.upvalues[descriptor.index]
            end
        end
        return newFunction(node, upvalues, frame.env, frame.chunkName)

    elseif kind == "Table" then
        return evalTable(node, frame)

    elseif kind == "Paren" then
        return prefix, prefixCell

    elseif kind == "Unary" then
        local value = readOperand(prefix, prefixCell)

        if node.operator == "-" then
            return -value

        elseif node.operator == "#" then
            return #value
        else
            return not value
        end

    elseif kind == "Index" then
        local key = evalExpression(node.key, frame)
        return readOperand(prefix, prefixCell)[key]

    elseif kind == "Binary" then
        local operator = node.operator

        if operator == "and" or operator == "or" then
            local left = readOperand(prefix, prefixCell)
            if (operator == "and" and not left) or (operator == "or" and left) then
                return left
            end

            local value, cell = evalOperand(node.right, frame)
            if node.liveResult then
                return value, cell
            end

            return readOperand(value, cell)

        elseif operator == ".." then
            local left = readOperand(prefix, prefixCell)
            return binaryValue(operator, left, evalExpression(node.right, frame))
        end

        local right = evalExpression(node.right, frame)
        return binaryValue(operator, readOperand(prefix, prefixCell), right)
    end
end

evalOperand = function(node, frame)
    -- Flat chains can grow independently of parser nesting.
    -- Traverse them iteratively to keep Lua call depth bounded along the chain.
    local pending

    while true do
        local kind = node.kind
        local child

        if kind == "Binary" then
            child = node.left

        elseif kind == "Unary" or kind == "Paren" then
            child = node.expression

        elseif kind == "Index" or kind == "MethodCall" then
            child = node.base

        elseif kind == "Call" then
            child = node.callee
        end

        if not child then
            break
        end

        if not pending then
            pending = {}
        end

        pending[#pending + 1] = node
        node = child
    end

    local value, cell = evalNode(node, frame)
    -- Folded results can still have side-effecting children; evaluate them first.
    if node.numericValue ~= nil then
        value, cell = node.numericValue, nil
    end

    if pending then
        for index = #pending, 1, -1 do
            node = pending[index]
            local kind = node.kind
            if kind == "Call" or kind == "MethodCall" then
                -- Move the target out of the evaluator's locals before the call can suspend.
                pending.target = readOperand(value, cell)
                value, cell = nil, nil
                if kind == "MethodCall" then
                    value = callMethod(node, frame, pending)
                else
                    value = takeCallTarget(pending)(unpackPacked(evalExpressionList(node.arguments, frame)))
                end
            else
                value, cell = evalNode(node, frame, value, cell)
            end

            if node.numericValue ~= nil then
                value, cell = node.numericValue, nil
            end
        end
    end

    return value, cell
end

evalExpression = function(node, frame)
    local value, cell = evalOperand(node, frame)
    return readOperand(value, cell)
end

evalMany = function(node, frame)
    if node.kind == "Vararg" then
        return frame.varargs
    end

    if node.kind == "MethodCall" then
        return packed(callMethod(node, frame, { target = evalExpression(node.base, frame) }))
    end

    return packed(evalExpression(node.callee, frame)(unpackPacked(evalExpressionList(node.arguments, frame))))
end

-- With a local i, t[i], i = f(), 3 fixes the first target's index before f() runs.
local function freezeConflictingReferences(references, cell)
    for index = 1, #references do
        local reference = references[index]

        if reference.objectCell == cell then
            reference.object, reference.objectCell = cell.value, nil
        end

        if reference.keyCell == cell then
            reference.key, reference.keyCell = cell.value, nil
        end
    end
end

local function assign(node, frame)
    local references = {}

    for index = 1, #node.targets do
        local target = node.targets[index]

        if target.kind == "Name" then
            local binding = target.binding
            if binding.kind == "local" then
                freezeConflictingReferences(references, frame.locals[binding.slot])
            end

            references[index] = {
                binding = binding,
            }
        else
            local object, objectCell = evalOperand(target.base, frame)
            local key, keyCell = evalOperand(target.key, frame)

            references[index] = {
                object = object,
                objectCell = objectCell,
                key = key,
                keyCell = keyCell,
            }
        end
    end

    local values = evalExpressionList(node.values, frame, #references)

    for index = #references, 1, -1 do
        local reference = references[index]
        local binding = reference.binding

        if binding then
            if binding.kind == "global" then
                frame.env[binding.name] = values[index]
            elseif binding.kind == "local" then
                frame.locals[binding.slot].value = values[index]
            else
                frame.upvalues[binding.index].value = values[index]
            end
        else
            local object = readOperand(reference.object, reference.objectCell)
            object[readOperand(reference.key, reference.keyCell)] = values[index]
        end
    end
end

local function declare(variables, values, frame)
    for index = 1, #variables do
        frame.locals[variables[index].binding.slot] = {
            value = values[index],
        }
    end
end

local function leaveBlock(block, frame)
    for slot = block.firstSlot, block.limitSlot - 1 do
        frame.locals[slot] = nil
    end
end

local executeStatements

local function forNumber(value, name, node, frame)
    local number = tonumber(value)
    if number == nil then
        failAt(frame.chunkName, node.line, node.column, "'for' " .. name .. " must be a number")
    end
    return number
end

local function executeStatement(node, frame)
    local kind = node.kind

    if kind == "Assign" then
        assign(node, frame)

    elseif kind == "Local" then
        declare(node.variables, evalExpressionList(node.values, frame), frame)

    elseif kind == "LocalFunction" then
        local cell = {}
        frame.locals[node.variable.binding.slot] = cell
        cell.value = evalExpression(node.value, frame)

    elseif kind == "CallStatement" then
        evalMany(node.expression, frame)

    elseif kind == "Return" then
        return "return", evalExpressionList(node.values, frame)

    elseif kind == "Break" then
        return "break"

    elseif kind == "Do" then
        return executeBlock(node.body, frame)

    elseif kind == "If" then
        for index = 1, #node.clauses do
            local clause = node.clauses[index]

            if evalExpression(clause.condition, frame) then
                return executeBlock(clause.body, frame)
            end
        end

        if node.elseBody then
            return executeBlock(node.elseBody, frame)
        end

    elseif kind == "While" then
        while evalExpression(node.condition, frame) do
            local signal, values = executeBlock(node.body, frame)

            if signal == "return" then
                return signal, values
            end

            if signal == "break" then
                break
            end
        end

    elseif kind == "Repeat" then
        repeat
            local signal, values = executeStatements(node.body, frame)
            local done = signal ~= nil or evalExpression(node.condition, frame)

            leaveBlock(node.body, frame)

            if signal == "return" then
                return signal, values
            end

        until done

    elseif kind == "NumericFor" then
        local initial = evalExpression(node.initial, frame)
        local limit = evalExpression(node.limit, frame)
        local step = 1

        if node.step then
            step = evalExpression(node.step, frame)
        end

        initial = forNumber(initial, "initial value", node, frame)
        limit = forNumber(limit, "limit", node, frame)
        step = forNumber(step, "step", node, frame)

        for control = initial, limit, step do
            frame.locals[node.variable.binding.slot] = {
                value = control,
            }

            local signal, values = executeBlock(node.body, frame)

            if signal == "return" then
                return signal, values
            end

            if signal == "break" then
                break
            end
        end

    elseif kind == "GenericFor" then
        local values = evalExpressionList(node.expressions, frame)
        local iterator = values[1]

        local function iterate(state, control)
            -- Release unused setup values before the iterator runs.
            values = nil
            local results = packed(iterator(state, control))
            return results[1], results
        end

        -- The host loop enforces Lua 5.1's yield boundary for the iterator.
        for _, results in iterate, values[2], values[3] do
            declare(node.variables, results, frame)
            results = nil

            local signal, returned = executeBlock(node.body, frame)

            if signal == "return" then
                return signal, returned
            end

            if signal == "break" then
                break
            end
        end
    end
end

executeStatements = function(block, frame)
    for index = 1, #block.statements do
        local signal, values = executeStatement(block.statements[index], frame)
        if signal then
            return signal, values
        end
    end
end

executeBlock = function(block, frame)
    local signal, values = executeStatements(block, frame)
    leaveBlock(block, frame)
    return signal, values
end

local function executeFunctionBody(body, frame)
    local _, values = executeBlock(body, frame)
    if values then
        return unpackPacked(values)
    end
end

newFunction = function(node, upvalues, env, chunkName)
    -- Capture only the function and its actual upvalues, never its parent frame.
    local function wrapper(...)
        local parameters = node.parameters
        local frame = {
            locals = {},
            upvalues = upvalues,
            env = env,
            chunkName = chunkName,
            -- Keep the active function alive across the tail call below.
            closure = wrapper,
        }
        declare(parameters, { ... }, frame)

        if node.isVararg then
            frame.varargs = packed(select(#parameters + 1, ...))
        end

        -- The tail call releases the wrapper's original arguments before the script runs.
        return executeFunctionBody(node.body, frame)
    end

    return wrapper
end

--============================================================
-- Public API
--============================================================

local function parse(source, chunkName)
    expectType(source, "string", "source", 2)

    if chunkName == nil then
        chunkName = DEFAULT_CHUNK_NAME
    else
        expectType(chunkName, "string", "chunkName", 2)
    end

    if string.len(source) > MAX_SOURCE_SIZE then
        failAt(chunkName, 1, 1, "source exceeds internal size limit", 2)
    end

    local ast = parseTokens(tokenize(source, chunkName), chunkName)

    Resolver.new(chunkName):run(ast)
    annotateLua51Semantics(ast)
    ast.chunkName = chunkName

    return ast
end

local function execute(ast, env, ...)
    if env == nil then
        env = {}
    else
        expectType(env, "table", "env", 2)
    end

    local wrapper = newFunction(ast, {}, env, ast.chunkName)
    return wrapper(...)
end

local function run(source, chunkName, env, ...)
    return execute(parse(source, chunkName), env, ...)
end

Rima.parse = parse
Rima.execute = execute
Rima.run = run

return Rima
