# `luai.nvim`

Generate, Demand, and Improve Lua Functions on the fly.

## Setup

```lua
-- Required:
require("luai").setup {
    -- Right now, I only support anthropic because we use some of the caching stuff.
    -- I don't care, you can send a PR and maybe I won't reject (but likely will).
    token = "ANTHROPIC_TOKEN"
}
```

## Usage

### `demand`

```lua
-- Load demand into the scope.
local demand = require("luai").demand

-- Demand is like `require` - just give it a module name
-- (must have a base module somewhere with a shared name)
--
-- If you have already demanded this function before, it will
-- re-use the generated function. Otherwise, it will generate
-- a function definition for you on the fly, and then save it.
--
-- NOTE: `demand` automatically executes the code. So if you
-- care about that, you should probably use `generate` first ;)
local win = demand("custom.utils").create_floating_window {
    title = "Hello, World!",
    filetype = "lua"
}
```

This will create a new file wherever you have a `lua/custom` folder somewhere in your runtime path.

The folder structure will look like:

```
lua/custom/utils/init.lua
lua/custom/utils/create_floating_window.lua
```

Going forward, you can just `require("custom.utils").create_floating_window` if you want! I made it so that
afterwards, loading it just works as normal with Lua. Or you can delete the file and it will generate something
fresh next time you `demand` it.

### `generate`

You can generate functions with a command:

```vim
:LuaiGenerate
```

This will lead you through several prompts and then generate the code, where you can review it afterwards.

### `improve`

```vim
" The coolest way to use the command:
:LuaiImprove
```

This will open up a selection window for you to select from
all the generated functions you have made so far, and then you
can give it the prompt to fix any existing problems that you have
with the function.
