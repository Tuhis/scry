-- ScryDB: the data contract with external apps. Its shape is specified by
-- schema/ScryDB.schema.json and documented in docs/DATA_CONTRACT.md; any change to
-- what is written here must be reflected there (./dev check enforces it).
local _, ns = ...

local SCHEMA_VERSION = 2

local DB = {}
ns.DB = DB
DB.SCHEMA_VERSION = SCHEMA_VERSION

-- migrations[n] upgrades a database from schemaVersion n to n + 1, in place.
local migrations = {}

-- v1 -> v2: WoW: Forever has no realms (GetRealmName() returns ""), so characters
-- are keyed by their GUID instead of "Name-Realm", and the realm field is gone.
-- Entries without a stored GUID cannot be re-keyed and are dropped.
migrations[1] = function(db)
	local byGuid = {}
	for _, entry in pairs(db.characters or {}) do
		---@type table?
		local c = type(entry) == "table" and type(entry.character) == "table" and entry.character or nil
		if c and type(c.guid) == "string" and c.guid ~= "" then
			c.realm = nil
			byGuid[c.guid] = entry
		end
	end
	db.characters = byGuid
end

-- ScryDB.names: ID -> display name, per kind of ID, for every ID the addon exports.
local NAME_KINDS =
	{ "items", "spells", "skills", "factions", "currencies", "achievements", "traitNodes", "maps", "specs", "quests" }

local function newDB()
	return { schemaVersion = SCHEMA_VERSION, meta = {}, characters = {} }
end

function DB:Init()
	local db = ScryDB
	if type(db) ~= "table" or type(db.schemaVersion) ~= "number" then
		db = newDB()
	elseif db.schemaVersion > SCHEMA_VERSION then
		-- Written by a newer addon version: we cannot know its shape, start over
		-- rather than emit data that violates our own schema.
		ns.Log:Warn("ScryDB schemaVersion " .. db.schemaVersion .. " is newer than supported, resetting")
		db = newDB()
	end
	while db.schemaVersion < SCHEMA_VERSION do
		local migrate = assert(migrations[db.schemaVersion], "missing migration from v" .. db.schemaVersion)
		migrate(db)
		db.schemaVersion = db.schemaVersion + 1
	end
	ScryDB = db
	self.db = db

	-- Names are in the client's language: start over when it changes.
	local locale = GetLocale()
	if type(db.names) ~= "table" or db.names.locale ~= locale then
		db.names = { locale = locale }
	end
	for _, kind in ipairs(NAME_KINDS) do
		db.names[kind] = db.names[kind] or {}
	end

	local gameVersion, _, _, interface = GetBuildInfo()
	db.meta.addonVersion = ns.version
	db.meta.gameVersion = gameVersion
	db.meta.interface = interface
	db.meta.updatedAt = db.meta.updatedAt or GetServerTime()
end

--- GUID of the logged in character, e.g. "Player-6951-00BF5811". WoW: Forever has
--- no realms, and the GUID is unique and stable. Valid from PLAYER_LOGIN on.
function DB:CharKey()
	return UnitGUID("player")
end

--- The current character's section for a module, created on demand.
function DB:Section(moduleName)
	local key = self:CharKey()
	local char = self.db.characters[key]
	if not char then
		char = {}
		self.db.characters[key] = char
	end
	local section = char[moduleName]
	if not section then
		section = {}
		char[moduleName] = section
	end
	return section
end

--- The current character's section for a module, or nil when nothing was recorded yet.
function DB:Peek(moduleName)
	local char = self.db.characters[self:CharKey()]
	return char and char[moduleName]
end

--- Remember the display name of an exported ID. `kind` is one of NAME_KINDS.
--- Does nothing when the client has no name (yet).
function DB:Name(kind, id, text)
	if id and type(text) == "string" and text ~= "" then
		self.db.names[kind][id] = text
	end
end

--- Stamp a section (and the database) as modified now. Call after every write.
function DB:Touch(section)
	local now = GetServerTime()
	section.updatedAt = now
	self.db.meta.updatedAt = now
end
