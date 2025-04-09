local M = {}
local util = require("bible-reader.util")
local view = require("bible-reader.view")
local bible = require("bible-reader")

local function bible_download_handler()
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

local function bible_read_handler(args)
    if args.args == "" then
        view.select_book()
    else
        -- Parse args format: <book> <chapter> [verse]
        local parts = vim.split(args.args, " ")
        local book = parts[1]
        local chapter = tonumber(parts[2])
        local verse = tonumber(parts[3])

        if book and chapter then
            view.open_chapter(view.get_translation(), book, chapter, verse)
        else
            vim.notify("Usage: BibleRead <book> <chapter> [verse]", vim.log.levels.ERROR)
        end
    end
end

local function bible_read_complete(arg_lead)
    local bible_data = bible.load_bible_data(view.get_translation())
    if not bible_data then
        return {}
    end

    local completions = {}
    for _, book in ipairs(bible_data) do
        if book.abbrev and book.abbrev:lower():find(arg_lead:lower(), 1, true) then
            table.insert(completions, book.abbrev)
        end
    end
    return completions
end

local function bible_translation_handler(args)
    if args.args == "" then
        view.select_translation()
    else
        local translation = args.args:lower()
        local available_translations = bible.get_available_translations()

        -- Check if translation is downloaded
        local translation_exists = false
        for _, t in ipairs(available_translations) do
            if t:lower() == translation then
                translation_exists = true
                break
            end
        end

        if not translation_exists then
            vim.notify(
                string.format(
                    "Translation '%s' is not downloaded. Available translations: %s",
                    translation,
                    table.concat(available_translations, ", ")
                ),
                vim.log.levels.ERROR
            )
            return
        end

        view.set_translation(translation)
        vim.notify(string.format("Changed translation to %s", translation:upper()), vim.log.levels.INFO)

        -- Refresh current view if a chapter is open
        local current = view.get_current_view()
        if current then
            view.open_chapter(translation, current.book_index, current.chapter, current.verse)
        end
    end
end

local function bible_translation_complete(arg_lead)
    local translations = bible.get_available_translations()
    local completions = {}
    for _, translation in ipairs(translations) do
        if translation:lower():find(arg_lead:lower(), 1, true) then
            table.insert(completions, translation)
        end
    end
    return completions
end

function M.setup()
    vim.api.nvim_create_user_command("BibleDownload", bible_download_handler, {})
    vim.api.nvim_create_user_command("BibleRead", bible_read_handler, {
        nargs = "*",
        complete = bible_read_complete,
    })
    vim.api.nvim_create_user_command("BibleTranslation", bible_translation_handler, {
        nargs = "?",
        complete = bible_translation_complete,
    })
end

return M
