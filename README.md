# Bible Reader Plugin for Neovim

A Neovim plugin for reading the Bible directly in your editor with support for multiple translations and a clean, distraction-free reading experience.

## Features

- Multiple Bible translations support
- Telescope integration for easy navigation
- Smart verse formatting and text wrapping
- Internationalization support
- Chapter preview when selecting
- Verse numbers in superscript format
- Customizable display options

## Requirements

- Neovim >= 0.5.0
- telescope.nvim

## Installation

Using packer.nvim:
```lua
use {
    'johnpgr/bible-reader.nvim',
    requires = {'nvim-telescope/telescope.nvim'}
}
```

Using Lazy.nvim
```lua
{
    'johnpgr/bible-reader.nvim',
    dependencies = {'nvim-telescope/telescope.nvim'},
    config = function()
        require('bible-reader').setup({
            -- Format options for Bible display
            format = {
                max_line_length = 80,    -- Maximum line length for text wrapping
                indent_size = 0,         -- Number of spaces to indent wrapped lines
                verse_spacing = 0,       -- Number of lines between verses
                chapter_header = true,   -- Whether to show chapter headers
            },
            -- Default translation (e.g., 'en_kjv' for King James Version)
            default_translation = 'en_kjv',
            -- UI language (default: 'en')
            language = 'en'
        })
    end
}
```

## Configuration

```lua
require('bible-reader').setup({
    -- Format options for Bible display
    format = {
        max_line_length = 80,    -- Maximum line length for text wrapping
        indent_size = 0,         -- Number of spaces to indent wrapped lines
        verse_spacing = 0,       -- Number of lines between verses
        chapter_header = true,   -- Whether to show chapter headers
    },
    -- Default translation (e.g., 'en_kjv' for King James Version)
    default_translation = 'en_kjv',
    -- UI language (default: 'en')
    language = 'en'
})
```
## Data Source

The JSON files used by this plugin for Bible translations and chapters are downloaded from the [thiagobodruk/bible](https://github.com/thiagobodruk/bible) repository. This repository provides structured and open-source Bible data in JSON format, making it easy to integrate various translations and languages into this plugin.

## Usage

### Commands

- `:BibleRead` - Open book selection with Telescope
- `:BibleRead <book abbreviation> <chapter> [verse]` - Open specific book, chapter and verse
- `:BibleTranslation` - Change Bible translation
- `:BibleDownload` - Download available translations
- `:BibleNextChapter` - View next chapter (relative to current chapter)
- `:BiblePreviousChapter`- View previous chapter (relative to current chapter)

### Navigation

Use Telescope interface to:
1. Select a Bible translation
2. Choose a book
3. Pick a chapter

### Customization

The plugin supports:
- Multiple translations
- International UI languages
- Verse spacing and indentation
- Chapter headers
