local M = {}

local i18n = require("bible-reader.i18n").strings

-- Current language for UI strings (default: en)
local current_language = "en"

-- Set UI language
---@param lang string Language code (e.g., 'en', 'pt_br')
function M.set_language(lang)
	if i18n[lang] then
		current_language = lang
	end
end

---Get the current UI language
---@return string
function M.get_language()
	return current_language
end

---@class ViewConfig
---@field translation string Current translation being viewed
---@field book string Current book being viewed
---@field book_index number Current book index being viewed (1-based)
---@field chapter number Current chapter being viewed
---@field verse number? Current verse being viewed

---@type ViewConfig|nil
local current_view = nil

---Get the current view
---@return ViewConfig|nil
function M.get_current_view()
	return current_view
end

-- Default format options
---@type FormatOptions|nil
local format_options = nil

---Set format options for Bible display
---@param opts FormatOptions
function M.set_format_options(opts)
    format_options = {
        max_line_length = opts.max_line_length,
        indent_size = opts.indent_size,
        verse_spacing = opts.verse_spacing,
        chapter_header = opts.chapter_header,
        break_verses = opts.break_verses,
    }
end

-- Default translation (can be changed via setup)
local current_translation = "en_kjv"

---Set the current translation
---@param translation string
function M.set_translation(translation)
	current_translation = translation
end

---Get the current translation
---@return string
function M.get_translation()
	return current_translation
end

---Setup telescope picker for translation selection
function M.select_translation()
	local bible = require("bible-reader")
	local translations = bible.get_available_translations()

	if #translations == 0 then
		vim.notify("No translations available. Use :BibleDownload to download translations.", vim.log.levels.WARN)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = i18n[current_language].bible_translations,
			results_title = "",
			finder = finders.new_table({
				results = translations,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry:upper(),
						ordinal = entry,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					M.set_translation(selection.value)
					vim.notify(
						string.format(i18n[current_language].changed_translation, selection.value:upper()),
						vim.log.levels.INFO
					)

					-- Refresh current view if a chapter is open
					if current_view then
						M.open_chapter(
							selection.value,
							current_view.book_index,
							current_view.chapter,
							current_view.verse
						)
					end
				end)
				return true
			end,
		})
		:find()
end

local superscripts = {
	["0"] = "⁰",
	["1"] = "¹",
	["2"] = "²",
	["3"] = "³",
	["4"] = "⁴",
	["5"] = "⁵",
	["6"] = "⁶",
	["7"] = "⁷",
	["8"] = "⁸",
	["9"] = "⁹",
}

---Format verse number as superscript
---@param num number
---@return string
local function to_superscript(num)
	local res, _ = string.gsub(tostring(num), ".", function(c)
		return superscripts[c] or c
	end)

	return res
end

