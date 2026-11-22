local M = {}

function M.read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

function M.write_file(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

--- Readable dump of any value, for assertion messages.
function M.dump(v, indent)
	indent = indent or ""
	if type(v) ~= "table" then
		return type(v) == "string" and string.format("%q", v) or tostring(v)
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local out = { "{" }
	for _, k in ipairs(keys) do
		out[#out + 1] = indent .. "  " .. tostring(k) .. " = " .. M.dump(v[k], indent .. "  ")
	end
	out[#out + 1] = indent .. "}"
	return table.concat(out, "\n")
end

return M
