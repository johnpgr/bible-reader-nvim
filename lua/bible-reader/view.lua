local M = {}

---@class ViewConfig
---@field translation string Current translation being viewed
---@field book string Current book being viewed
---@field chapter number Current chapter being viewed
---@field verse number? Current verse being viewed

---@type ViewConfig|nil
local current_view = nil

---@class FormatOptions
---@field max_line_length number Maximum line length for text wrapping
---@field indent_size number Number of spaces to indent wrapped lines
---@field verse_spacing number Number of lines between verses
---@field chapter_header boolean Whether to show chapter header
---@field chapter_header_format string Format for chapter header

-- Default format options
local format_options = {
	max_line_length = 80,
	indent_size = 0,
	verse_spacing = 0,
	chapter_header = true,
	chapter_header_format = "Chapter %d",
}

---Set format options for Bible display
---@param opts BibleFormatOptions
function M.set_format_options(opts)
	format_options.max_line_length = opts.max_line_length or format_options.max_line_length
	format_options.indent_size = opts.indent_size or format_options.indent_size
	format_options.verse_spacing = opts.verse_spacing or format_options.verse_spacing
	format_options.chapter_header = opts.chapter_header ~= nil and opts.chapter_header or format_options.chapter_header
	format_options.chapter_header_format = opts.chapter_header_format or format_options.chapter_header_format
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
			prompt_title = "Bible Translations",
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
					vim.notify("Changed translation to " .. selection.value:upper(), vim.log.levels.INFO)
				end)
				return true
			end,
		})
		:find()
end

---Format verse number as superscript
---@param num number
---@return string
local function to_superscript(num)
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
	local res, _ = string.gsub(tostring(num), ".", function(c)
		return superscripts[c] or c
	end)

	return res
end

---Create winbar text for Bible reading
---@param view ViewConfig
---@return string
local function make_winbar(view)
	return string.format("%s | %s %d", view.translation:upper(), view.book, view.chapter)
end

---Format chapter content for display
---@param verses BibleVerse[]
---@return string[]
local function format_chapter(verses)
	local lines = {}
	local current_line = ""
	local line_length = 0
	local indent = string.rep(" ", format_options.indent_size)
	local max_length = format_options.max_line_length

	-- Add chapter header if enabled
	if format_options.chapter_header and current_view then
		table.insert(lines, string.format(format_options.chapter_header_format, current_view.chapter))
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
			local prefix = is_line_start and (line_length > 0 and indent or "") or " "
			local word_with_space = (is_line_start and "" or " ") .. word

			if line_length + #word_with_space > max_length and line_length > 0 then
				table.insert(lines, current_line)
				current_line = indent .. word
				line_length = #indent + #word
			else
				if current_line ~= "" then
					current_line = current_line .. " "
					line_length = line_length + 1
				end
				current_line = current_line .. word
				line_length = line_length + #word
			end
		end

		-- End of verse
		if current_line ~= "" then
			table.insert(lines, current_line)
			current_line = ""
			line_length = 0
		end

		-- Add verse spacing if configured
		if format_options.verse_spacing > 0 then
			for _ = 1, format_options.verse_spacing do
				table.insert(lines, "")
			end
		end
	end

	return lines
end

---Open a Bible chapter for reading
---@param translation string Translation identifier
---@param book string Book abbreviation
---@param chapter number Chapter number
---@param verse? number Optional verse number to focus on
function M.open_chapter(translation, book, chapter, verse)
	local bible = require("bible-reader")
	local bible_data = bible.load_bible_data(translation)
	if not bible_data then
		vim.notify("Failed to load Bible data", vim.log.levels.ERROR)
		return
	end

	-- Find the book by abbreviation
	local book_data
	for _, b in ipairs(bible_data) do
		if b.abbrev == book:lower() then
			book_data = b
			break
		end
	end

	if not book_data then
		vim.notify("Book not found: " .. book, vim.log.levels.ERROR)
		return
	end

	-- Get chapter verses
	local chapter_verses = book_data.chapters[chapter]
	if not chapter_verses then
		vim.notify("Chapter not found: " .. chapter, vim.log.levels.ERROR)
		return
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, string.format("bible://%s/%s/%d", translation, book, chapter))

	-- Convert verses to the expected format for format_chapter
	---@type BibleVerse[]
	local verses = {}
	for verse_num, verse_text in ipairs(chapter_verses) do
		table.insert(verses, { verse = verse_num, text = verse_text })
	end

	-- Format verses for display with word wrapping
	local lines = format_chapter(verses)

	-- Set buffer content while it's still modifiable
	vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)

	-- Now set buffer options after content is set
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)

	-- Open in current window
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Set up winbar
	current_view = { translation = translation, book = book, chapter = chapter, verse = verse }
	vim.wo[win].winbar = make_winbar(current_view)
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
				chapters = book.chapters,
				name = book.abbrev:upper(), -- Using abbrev as name temporarily
			})
		end
	end

	if #entries == 0 then
		vim.notify("No valid books found in translation", vim.log.levels.ERROR)
		return
	end

	pickers
		.new({}, {
			prompt_title = "Bible Books",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.name,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					M.open_chapter(current_translation, selection.value.name, 1)
				end)
				return true
			end,
		})
		:find()
end

return M
