local I = require "inspect"
local teml = setmetatable({},{
    __call = function(self,str)
        return self.eval(str)
    end
})

teml._version = "0.1.0"

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

local patterns = {
    {"@for%s*%((.+)%)%s*{(.+)}",
    function(t,s_iter,templ)
        s_iter = trim(s_iter)

        ---@diagnostic disable-next-line:unbalanced-assignments
        local iter_var,iter = {}
        s_iter:gsub("(.+)[ ]*:[ ]*(.+)",function(c1,c2)
            iter = c2
            for s in c1:gmatch "([^, ]+)" do
                iter_var[#iter_var+1] = s
            end
        end)

        local buff = ""
        local tmp_t = shallow_copy(t)

        if type(str_index(t,iter)) == "table" then
            for i,v in pairs(str_index(t,iter)) do
                tmp_t[iter_var[1] or "_"] = i
                tmp_t[iter_var[2] or "_"] = v
                buff = buff..teml(templ)(tmp_t)
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
                tmp_t[iter_var[1] or "_"] = i
                buff = buff..teml(templ)(tmp_t)
            end
        else
            for i = st,en do
                tmp_t[iter_var[1] or "_"] = i
                buff = buff..teml(templ)(tmp_t)
            end
        end
        return buff
    end},

    -- If-else statement: `@if(<templatep>){<template>}@else(<alt-template>)
    {"@if%s*%((.+)%)%s*{(.+)}%s*@else%s*{(.+)}",
    function(t,comp,templ,alt_templ)
        local f = (load or loadstring)(
        "return "..teml(comp)(t))
        if not f then return teml(alt_templ)(t) end

        return f() and teml(templ)(t) or teml(alt_templ)(t)
    end},

    -- If statement: `@if(<<template>+<comp>>){<template>}`
    {"@if%s*%((.+)%)%s*{(.+)}",
    function(t,comp,templ)
        local f = (load or loadstring)(
        "return "..teml(comp)(t))
        if not f then return "" end

        return f() and teml(templ)(t) or ""
    end},

    -- Variable: `$<var-name>`
    {"$(%w+)",
    function(t,vname)
        return str_index(t,vname)
    end},

    -- Enclosed Variable `${<var-name>}`
    {"${(.+)}",
    function(t,vname)
        return str_index(t,vname)
    end},
}

function teml.eval(str)
    return function(temp)
        for _,v in ipairs(patterns) do
            str = str:gsub("("..v[1]..")",function(_,...)
                return tostring(v[2](temp,...))
            end)
        end
        return str
    end
end

return teml
