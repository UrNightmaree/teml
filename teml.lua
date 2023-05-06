local L = require("log")
local I = require("inspect")
local teml = setmetatable({}, {
    __call = function(self, str)
        return self.eval(str)
    end,
})

teml._version = "0.1.0"

local function trim(str)
    return str:match("^%s*(.*)%s*$")
end

local function shallow_copy(t)
    local copy = {}
    for i, v in pairs(t) do
        if type(v) == "table" then
            copy[i] = shallow_copy(v)
        else
            copy[i] = v
        end
    end
    return copy
end

local function is_empty(str)
    return not str or str == "" or str:match("^%s+$")
end

local function is_number(str, integer)
    if is_empty(str) then
        return false
    end
    if str == "0" then
        return true
    end

    local integer_pattern = "^[-+]?[1-9]%d*$"
    local number_pattern1 = "^[-+]?[1-9]%d*"
    local number_pattern2 = "%.%d+$"

    local _, found_n = str:gsub(number_pattern2, "")

    if not integer and str:match(number_pattern1) and found_n >= 0 and found_n <= 1 then
        return true
    elseif integer and str:match(integer_pattern) then
        return true
    end
    return false
end

local function get_line(str, pattern)
    local n = 0
    for s in str:gmatch("([^\n\r]+)") do
        n = n + 1
        if s:match(pattern) then
            return n
        end
    end
end

