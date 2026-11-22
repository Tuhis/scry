-- Reads a SavedVariables file (Lua) on stdin, writes all its globals as one JSON
-- object on stdout. The file is executed in an empty sandbox.
--
-- Lua tables are ambiguous in JSON; the mapping here is deliberately mechanical:
--   * keys 1..n exactly      -> array
--   * anything else          -> object, keys converted to strings
--   * empty table            -> {}
-- tools/tasks.py then uses the JSON Schema to fix up the two ambiguous cases
-- (empty arrays, and id-keyed maps that happen to look like arrays).
local source = io.read("*a")
local chunk, err = loadstring(source, "SavedVariables")
if not chunk then
	io.stderr:write("not a valid SavedVariables file: ", tostring(err), "\n")
	os.exit(2)
end
local env = {}
setfenv(chunk, env)
local ok, run_err = pcall(chunk)
if not ok then
	io.stderr:write("not a valid SavedVariables file: ", tostring(run_err), "\n")
	os.exit(2)
end

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function str(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return escapes[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local encode
local function is_array(t)
	local n = #t
	if n == 0 then
		return false
	end
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	return count == n
end

function encode(v, out)
	local t = type(v)
	if t == "table" then
		if is_array(v) then
			out[#out + 1] = "["
			for i = 1, #v do
				if i > 1 then
					out[#out + 1] = ","
				end
				encode(v[i], out)
			end
			out[#out + 1] = "]"
		else
			local keys = {}
			for k in pairs(v) do
				keys[#keys + 1] = k
			end
			table.sort(keys, function(a, b)
				if type(a) ~= type(b) then
					return type(a) == "number"
				end
				return a < b
			end)
			out[#out + 1] = "{"
			for i, k in ipairs(keys) do
				if i > 1 then
					out[#out + 1] = ","
				end
				local key = type(k) == "number" and k == math.floor(k) and string.format("%d", k) or tostring(k)
				out[#out + 1] = str(key) .. ":"
				encode(v[k], out)
			end
			out[#out + 1] = "}"
		end
	elseif t == "string" then
		out[#out + 1] = str(v)
	elseif t == "number" then
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
			out[#out + 1] = string.format("%d", v)
		else
			out[#out + 1] = string.format("%.17g", v)
		end
	elseif t == "boolean" then
		out[#out + 1] = tostring(v)
	else
		out[#out + 1] = "null"
	end
end

local out = {}
encode(env, out)
io.write(table.concat(out), "\n")
