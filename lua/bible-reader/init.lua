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

	-- Debug: Show first 100 characters after BOM removal
	vim.notify("First 100 chars (after BOM removal): " .. content:sub(1, 100), vim.log.levels.DEBUG)

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

---Setup telescope picker for Bible translations
function M.setup_telescope()
	local index_data = util.load_index_data()
	if not index_data then
		vim.notify("Failed to load translations index", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	-- Prepare the entries for telescope
	local entries = {}
	for _, lang in ipairs(index_data) do
		for _, version in ipairs(lang.versions) do
			table.insert(entries, {
				language = lang.language,
				name = version.name,
				abbreviation = version.abbreviation,
			})
		end
	end

	pickers
		.new({}, {
			prompt_title = "Bible Translations",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return {
						value = entry.abbreviation,
						display = string.format("%s - %s (%s)", entry.language, entry.name, entry.abbreviation),
						ordinal = string.format("%s %s %s", entry.language, entry.name, entry.abbreviation),
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()

					vim.schedule(function()
						vim.notify("Downloading " .. selection.value .. "...", vim.log.levels.INFO)
						local success, err = M.download_translation(selection.value)

						if success then
							vim.notify("Successfully downloaded " .. selection.value, vim.log.levels.INFO)
						else
							vim.notify(
								"Failed to download " .. selection.value .. ": " .. (err or "unknown error"),
								vim.log.levels.ERROR
							)
						end
					end)
				end)
				return true
			end,
		})
		:find()
end

---@class BibleFormatOptions
---@field max_line_length number Maximum line length for text wrapping (default: 80)
---@field indent_size number Number of spaces to indent wrapped lines (default: 0)
---@field verse_spacing number Number of lines between verses (default: 0)
---@field chapter_header boolean Whether to show chapter header (default: true)
---@field chapter_header_format string Format for chapter header (default: "Chapter %d")

---@class BibleReaderOptions
---@field translation? string Default translation to use (e.g., 'pt_nvi', 'en_kjv')
---@field format? BibleFormatOptions Formatting options for Bible text display

---Setup the plugin with options
---@param opts? BibleReaderOptions Plugin options
function M.setup(opts)
	opts = opts or {}

	-- Set default translation if provided
	if opts.translation then
		local view = require("bible-reader.view")
		view.set_translation(opts.translation)
	end

	-- Set format options if provided
	if opts.format then
		local view = require("bible-reader.view")
		view.set_format_options(opts.format)
	end

	-- Create commands
	vim.api.nvim_create_user_command("BibleDownload", function()
		M.setup_telescope()
	end, {})

	vim.api.nvim_create_user_command("BibleRead", function()
		local view = require("bible-reader.view")
		view.select_book()
	end, {})

	vim.api.nvim_create_user_command("BibleTranslation", function()
		local view = require("bible-reader.view")
		view.select_translation()
	end, {})
end

-- Development reload function
function M.dev_reload()
	-- Clear loaded modules
	package.loaded["bible-reader"] = nil
	package.loaded["bible-reader.view"] = nil
	package.loaded["bible-reader.util"] = nil
	-- Reload the module
	return require("bible-reader")
end

return M
