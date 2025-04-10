---@class BibleVerse
---@field text string
---@field verse number

---@class BibleChapter
---@field verses BibleVerse[]
---@field chapter number

---@class BibleBook
---@field chapters BibleChapter[]
---@field name string
---@field abbrev string

---@class BibleTranslation
---@field books BibleBook[]
---@field version string
---@field language string

local M = {}

-- Cache translations data after first load
---@type table<string, BibleTranslation>
local translations_cache = {}

local util = require("bible-reader.util")

---Get available translations in the data directory
---@return string[] translation_files List of available translation files without .json extension
function M.get_available_translations()
	local translations = {}
	local data_dir = util.get_data_dir()

	local handle = vim.uv.fs_scandir(data_dir)
	if handle then
		while true do
			local name, type = vim.uv.fs_scandir_next(handle)
			if not name then
				break
			end
			if type == "file" and name:match("%.json$") and name ~= "index.json" then
				-- Just append to the array without specifying an index
				translations[#translations + 1] = name:gsub("%.json$", "")
			end
		end
	end

	return translations
end

---Load and parse Bible JSON for a specific translation
---@param translation string The translation identifier (e.g., 'pt_aa', 'pt_nvi')
---@return BibleTranslation|nil bible_data The parsed Bible data or nil if not found
function M.load_bible_data(translation)
	-- Return cached data if available
	if translations_cache[translation] then
		return translations_cache[translation]
	end

	local data_dir = util.get_data_dir()
	local bible_path = data_dir .. "/" .. translation .. ".json"

	-- Debug: Check if file exists
	if not vim.loop.fs_stat(bible_path) then
		vim.notify("Bible file does not exist: " .. bible_path, vim.log.levels.ERROR)
		return nil
	end

	-- Read the file content
	local file = io.open(bible_path, "r")
	if not file then
		vim.notify("Could not open Bible data file for translation: " .. translation, vim.log.levels.ERROR)
		return nil
	end
	local content = file:read("*all")
	file:close()

	-- Debug: Check content
	if #content == 0 then
		vim.notify("Bible file is empty: " .. bible_path, vim.log.levels.ERROR)
		return nil
	end

	-- Remove BOM if present
	if content:sub(1, 3) == string.char(0xEF, 0xBB, 0xBF) then
		content = content:sub(4)
	elseif content:sub(1, 2) == string.char(0xFE, 0xFF) or content:sub(1, 2) == string.char(0xFF, 0xFE) then
		content = content:sub(3)
	end

	-- Parse JSON and cache it
	local success, decoded = pcall(vim.json.decode, content)
	if not success then
		-- Remove the file if it's invalid
		os.remove(bible_path)
		vim.notify("Invalid JSON file removed. Please try downloading again.", vim.log.levels.WARN)
		vim.notify(
			"Failed to parse Bible JSON for translation: " .. translation .. "\nError: " .. tostring(decoded),
			vim.log.levels.ERROR
		)
		return nil
	end

	translations_cache[translation] = decoded
	return decoded
end

---@class BibleVersion
---@field name string
---@field abbreviation string

---@class BibleLanguage
---@field language string
---@field versions BibleVersion[]

---Download a Bible translation
---@param abbreviation string The translation identifier (e.g., 'pt_aa')
---@return boolean success
---@return string? error
function M.download_translation(abbreviation)
	if not util.ensure_data_dir() then
		return false, "Failed to create data directory"
	end

	local output_path = string.format("%s/%s.json", util.get_data_dir(), abbreviation)
	local download_url = string.format("%s/%s.json", util.GITHUB_RAW_URL, abbreviation)

	local success, err = util.download_file(download_url, output_path)
	if not success then
		return false, err
	end

	-- Clear the cache for this translation if it exists
	translations_cache[abbreviation] = nil

	return true
end

---@class BibleFormatOptions
---@field max_line_length number Maximum line length for text wrapping (default: 80)
---@field indent_size number Number of spaces to indent wrapped lines (default: 0)
---@field verse_spacing number Number of lines between verses (default: 0)
---@field chapter_header boolean Whether to show chapter header (default: true)
---@field break_verses boolean Whether to start each verse on a new line (default: true)

---@class BibleReaderOptions
---@field translation? string Default translation to use (e.g., 'pt_nvi', 'en_kjv')
---@field format? BibleFormatOptions Formatting options for Bible text display
---@field language? string Language code for UI strings (e.g., 'en', 'pt_br', default: 'en')

-- Default configuration
---@type BibleReaderOptions
local default_config = {
	translation = "en_kjv",
	language = "en",
	format = {
		max_line_length = 80,
		indent_size = 0,
		verse_spacing = 0,
		chapter_header = true,
        break_verses = true,
	},
}

---Setup the plugin with options
---@param opts? BibleReaderOptions Plugin options
function M.setup(opts)
	opts = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Set default translation if provided
	local view = require("bible-reader.view")
	view.set_translation(opts.translation)

	-- Set language for UI strings
	if opts.language then
		view.set_language(opts.language)
	end

	-- Set format options if provided
	view.set_format_options(opts.format)

	local commands = require("bible-reader.commands")
	commands.setup()
end

return M
