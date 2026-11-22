-- Writes SavedVariables the way the WoW client does (same syntax; keys are sorted
-- so output is deterministic). Raises on values the client cannot persist, which
-- in game would be silently dropped - almost always a bug in the addon.
local M = {}

local function quote(s)
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
end

local function scalar(v, path)
	local t = type(v)
	if t == "string" then
		return quote(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("SavedVariables: non-finite number at " .. path)
		end
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
			return string.format("%d", v)
		end
		return string.format("%.17g", v)
	end
	error(("SavedVariables: cannot persist a %s (at %s)"):format(t, path))
end

local function sorted_keys(t, n)
	local keys = {}
	for k in pairs(t) do
		local is_array_part = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
		if not is_array_part then
			if type(k) ~= "string" and type(k) ~= "number" then
				error("SavedVariables: unsupported key type " .. type(k))
			end
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then
			return type(a) == "number"
		end
		return a < b
	end)
	return keys
end

local function write(out, v, indent, path, seen)
	if type(v) ~= "table" then
		out[#out + 1] = scalar(v, path)
		return
	end
	if seen[v] then
		error("SavedVariables: cyclic table at " .. path)
	end
	seen[v] = true
	out[#out + 1] = "{\n"
	local n = #v
	local inner = indent .. "\t"
	for i = 1, n do
		out[#out + 1] = inner
		write(out, v[i], inner, path .. "[" .. i .. "]", seen)
		out[#out + 1] = ", -- [" .. i .. "]\n"
	end
	for _, k in ipairs(sorted_keys(v, n)) do
		out[#out + 1] = inner .. "[" .. scalar(k, path) .. "] = "
		write(out, v[k], inner, path .. "." .. tostring(k), seen)
		out[#out + 1] = ",\n"
	end
	out[#out + 1] = indent .. "}"
	seen[v] = nil
end

--- Text of a SavedVariables file holding the given global names from env.
function M.file(env, names)
	local out = {}
	for _, name in ipairs(names) do
		local value = rawget(env, name)
		out[#out + 1] = "\n" .. name .. " = "
		if value == nil then
			out[#out + 1] = "nil"
		else
			write(out, value, "", name, {})
		end
		out[#out + 1] = "\n"
	end
	return table.concat(out)
end

return M