---Format chapter content for display
---@param verses BibleVerse[]
---@param chapter_num number
---@param book_name string
---@return string[]
local function format_chapter(verses, chapter_num, book_name)
	assert(format_options ~= nil, "Format options not set. Please call M.set_format_options() before formatting.")
	local lines = {}
	local current_line = ""
	local line_length = 0
	local indent = string.rep(" ", format_options.indent_size)
	local max_length = format_options.max_line_length

	-- Add chapter header if enabled
	if format_options.chapter_header then
		local header = string.format("%s %d", book_name:upper(), chapter_num)
		local padding = string.rep("═", math.floor((max_length - #header) / 2))
		table.insert(lines, padding .. " " .. header .. " " .. padding)

		if format_options.verse_spacing > 0 then
			for _ = 1, format_options.verse_spacing do
				table.insert(lines, "")
			end
		end
	end

	for _, verse in ipairs(verses) do
		local verse_text = to_superscript(verse.verse) .. " " .. verse.text
		local words = vim.split(verse_text, " ")

		for _, word in ipairs(words) do
			local is_line_start = current_line == ""
			local word_with_space = (is_line_start and "" or " ") .. word

			if line_length + #word_with_space > max_length and line_length > 0 then
				table.insert(lines, indent .. current_line)
				current_line = word
				line_length = #word
			else
                current_line = is_line_start and word or (current_line .. " " .. word)
                line_length = is_line_start and #word or (line_length + #word_with_space)
			end
		end

		-- End of verse
		if current_line ~= "" then
			if format_options.break_verses then
                table.insert(lines, current_line)
				current_line = ""
				line_length = 0
			end
		end

		-- Add verse spacing if configured
		if format_options.verse_spacing > 0 and format_options.break_verses then
			for _ = 1, format_options.verse_spacing do
				table.insert(lines, "")
			end
		end
	end

	return lines
end

---Setup telescope picker for chapter selection
---@param book table The selected book data
---@param translation string The current translation
local function select_chapter(book, translation)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	-- Create list of chapters
	local chapters = {}
	for i = 1, #book.chapters do
		-- Convert chapter verses to the required format
		local verses = {}
		for verse_num, verse_text in ipairs(book.chapters[i]) do
			table.insert(verses, { verse = verse_num, text = verse_text })
		end

		table.insert(chapters, {
			number = i,
			verses = verses,
		})
	end

	pickers
		.new({}, {
			prompt_title = string.format(i18n[current_language].select_chapter, book.name:upper()),
			finder = finders.new_table({
				results = chapters,
				entry_maker = function(entry)
					return {
						value = entry.number,
						display = string.format(i18n[current_language].chapter, entry.number),
						ordinal = tostring(entry.number),
						verses = entry.verses,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = require("telescope.previewers").new_buffer_previewer({
				title = i18n[current_language].chapter_preview,
				define_preview = function(self, entry)
					-- Format the chapter content using our existing formatter
					local formatted_lines = format_chapter(entry.verses, entry.value, book.name)
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, formatted_lines)

					-- Set buffer options for better preview rendering
					vim.opt_local.wrap = true
					vim.opt_local.linebreak = true
				end,
			}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					M.open_chapter(translation, book.name, selection.value)
				end)
				return true
			end,
		})
		:find()
end

---Open a Bible chapter for reading
---@param translation string Translation identifier
---@param book string|number Book name or index
---@param chapter number Chapter number
---@param verse? number Optional verse number to focus on
function M.open_chapter(translation, book, chapter, verse)
	local bible = require("bible-reader")
	local bible_data = bible.load_bible_data(translation)
	if not bible_data then
		vim.notify("Failed to load Bible data", vim.log.levels.ERROR)
		return
	end

	-- Find the book by index if number, otherwise by name
	local book_data
	local book_index

	if type(book) == "number" then
		book_data = bible_data[book]
		book_index = book
	else
		local book_lower = book:lower()
		for idx, b in ipairs(bible_data) do
			if b.name:lower() == book_lower or b.abbrev:lower() == book_lower then
				book_data = b
				book_index = idx
				break
			end
		end
	end

	if not book_data then
		vim.notify("Book not found: " .. tostring(book) .. " in translation " .. translation, vim.log.levels.ERROR)
		return
	end

	-- Get chapter verses
	local chapter_verses = book_data.chapters[chapter]
	if not chapter_verses then
		vim.notify("Chapter not found: " .. chapter, vim.log.levels.ERROR)
		return
	end

	-- Check for existing buffer and delete it if it exists
	local buf_name = string.format("bible://%s/%s/%d", translation, book_data.name, chapter)
	local existing_buf = vim.fn.bufnr(buf_name)
	if existing_buf ~= -1 then
		vim.api.nvim_buf_delete(existing_buf, { force = true })
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, buf_name)

	-- Convert verses to the expected format for format_chapter
	---@type BibleVerse[]
	local verses = {}
	for verse_num, verse_text in ipairs(chapter_verses) do
		table.insert(verses, { verse = verse_num, text = verse_text })
	end

	-- Format verses for display with word wrapping
	local lines = format_chapter(verses, chapter, book_data.name)

	-- Set buffer content while it's still modifiable
	vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)

	-- Now set buffer options after content is set
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false

	-- Open in current window
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	current_view =
		{ translation = translation, book = book_data.name, book_index = book_index, chapter = chapter, verse = verse }

	-- If a verse is specified, find and move cursor to that verse
	if verse then
		local verse_pattern = to_superscript(verse) .. " "
		for i, line in ipairs(lines) do
			if line:find(verse_pattern, 1, true) then
				vim.api.nvim_win_set_cursor(win, { i, 0 })
				break
			end
		end
	end
end

---Setup telescope picker for Bible books
function M.select_book()
	local bible = require("bible-reader")
	local bible_data = bible.load_bible_data(current_translation)
	if not bible_data then
		vim.notify("Failed to load Bible data for translation: " .. current_translation, vim.log.levels.ERROR)
		return
	end

	-- Debug the data structure
	vim.notify("Bible data type: " .. type(bible_data), vim.log.levels.DEBUG)
	if type(bible_data) == "table" then
		vim.notify("Number of entries: " .. #bible_data, vim.log.levels.DEBUG)
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	-- Prepare the entries for Telescope
	local entries = {}
	for _, book in ipairs(bible_data) do
		if type(book) == "table" and book.abbrev then
			table.insert(entries, {
				abbrev = book.abbrev,
				name = book.name or book.abbrev:upper(),
				chapters = book.chapters,
				total_chapters = #book.chapters,
				total_verses = vim.tbl_count(book.chapters[1]), -- Count verses in first chapter
			})
		end
	end

	if #entries == 0 then
		vim.notify("No valid books found in translation", vim.log.levels.ERROR)
		return
	end

	pickers
		.new({}, {
			prompt_title = i18n[current_language].bible_books,
			results_title = "",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return {
						value = entry,
						display = string.format(i18n[current_language].book_format, entry.name, entry.total_chapters),
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					-- Instead of opening chapter 1, show chapter picker
					select_chapter(selection.value, current_translation)
				end)
				return true
			end,
		})
		:find()
end

return M
