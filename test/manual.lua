local reload = require("plenary.reload").reload_module
reload "luai"
reload "luai.prompt"
reload "luai.prompt.nvim_api"
reload "luai.path"

-- local generate = require("luai").generate
-- generate.telescope_search_my_neovim_config {}

reload "luai.utils"
reload "luai.utils.split_string_on_vowels"

local dotenv = require "custom.dotenv"
local parsed = dotenv.parse ".env"
require("luai").setup {
  token = parsed.ANTHROPIC_TOKEN,
}

-- require("luai").improve_select()

-- local improve = require("luai").improve
-- improve("luai.utils").greet_a_friend_in_a_popup_window =
--   "The background should ONLY be set for the popup window itself. Not anyewhere else."

local demand = require("luai").demand
local result = demand("luai.utils").greet_a_friend_in_a_popup_window {
  friend_name = "janetacarr",
  background = "green",
}
-- print(vim.inspect(result))

-- generate.select_random_neovim_colorscheme {}

-- generate.create_floating_window {
--   __description = "Create a floating window, with the provided background color.",
--
--   title = "hello world 2",
--   filetype = "lua",
--   background = "green",
--   default = {
--     'print("hello world")',
--   },
-- }

-- generate.create_floating_window =
-- "Let me provide an optional 'default' value which will place that text inside of the buffer that is created"

-- generate.create_floating_window = "I got an error. winhighlight is not a valid option"
-- generate.trim_trailing_whitespace {
--   buffer = 0,
-- }

-- generate.print_all_odd_values_in_table { t = { 1, 2, 3, 4, 5 } }
-- generate.remove_multiple_whitespace_from_string_anywhere_in_text { text = "  hello  world  " }
-- generate.select_random_neovim_colorscheme {}
-- generate.select_random_neovim_colorscheme = "Print the colorscheme that is chosen"
-- print(generate.add_numbers { left = 5, right = 10 })

-- print(generate.count_letters_in_word {
--   __description = "Count the letters!",
--   letter = "r",
--   word = "strawberry",
-- })

-- generate.count_letters_in_word = "Also print each index of the letter in the word"
-- generate.count_letters_in_word = "Print them as you find them, don't store in an intermediate table"
-- generate.count_letters_in_word = "just use print instead of nvim_echo"
--

--[[

- make a new "require" function, called demand

local x = demand("neovim.create_floating_window") { ... }
local x = demand("neovim.create_floating_window", { ... })
local x = demand("custom.module").create_floating_window { ... }

local api = demand("telescope.utils").create_floating_window {
  width = 40,
  height = 20,
  title = "hello world",
  filetype = "lua",
}

-- -> lua/telescope/utils/create_floating_window.lua

--]]
