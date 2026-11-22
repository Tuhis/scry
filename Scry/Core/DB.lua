-- ScryDB: the data contract with external apps. Its shape is specified by
-- schema/ScryDB.schema.json and documented in docs/DATA_CONTRACT.md; any change to
-- what is written here must be reflected there (./dev check enforces it).
local _, ns = ...

local SCHEMA_VERSION = 1

local DB = {}
ns.DB = DB
DB.SCHEMA_VERSION = SCHEMA_VERSION

-- migrations[n] upgrades a database from schemaVersion n to n + 1, in place.
local migrations = {}

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

	local gameVersion, _, _, interface = GetBuildInfo()
	db.meta.addonVersion = ns.version
	db.meta.gameVersion = gameVersion
	db.meta.interface = interface
	db.meta.updatedAt = db.meta.updatedAt or GetServerTime()
end

--- "Name-NormalizedRealm" of the logged in character. Valid from PLAYER_LOGIN on.
function DB:CharKey()
	return UnitName("player") .. "-" .. GetNormalizedRealmName()
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

--- Stamp a section (and the database) as modified now. Call after every write.
function DB:Touch(section)
	local now = GetServerTime()
	section.updatedAt = now
	self.db.meta.updatedAt = now
end
