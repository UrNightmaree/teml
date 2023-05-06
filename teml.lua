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
	return str == "" or str:match("^%s+$")
end

local function is_number(str, integer)
	if str == "0" then
		return true
	end

	local patt_integer = "^[-+]?[1-9]%d*$"
	local patt_number1 = "^[-+]?[1-9]%d*"
	local patt_number2 = "%.%d+$"

	local _, found_n = str:gsub(patt_number2, "")

	if not integer and str:match(patt_number1) and found_n >= 0 and found_n <= 1 then
		return true
	elseif integer and str:match(patt_integer) then
		return true
	end
	return false
end

local function get_line(str, patt)
	local n = 0
	for s in str:gmatch("([^\n\r]+)") do
		n = n + 1
		if s:match(patt) then
			return n
		end
	end
end

local function str_index(tbl, str)
	local buff = {}
	for s in str:gmatch("([^.]+)") do
		buff[#buff + 1] = s:match("^%d+$") and "[" .. s .. "]" or "['" .. s .. "']"
	end
	local f = (load or loadstring)("return (_VERSION == 'Lua 5.1' and arg or {...})[1]" .. table.concat(buff))
	return f and f(tbl)
end

local function escape(str)
	return str:gsub("%p", "%%%1")
end

local patterns = {
	-- For loop:
	-- `@for(<varname[,varname...]> : <<table-var> / <s>..<e>[..<i>]){<template>}`
	{
		"@for%s*%((.-)%)%s*{(.-)}",
		---@param p PropTable
		---@param s_iter string
		---@param template string
		---@return string?
		---@return string?
		function(p, s_iter, template)
			if is_empty(s_iter) then
				return nil,
					"line "
						.. get_line(p.string, "@for%s*%(" .. s_iter .. "%)%s*{" .. template .. "}")
						.. ": for iter expression is empty."
			end

			s_iter = trim(s_iter)

			local iter_var, iter = {}, nil
			s_iter:gsub("(.+)[ ]*:[ ]*(.+)", function(c1, c2)
				iter = c2
				for s in c1:gmatch("([^,]+)") do
					iter_var[#iter_var + 1] = s
				end
			end)

			local buff = ""
			local tmp_t = shallow_copy(p.table)

			if type(str_index(p.table, iter)) == "table" then
				for i, v in pairs(str_index(p.table, iter)) do
					tmp_t[iter_var[1] or ""] = i
					tmp_t[iter_var[2] or ""] = v
					buff = buff .. teml(template)(tmp_t)
				end
				return buff
			end

			local sei = {}
			for n in iter:gmatch("([^..]+)") do
				sei[#sei + 1] = tonumber(n)
			end

			local st, en, inc = (table.unpack or unpack)(sei)
			if st and en and inc then
				for i = st, en, inc do
					tmp_t[iter_var[1] or ""] = i
					buff = buff .. teml(template)(tmp_t)
				end
			else
				for i = st, en do
					tmp_t[iter_var[1] or ""] = i
					buff = buff .. teml(template)(tmp_t)
				end
			end
			return buff
		end,
	},

	-- If-else statement:
	-- `@if(<<template>+<comp>>){<template>}@else(<alt-template>)
	{
		"@if%s*%((.-)%)%s*{(.-)}%s*@else%s*{(.-)}",
		---@param p PropTable
		---@param comp_exp string
		---@param template string
		---@param alt_template string
		---@return string?
		---@return string?
		function(p, comp_exp, template, alt_template)
			if is_empty(comp_exp) then
				return nil,
					"line " .. get_line(
						p.string,
						"@if%s*%("
							.. escape(comp_exp)
							.. "%)%s*{"
							.. escape(template)
							.. "}%s*@else%s*{"
							.. alt_template
							.. "}"
					) .. ": statement is empty."
			end

			local f = (load or loadstring)("return " .. teml(comp_exp)(p.table))
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
		---@param comp_exp string
		---@param template string
		---@return string?
		---@return string?
		function(p, comp_exp, template)
			if is_empty(comp_exp) then
				return nil,
					"line "
						.. get_line(p.string, "@if%s*%(" .. escape(comp_exp) .. "%)%s*{" .. escape(template) .. "}")
						.. ": statement is empty."
			end

			local f = (load or loadstring)("return " .. teml(comp_exp)(p.table))
			if not f then
				return ""
			end

			return f() and teml(template)(p.table) or ""
		end,
	},

	-- Function call:
	-- `@<func-name>([arg1[,argn...]])`
	{
		"@(%S+)%s*%((.-)%)",
		---@param p PropTable
		---@param func string
		---@param args string
		---@return string?
		---@return string?
		function(p, func, args)
			local fn_args = {}
			for s in args:gmatch("([^,]+)") do
				fn_args[#fn_args + 1] = teml(s)(p.table)
			end

			local ret, err

			if type(teml.functions[func]) == "function" then
				ret, err = teml.functions[func]((table.unpack or unpack)(fn_args))
				err = err
					and "line "
						.. get_line(p.string, "@" .. escape(func) .. "%(" .. escape(args) .. "%)")
						.. ": "
						.. func
						.. ": "
						.. err
			else
				local tmp_func = shallow_copy(teml.functions[func])
				local tmp_lua_func = table.remove(tmp_func, 1)

				local eval_args = {}
				for i, param_type in ipairs(tmp_func) do
					if param_type == "integer" then
						err = not is_number(fn_args[i], true)
								and "line " .. get_line(p.string, "@" .. escape(func) .. "%(" .. escape(args) .. "%)") .. ": " .. func .. ": error on argument #" .. i .. " (expected integer)"
							or nil
						eval_args[i] = not err and tonumber(fn_args[i]) or nil
					elseif param_type == "number" then
						err = not is_number(fn_args[i])
								and "line " .. get_line(p.string, "@" .. escape(func) .. "%(" .. escape(args) .. "%)") .. ": " .. func .. ": error on argument #" .. i .. " (expected number)"
							or nil
						eval_args[i] = not err and tonumber(fn_args[i]) or nil
					else
						eval_args[i] = fn_args[i]
					end

					if err then
						break
					end
				end

				local ok
				ok, ret = pcall(tmp_lua_func, (table.unpack or unpack)(eval_args))

				if not ok and not err and ret then
					err = "line "
						.. get_line(p.string, "@" .. func .. "%(" .. escape(args) .. "%)")
						.. ": "
						.. func
						.. ": "
						.. ret
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
		---@param var_name string
		---@param alt_string string
		---@return string?
		---@return string?
		function(p, var_name, alt_string)
			if is_empty(var_name) then
				return nil,
					"line "
						.. get_line(p.string, "${" .. escape(var_name) .. ":%-" .. escape(alt_string) .. "}")
						.. ": empty variable name."
			end

			return str_index(p.table, var_name) or alt_string
		end,
	},

	-- Use string B if variable A set:
	-- `${<variable-A>:+<string-B>}`
	{
		"${(.-):%+(.-)}",
		---@param p PropTable
		---@param var_name string
		---@param set_string string
		---@return string?
		---@return string?
		function(p, var_name, set_string)
			if is_empty(var_name) then
				return nil,
					"line "
						.. get_line(p.string, "${" .. escape(var_name) .. ":%+" .. escape(set_string) .. "}")
						.. ": empty variable name."
			end

			return str_index(p.table, var_name) and set_string
		end,
	},

	-- Variable: `$<var-name>`
	{
		"$(%w+)",
		---@param p PropTable
		---@param var_name string
		---@return any
		function(p, var_name)
			return str_index(p.table, var_name)
		end,
	},

	-- Enclosed variable `${<var-name>}`
	{
		"${(.-)}",
		---@param p PropTable
		---@param var_name string
		---@return any?
		---@return string?
		function(p, var_name)
			if is_empty(var_name) then
				return nil, "line " .. get_line(p.string, "${" .. escape(var_name) .. "}") .. ": empty variable name."
			end

			return str_index(p.table, var_name)
		end,
	},
}

local functions = {
	["string.rep"] = { string.rep, "string", "number", "string" },
	["string.reverse"] = function(str)
		return str:reverse()
	end,
	["string.sub"] = function(str, i, j)
		if not i or i:match("^[^-+]?%D+$") then
			return nil, "error on argument #2 (expected integer)"
		end
		if j and j:match("^[^-+]?%D+$") then
			return nil, "error on argument #3 (expected integer)"
		end
		return str:sub(tonumber(i), j and tonumber(j))
	end,
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
				local eval_str
				eval_str, err = v[2](prop, ...)

				if not err then
					return tostring(eval_str)
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
