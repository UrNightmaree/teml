local L = require "log"
local I = require "inspect"
local teml = setmetatable({},{
    __call = function(self,str)
        return self.eval(str)
    end
})

teml._version = "0.1.0"

local function trim(str)
    return str:match "^%s*(.*)%s*$"
end

local function shallow_copy(t)
    local copy = {}
    for i,v in pairs(t) do
        if type(v) == "table" then
            copy[i] = shallow_copy(v)
        else copy[i] = v end
    end
    return copy
end

local function is_empty(str)
    return str == "" or str:match "^%s+$"
end

local function get_line(str,patt)
    local n = 0
    for s in str:gmatch "([^\n\r]+)" do
        n = n + 1
        if s:match(patt) then
            return n
        end
    end
end

local function str_index(tbl,str)
    local buff = {}
    for s in str:gmatch "([^.]+)" do
        buff[#buff+1] =
            s:match "^%d+$" and "["..s.."]" or
            "['"..s.."']"
    end
    local f = (load or loadstring)(
        "return (_VERSION == 'Lua 5.1' and arg or {...})[1]"
        ..table.concat(buff))
    return f and f(tbl)
end

local function escape(str)
    return str:gsub("%p","%%%1")
end

local patterns = {
    -- For loop:
    -- `@for(<varname[,varname...]> : <<table-var> / <s>..<e>[..<i>]){<template>}`
    {"@for%s*%((.-)%)%s*{(.-)}",
    ---@param p PropTable
    ---@param s_iter string
    ---@param template string
    ---@return string?
    ---@return string?
    function(p,s_iter,template)
        if is_empty(s_iter) then
            return nil, "line "..
                   get_line(p.template_string,
                   "@for%s*%("..s_iter.."%)%s*{"..template.."}")
                   ..": for iter expression is empty."
        end

        s_iter = trim(s_iter)

        local iter_var,iter = {},nil
        s_iter:gsub("(.+)[ ]*:[ ]*(.+)",function(c1,c2)
            iter = c2
            for s in c1:gmatch "([^,]+)" do
                iter_var[#iter_var+1] = s
            end
        end)

        local buff = ""
        local tmp_t = shallow_copy(p.table)

        if type(str_index(p.table,iter)) == "table" then
            for i,v in pairs(str_index(p.table,iter)) do
                tmp_t[iter_var[1] or ""] = i
                tmp_t[iter_var[2] or ""] = v
                buff = buff..teml(template)(tmp_t)
            end
            return buff
        end

        local sei = {}
        for n in iter:gmatch "([^..]+)" do
            sei[#sei+1] = tonumber(n)
        end

        local st,en,inc = (table.unpack or unpack)(sei)
        if st and en and inc then
            for i = st,en,inc do
                tmp_t[iter_var[1] or ""] = i
                buff = buff..teml(template)(tmp_t)
            end
        else
            for i = st,en do
                tmp_t[iter_var[1] or ""] = i
                buff = buff..teml(template)(tmp_t)
            end
        end
        return buff
    end},

    -- If-else statement:
    -- `@if(<<template>+<comp>>){<template>}@else(<alt-template>)
    {"@if%s*%((.-)%)%s*{(.-)}%s*@else%s*{(.-)}",
    ---@param p PropTable
    ---@param comp_exp string
    ---@param template string
    ---@param alt_template string
    ---@return string?
    ---@return string?
    function(p,comp_exp,template,alt_template)
        if is_empty(comp_exp) then
            return nil, "line "..
                   get_line(p.template_string,
                   "@if%s*%("..escape(comp_exp).."%)%s*{"..
                   escape(template).."}%s*@else%s*{"..
                   alt_template.."}")
                   ..": statement is empty."
        end

        local f = (load or loadstring)(
        "return "..teml(comp_exp)(p.table))
        if not f then return teml(alt_template)(p.table) end

        return f() and teml(template)(p.table) or teml(alt_template)(p.table)
    end},

    -- If statement:
    -- `@if(<<template>+<comp>>){<template>}`
    {"@if%s*%((.-)%)%s*{(.-)}",
    ---@param p PropTable
    ---@param comp_exp string
    ---@param template string
    ---@return string?
    ---@return string?
    function(p,comp_exp,template)
        if is_empty(comp_exp) then
            return nil, "line "..
                   get_line(p.template_string,
                   "@if%s*%("..escape(comp_exp)..
                   "%)%s*{"..escape(template).."}")
                   ..": statement is empty."
        end

        local f = (load or loadstring)(
        "return "..teml(comp_exp)(p.table))
        if not f then return "" end

        return f() and teml(template)(p.table) or ""
    end},

    -- Function call:
    -- `@<func-name>([arg1[,argn...]])`
    {"@(%S+)%s*%((.-)%)",
    ---@param p PropTable
    ---@param func string
    ---@param args string
    ---@return string?
    ---@return string?
    function(p,func,args)
        local fn_args = {}
        for s in args:gmatch "([^,]+)" do
            fn_args[#fn_args+1] = teml(s)(p.table)
        end

        local ret,err = teml.functions[func]((table.unpack or unpack)(fn_args))

        if err then
            return nil,"line "..
            get_line(p.template_string,"@"..escape(func).."%("..
            escape(args).."%)")
            ..": "..func..": "..err
        end
        return ret
    end},

    -- Use string B if variable A unset:
    -- `${<variable-A>:-<string-B>}`
    {"${(.-):%-(.-)}",
    ---@param p PropTable
    ---@param var_name string
    ---@param alt_string string
    ---@return string?
    ---@return string?
    function(p,var_name,alt_string)
        if is_empty(var_name) then
            return nil, "line "..
            get_line(p.template_string,"${"..
            escape(var_name)..":%-"..escape(alt_string).."}")
            ..": empty variable name."
        end

        return str_index(p.table,var_name) or alt_string
    end},

    -- Use string B if variable A set:
    -- `${<variable-A>:+<string-B>}`
    {"${(.-):%+(.-)}",
    ---@param p PropTable
    ---@param var_name string
    ---@param set_string string
    ---@return string?
    ---@return string?
    function(p,var_name,set_string)
        if is_empty(var_name) then
            return nil,"line "..
            get_line(p.template_string,"${"..escape(var_name)
            ..":%+"..escape(set_string).."}")
            ..": empty variable name."
        end

        return str_index(p.table,var_name) and set_string
    end},

    -- Variable: `$<var-name>`
    {"$(%w+)",
    ---@param p PropTable
    ---@param var_name string
    ---@return any
    function(p,var_name)
        return str_index(p.table,var_name)
    end},

    -- Enclosed variable `${<var-name>}`
    {"${(.-)}",
    ---@param p PropTable
    ---@param var_name string
    ---@return any?
    ---@return string?
    function(p,var_name)
        if is_empty(var_name) then
            return nil, "line "..
                   get_line(p.template_string,"${"..escape(var_name).."}")
                   ..": empty variable name."
        end

        return str_index(p.table,var_name)
    end},
}

local functions = {
    ["string.rep"] = function(str,n,sep)
        if not str or is_empty(str) then
            return nil,"error on argument #1 (expected not empty)"
        end
        if not n or is_empty(n) or n:match "^%D+$" then
            return nil,"error on argument #2 (expected number)"
        end
        return str:rep(tonumber(n),sep or "")
    end,
    ["string.reverse"] = function(str)
        if not str or is_empty(str) then
            return nil,"error on argument #1 (expected not empty"
        end
        return str:reverse()
    end
}

teml.patterns = patterns
teml.functions = functions

function teml.eval(str)
    ---@class PropTable
    ---@field template_string string
    ---@field table table
    ---@field pattern string
    local prop = { template_string = str }

    return function(...)
        prop.table = select("#",...) > 1 and {...} or select(1,...)

        local err
        for _,v in ipairs(patterns) do
            prop.pattern = v[1]
            str = str
                :gsub("("..v[1]..")",function(_,...)
                    local eval_str
                    eval_str,err = v[2](prop,...)

                    if not err then
                        return tostring(eval_str)
                    end
                end)

            if err then
                str = nil
                break
            end
        end

        return str,err
    end
end

return teml