local function str_index(tbl, str)
    local buffer = {}
    for s in str:gmatch("([^.]+)") do
        buffer[#buffer + 1] = s:match("^%d+$") and "[" .. s .. "]" or "['" .. s .. "']"
    end
    local f = (load or loadstring)("return (_VERSION == 'Lua 5.1' and arg or {...})[1]" .. table.concat(buffer))
    return f and f(tbl)
end

local function escape(str)
    return str:gsub("%p", "%%%1")
end

local function gen_error(line, err)
    return ("line %d: %s"):format(line, err)
end

local function gen_func_error(line, func, err, argn)
    return not argn and gen_error(line, ("%s: %s"):format(func, err))
        or gen_error(line, ("%s: error on argument #%d (%s)"):format(func, argn, err))
end

local patterns = {
    -- For loop:
    -- `@for(<varname[,varname...]> : <<table-var> / <s>..<e>[..<i>]){<template>}`
    {
        "@for%s*%((.-)%)%s*{(.-)}",
        ---@param p PropTable
        ---@param string_iter string
        ---@param template string
        ---@return string?
        ---@return string?
        function(p, string_iter, template)
            if is_empty(string_iter) then
                return nil,
                    gen_error(
                        get_line(p.string, "@for%s*%(" .. string_iter .. "%)%s*{" .. template .. "}"),
                        "for iter expression is empty."
                    )
            end

            string_iter = trim(string_iter)

            local iter_variable, iter = {}, nil
            string_iter:gsub("(.+)[ ]*:[ ]*(.+)", function(c1, c2)
                iter = c2
                for s in c1:gmatch("([^,]+)") do
                    iter_variable[#iter_variable + 1] = s
                end
            end)

            local buffer = ""
            local tmp_table = shallow_copy(p.table)

            if type(str_index(p.table, iter)) == "table" then
                for i, v in pairs(str_index(p.table, iter)) do
                    tmp_table[iter_variable[1] or ""] = i
                    tmp_table[iter_variable[2] or ""] = v
                    buffer = buffer .. teml(template)(tmp_table)
                end
                return buffer
            end

            local sei_variable = {}
            for v in iter:gmatch("([^..]+)") do
                sei_variable[#sei_variable + 1] = tonumber(v)
            end

            local start_var, end_var, increase_var = (table.unpack or unpack)(sei_variable)
            if start_var and end_var and increase_var then
                for i = start_var, end_var, increase_var do
                    tmp_table[iter_variable[1] or ""] = i
                    buffer = buffer .. teml(template)(tmp_table)
                end
            else
                for i = start_var, end_var do
                    tmp_table[iter_variable[1] or ""] = i
                    buffer = buffer .. teml(template)(tmp_table)
                end
            end
            return buffer
        end,
    },

    -- If-else statement:
    -- `@if(<<template>+<comp>>){<template>}@else(<alt-template>)
    {
        "@if%s*%((.-)%)%s*{(.-)}%s*@else%s*{(.-)}",
        ---@param p PropTable
        ---@param logical_exp string
        ---@param template string
        ---@param alt_template string
        ---@return string?
        ---@return string?
        function(p, logical_exp, template, alt_template)
            if is_empty(logical_exp) then
                return nil,
                    gen_error(
                        get_line(
                            p.string,
                            "@if%s*%("
                                .. escape(logical_exp)
                                .. "%)%s*{"
                                .. escape(template)
                                .. "}%s*@else%s*{"
                                .. alt_template
                                .. "}"
                        ),
                        "statement is empty."
                    )
            end

            local f = (load or loadstring)("return " .. teml(logical_exp)(p.table))
            if not f then
                return teml(alt_template)(p.table)
            end

            return f() and teml(template)(p.table) or teml(alt_template)(p.table)
        end,
    },

    -- If statement:
    -- `@if(<<template>+<comp>>){<template>}`
    {
        "@if%s*%((.-)%)%s*{(.-)}",
        ---@param p PropTable
        ---@param logical_exp string
        ---@param template string
        ---@return string?
        ---@return string?
        function(p, logical_exp, template)
            if is_empty(logical_exp) then
                return nil,
                    gen_error(
                        get_line(p.string, "@if%s*%(" .. escape(logical_exp) .. "%)%s*{" .. escape(template) .. "}"),
                        "statement is empty."
                    )
            end

            local f = (load or loadstring)("return " .. teml(logical_exp)(p.table))
            if not f then
                return ""
            end

            return f() and teml(template)(p.table) or ""
        end,
    },

    -- Function call:
    -- `@<func-name>([arg1[,argn...]])`
    {
        "@(%S-)%s*%((.*)%)",
        ---@param p PropTable
        ---@param func_name string
        ---@param args string
        ---@return string?
        ---@return string?
        function(p, func_name, args)
            args = teml(args)(p.table)
            local fn_args = {}
            for s in args:gmatch("([^,]+)") do
                fn_args[#fn_args + 1] = teml(s)(p.table)
            end

            local ret, err

            if type(teml.functions[func_name]) == "function" then
                ret, err = teml.functions[func_name]((table.unpack or unpack)(fn_args))
                err = err
                    and gen_func_error(
                        get_line(p.string, "@" .. escape(func_name) .. "%(" .. escape(args) .. "%)"),
                        func_name,
                        err
                    )
            else
                local table_func = shallow_copy(teml.functions[func_name])
                local func = table.remove(table_func, 1)

                local eval_args = {}
                for i, v in ipairs(table_func) do
                    local farg = fn_args[i]
                    local param_type, param_optional = v:match("^(%l+)(%??)$")

                    if param_type == "integer" then
                        err = param_optional == ""
                                and not is_number(farg, true)
                                and gen_func_error(
                                    get_line(p.string, "@" .. escape(func_name) .. "%(" .. escape(args) .. "%)"),
                                    func_name,
                                    "expected integer",
                                    i
                                )
                            or nil
                        eval_args[i] = not err and tonumber(farg) or nil
                    elseif param_type == "number" then
                        err = param_optional == ""
                            or not is_number(farg) and gen_func_error(
                                get_line(p.string, "@" .. escape(func_name) .. "%(" .. escape(args) .. "%)"),
                                func_name,
                                "expected number",
                                i
                            )
                            or nil
                        eval_args[i] = not err and tonumber(farg) or nil
                    else
                        err = param_optional == ""
                                and is_empty(farg)
                                and gen_func_error(
                                    get_line(p.string, "@" .. escape(func_name) .. "%(" .. escape(args) .. "%)"),
                                    func_name,
                                    "expected value",
                                    i
                                )
                            or nil
                        eval_args[i] = not err and farg or nil
                    end

                    if err then
                        L.info("test")
                        break
                    end
                end

                local ok
                ok, ret = pcall(func, (table.unpack or unpack)(eval_args))

                if not ok and not err and ret then
                    err = gen_func_error(
                        get_line(p.string, "@" .. escape(func_name) .. "%(" .. escape(args) .. "%)"),
                        func_name,
                        ret
                    )
                    ret = nil
                end
            end

            return ret, err
        end,
    },

    -- Use string B if variable A unset:
    -- `${<variable-A>:-<string-B>}`
    {
        "${(.-):%-(.-)}",
        ---@param p PropTable
        ---@param variable_name string
        ---@param alt_string string
        ---@return string?
        ---@return string?
        function(p, variable_name, alt_string)
            if is_empty(variable_name) then
                return nil,
                    gen_error(
                        get_line(p.string, "${" .. escape(variable_name) .. ":%-" .. escape(alt_string) .. "}"),
                        "empty variable name."
                    )
            end

            return str_index(p.table, variable_name) or alt_string
        end,
    },

    -- Use string B if variable A set:
    -- `${<variable-A>:+<string-B>}`
    {
        "${(.-):%+(.-)}",
        ---@param p PropTable
        ---@param variable_name string
        ---@param set_string string
        ---@return string?
        ---@return string?
        function(p, variable_name, set_string)
            if is_empty(variable_name) then
                return nil,
                    gen_error(
                        get_line(p.string, "${" .. escape(variable_name) .. ":%+" .. escape(set_string) .. "}"),
                        "empty variable name."
                    )
            end

            return str_index(p.table, variable_name) and set_string
        end,
    },

    -- Variable: `$<var-name>`
    {
        "$(%w+)",
        ---@param p PropTable
        ---@param variable_name string
        ---@return any
        function(p, variable_name)
            return str_index(p.table, variable_name)
        end,
    },

    -- Enclosed variable `${<var-name>}`
    {
        "${(.-)}",
        ---@param p PropTable
        ---@param variable_name string
        ---@return any?
        ---@return string?
        function(p, variable_name)
            if is_empty(variable_name) then
                return nil, gen_error(get_line(p.string, "${" .. escape(variable_name) .. "}"), "empty variable name.")
            end

            return str_index(p.table, variable_name)
        end,
    },
}

local functions = {
    ["string.rep"] = { string.rep, "string", "integer", "string?" },
    ["string.reverse"] = { string.reverse, "string" },
    ["string.sub"] = { string.sub, "string", "integer", "integer?" },
    ["string.len"] = { string.len, "string" },
    ["string.upper"] = { string.upper, "string" },
    ["string.lower"] = { string.lower, "string" },
    ["string.byte"] = { string.byte, "string", "integer?", "integer?" },
}

teml.patterns = patterns
teml.functions = functions

function teml.eval(str)
    ---@class PropTable
    ---@field string string
    ---@field table table
    ---@field pattern string
    local prop = { string = str }

    return function(...)
        prop.table = select("#", ...) > 1 and { ... } or select(1, ...)

        local err
        for _, v in ipairs(patterns) do
            prop.pattern = v[1]
            str = str:gsub("(" .. v[1] .. ")", function(_, ...)
                local eval_string
                eval_string, err = v[2](prop, ...)

                if not err then
                    return tostring(eval_string)
                end
            end)

            if err then
                str = nil
                break
            end
        end

        return str, err
    end
end

return teml
