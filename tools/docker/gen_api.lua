-- Runs once at image build time (cwd = /opt/wow-api). Turns the pinned WoW API
-- reference data into three artifacts used by the toolchain:
--   api.lua           machine-readable set of real globals / fields / events (used by the test mock)
--   luacheck_std.lua  luacheck std, so calling an API that does not exist is a lint error
--   index.txt         one line per API, searched by `./dev api <pattern>`
-- Sources: Blizzard's own generated API docs (authoritative, current) and
-- Ketho's LuaLS annotations (covers undocumented globals and widget methods).

local function lines_of(cmd)
	local out = {}
	local p = assert(io.popen(cmd))
	for l in p:lines() do
		out[#out + 1] = l
	end
	p:close()
	return out
end

local globals = {} -- name -> { fields = {name -> {fields=...}|true} | nil }
local events = {}
local index = {}

local function global(name)
	globals[name] = globals[name] or {}
	return globals[name]
end

local function field(g, name)
	local t = global(g)
	t.fields = t.fields or {}
	t.fields[name] = t.fields[name] or {}
	return t.fields[name]
end

-- ---------------------------------------------------------------- Blizzard docs
local doc_tables = {}
local function zero()
	return 0
end
local dummy = setmetatable({}, {
	__index = function(t)
		return t
	end,
	__call = function(t)
		return t
	end,
	__add = zero,
	__sub = zero,
	__mul = zero,
	__div = zero,
	__unm = zero,
	__concat = function()
		return ""
	end,
})
local doc_env = setmetatable({
	APIDocumentation = {
		AddDocumentationTable = function(_, t)
			doc_tables[#doc_tables + 1] = t
		end,
	},
}, {
	__index = function()
		return dummy
	end,
})

for _, path in
	ipairs(lines_of("find ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated -name '*.lua' | sort"))
do
	local chunk = assert(loadfile(path))
	setfenv(chunk, doc_env)
	local ok, err = pcall(chunk)
	if not ok then
		io.stderr:write("warn: ", path, ": ", tostring(err), "\n")
	end
end

local function typed(list)
	local parts = {}
	for _, a in ipairs(list or {}) do
		local ty = tostring(a.Type or "?")
		if a.InnerType then
			ty = ty .. "<" .. tostring(a.InnerType) .. ">"
		end
		parts[#parts + 1] = tostring(a.Name) .. ": " .. ty .. (a.Nilable and "?" or "")
	end
	return table.concat(parts, ", ")
end

local function flags(entry)
	local parts = {}
	for k, v in pairs(entry) do
		if type(v) ~= "table" and k ~= "Name" and k ~= "Type" and k ~= "LiteralName" and k ~= "Documentation" then
			parts[#parts + 1] = k .. "=" .. tostring(v)
		end
	end
	table.sort(parts)
	return #parts > 0 and ("  [" .. table.concat(parts, " ") .. "]") or ""
end

local blizz_documented = {}
for _, t in ipairs(doc_tables) do
	local ns = t.Namespace
	for _, f in ipairs(t.Functions or {}) do
		local full
		if ns then
			field(ns, f.Name)
			full = ns .. "." .. f.Name
		else
			global(f.Name)
			full = f.Name
		end
		blizz_documented[full] = true
		local ret = typed(f.Returns)
		index[#index + 1] = "fn     "
			.. full
			.. "("
			.. typed(f.Arguments)
			.. ")"
			.. (ret ~= "" and (" -> " .. ret) or "")
			.. flags(f)
	end
	for _, e in ipairs(t.Events or {}) do
		if e.LiteralName then
			events[e.LiteralName] = true
			index[#index + 1] = "event  " .. e.LiteralName .. "(" .. typed(e.Payload) .. ")" .. flags(e)
		end
	end
	for _, tbl in ipairs(t.Tables or {}) do
		if tbl.Type == "Enumeration" and tbl.Name then
			local e = field("Enum", tbl.Name)
			e.fields = e.fields or {}
			local names = {}
			for _, v in ipairs(tbl.Fields or {}) do
				e.fields[v.Name] = {}
				names[#names + 1] = v.Name .. "=" .. tostring(v.EnumValue)
			end
			index[#index + 1] = "enum   Enum." .. tbl.Name .. " { " .. table.concat(names, ", ") .. " }"
		elseif tbl.Type == "Constants" and tbl.Name then
			local c = field("Constants", tbl.Name)
			c.fields = c.fields or {}
			for _, v in ipairs(tbl.Values or {}) do
				c.fields[v.Name] = {}
			end
		elseif tbl.Type == "Structure" and tbl.Name then
			index[#index + 1] = "struct " .. tbl.Name .. " { " .. typed(tbl.Fields) .. " }"
		end
	end
end

-- ------------------------------------------------------------ Ketho annotations
local methods = {}
for _, path in
	ipairs(lines_of("find annotations/Core annotations/FrameXML -name '*.lua' -not -path '*/Libraries/*' | sort"))
do
	local doc_url
	local in_event_alias = false
	for line in io.lines(path) do
		local url = line:match("^%-%-%-.-%((https?://[^)%s]+)%)")
		if url then
			doc_url = url
		end
		if line:match("^%-%-%-@alias FrameEvent") then
			in_event_alias = true
		elseif in_event_alias then
			local ev = line:match('^%-%-%-|"([%w_]+)"')
			if ev then
				events[ev] = true
			else
				in_event_alias = false
			end
		end

		-- Anything indexed from here is absent from Blizzard's generated docs.
		local suffix = "  [not in Blizzard docs: verify in game]" .. (doc_url and (" -- " .. doc_url) or "")
		local a, b, args = line:match("^function ([%a_][%w_]*)%.([%a_][%w_]*)[%w_.]*(%b())")
		local m_obj, m_name, m_args = line:match("^function ([%a_][%w_]*):([%a_][%w_]*)(%b())")
		local g, g_args = line:match("^function ([%a_][%w_]*)(%b())")
		local av = line:match("^([%a_][%w_]*)%s*=")
		local fa, fb = line:match("^([%a_][%w_]*)%.([%a_][%w_]*)%s*=")
		if a then
			field(a, b)
			if not blizz_documented[a .. "." .. b] then
				index[#index + 1] = "fn     " .. a .. "." .. b .. args .. suffix
			end
		elseif m_obj then
			methods[#methods + 1] = { m_obj, m_name }
			index[#index + 1] = "method "
				.. m_obj
				.. ":"
				.. m_name
				.. m_args
				.. (doc_url and ("  -- " .. doc_url) or "")
		elseif g then
			global(g)
			if not blizz_documented[g] then
				index[#index + 1] = "fn     " .. g .. g_args .. suffix
			end
		elseif av then
			global(av)
			local target = path:find("/Lua/", 1, true) and line:match("^[%w_]+%s*=%s*([%a_][%w_.]*)%s*$")
			if target then
				index[#index + 1] = "alias  " .. av .. " = " .. target
			end
		elseif fa then
			field(fa, fb)
		end
		if not line:match("^%-%-") then
			doc_url = nil
		end
	end
end
for _, m in ipairs(methods) do
	if globals[m[1]] then
		field(m[1], m[2])
	end
end

-- ------------------------------------------------- Blizzard FrameXML Lua source
-- Globals defined by Blizzard's own Lua code (ReloadUI, Mixin, ...). Deliberately
-- loose: this includes load-on-demand Blizzard addons.
for _, path in ipairs(lines_of("find ui-source/Interface/AddOns -name '*.lua' -not -path '*APIDocumentation*' | sort")) do
	local short = path:gsub("^ui%-source/Interface/AddOns/", "")
	for line in io.lines(path) do
		local g, g_args = line:match("^function ([%a_][%w_]*)%s*(%b())")
		if g then
			if not globals[g] then
				index[#index + 1] = "fn     " .. g .. g_args .. "  -- Blizzard Lua: " .. short
			end
			global(g)
		else
			local av = line:match("^([%a_][%w_]*)%s*=[^=]")
			if av then
				global(av)
			end
		end
	end
end

-- Plain Lua 5.1 globals are handled by luacheck's own std and the real interpreter.
for _, name in ipairs({ "_G", "string", "table", "math", "os", "coroutine", "debug", "bit" }) do
	globals[name] = globals[name] and { open = true } or nil
end

-- ----------------------------------------------------------------------- output
local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

-- Only namespaces whose member list we trust to be complete are checked strictly.
local function strict(name)
	return name:match("^C_") or name == "Enum"
end

local function write_fields(out, fields, depth, closed)
	out:write("{")
	if fields and next(fields) then
		out:write("fields={")
		for _, k in ipairs(sorted_keys(fields)) do
			out:write(string.format("[%q]=", k))
			local sub = fields[k]
			if depth < 2 and type(sub) == "table" and sub.fields and next(sub.fields) then
				write_fields(out, sub.fields, depth + 1, closed)
			else
				out:write("{other_fields=true}")
			end
			out:write(",")
		end
		out:write("},")
		if not closed then
			out:write("other_fields=true,")
		end
	else
		out:write("other_fields=true,")
	end
	out:write("}")
end

local std = assert(io.open("luacheck_std.lua", "w"))
std:write("return {read_globals={\n")
for _, name in ipairs(sorted_keys(globals)) do
	std:write(string.format("[%q]=", name))
	write_fields(std, globals[name].fields, 1, strict(name))
	std:write(",\n")
end
std:write("}}\n")
std:close()

local api = assert(io.open("api.lua", "w"))
api:write("return {\nglobals={\n")
for _, name in ipairs(sorted_keys(globals)) do
	local g = globals[name]
	if g.fields and strict(name) then
		api:write(string.format("[%q]={", name))
		for _, k in ipairs(sorted_keys(g.fields)) do
			api:write(string.format("[%q]=true,", k))
		end
		api:write("},\n")
	else
		api:write(string.format("[%q]=true,\n", name))
	end
end
api:write("},\nevents={\n")
for _, name in ipairs(sorted_keys(events)) do
	api:write(string.format("[%q]=true,\n", name))
end
api:write("},\n}\n")
api:close()

table.sort(index)
local idx = assert(io.open("index.txt", "w"))
local last
for _, l in ipairs(index) do
	if l ~= last then
		idx:write(l, "\n")
	end
	last = l
end
idx:close()

local ng, ne = #sorted_keys(globals), #sorted_keys(events)
print(string.format("wow-api: %d globals, %d events, %d index lines", ng, ne, #index))
assert(
	ng > 3000 and ne > 1000,
	"API reference looks incomplete; refusing to build a toolchain that would not catch bad API use"
)
