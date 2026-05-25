# `luai.nvim`

Generate, Demand, and Improve Lua Functions on the fly.

## Setup

`luai.nvim` uses a provider-based architecture. Built-in providers are `cursor`, `opencode`, `ollama`, and `claude`.

```lua
require("luai").setup {
  provider = "cursor",   -- or "opencode", "ollama", "claude"
  model = "composer-2-fast",
}
```

The `opencode` provider expects a model in `provider/model` format:

```lua
require("luai").setup {
  provider = "opencode",
  model = "opencode/big-pickle",
}
```

```lua
require("luai").setup {
  provider = "ollama",
  model = "gemma4:e4b",
}
```

```lua
require("luai").setup {
  provider = "claude",
  model = "claude-sonnet-4-6",
}
```

Additional providers can be easily added via `lua/luai/provider_*.lua` files.

Internally, each provider shells out to its respective CLI and consumes the output; for example the default `cursor` provider will run:

```bash
agent -p --mode ask --output-format json --model composer-2-fast --trust --workspace "$PWD" "<prompt>"
```

The plugin reads the `.result` field from that JSON response and expects raw Lua code that starts with `return function(opts)` and ends with `end`.
If the agent accidentally returns fenced Lua or a small amount of prose before the code, `luai.nvim` will try to normalize that automatically.
You can override the default model for any single generation by passing `__model` in the opts table, for example `generate.some_fn { __model = "gpt-5.4-medium-fast" }`.

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
the generated modules on your runtimepath, then a second selection
for the generated functions inside that module, and finally it will
prompt you for what you want improved.
