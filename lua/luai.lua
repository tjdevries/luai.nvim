--[[
TODO:
- Make async version of generation, where it's not required, just generate one
- Make async version when `callback` is specified, since you can just execute the callback later

```lua
-- This would happen asynchronously, we don't have to wait for the generation
demand("my.plugin").do_something_cool {
  callback = function(err, result)
    print(err, result)
  end
}
```

--]]

local curl = require "plenary.curl"
local path = require "luai.path"

local M = {}

local api_key = nil

-- Basepath for generated functions from luai, that are not from `demand(...)`
local basepath = vim.fs.joinpath(vim.fn.stdpath "data" --[[@as string]], "luai", "generated")
vim.fn.mkdir(basepath, "p")

-- Temp file that we use since the prompts can be very large. Curl likes this much better
LUAI_TMP_FILE = LUAI_TMP_FILE or vim.fn.tempname()

---@class luai.Settings
---@field token string: The token to use for the anthropic API. Currently only supporting anthropic. Don't know if I'll take any PRs, btw.

---@class luai.GeneratedFunction
---@field function_name string
---@field filepath string
---@field history luai.RawGeneratedFunctionResult[]
---@field implementation function

---@class luai.WriteFileOptions
---@field function_name string
---@field filepath string
---@field history luai.RawGeneratedFunctionResult[]
---@field implementation string

---@class luai.RawGeneratedFunctionResult
---@field version number
---@field option_list string
---@field option_example table
---@field description string
---@field thoughts string
---@field implementation string

---@class luai.GenerateFunctionOpts
---@field function_name string
---@field options table

--- Setup the luai module. This must be called before using the module.
---@param opts luai.Settings
M.setup = function(opts)
  assert(opts.token, "[luai] must have anthropic token")
  api_key = opts.token
end

--- Get the generated file
---@param name string
---@return string
local get_generated_filepath = function(name)
  ---@diagnostic disable-next-line: param-type-mismatch
  return vim.fs.joinpath(basepath, name .. ".lua")
end

--- Read the generated file from disk
---@param filepath string: The path to the existing generated file
---@return luai.GeneratedFunction?
local read_generated_file = function(filepath)
  if vim.fn.filereadable(filepath) == 1 then
    local generated = loadfile(filepath)()
    generated.history = vim.json.decode(generated.history)
    for _, v in ipairs(generated.history) do
      if type(v.option_example) == "string" then
        v.option_example = vim.json.decode(v.option_example)
      end
    end

    return generated
  end

  return nil
end

--- Write the generated file to disk
---@param options luai.WriteFileOptions
local write_generate_file = function(options)
  assert(options.implementation, "must have implementation to write")

  local file_contents = string.format(
    [[
return setmetatable({
  history = [==[ %s ]==],
  implementation = function()
%s
  end,
}, { __call = function(self, ...) return self.implementation()(...) end })
]],
    vim.json.encode(options.history),
    options.implementation
  )

  vim.fn.writefile(vim.split(file_contents, "\n"), options.filepath)
  vim.system({ "stylua", options.filepath }):wait()

  print(string.format("[luai] wrote new updated file: %s", options.filepath))
end

--- Generate a new function
---@param opts luai.GenerateFunctionOpts
---@return luai.RawGeneratedFunctionResult
local generate_new_function = function(opts)
  print("[luai] generating new function:", opts.function_name)

  local new_prompt = require "luai.prompt"(opts)
  local system = new_prompt.system
  local messages = new_prompt.messages

  local json_body = vim.json.encode {
    model = "claude-3-5-sonnet-20241022",
    stream = false,
    max_tokens = 4096,
    temperature = 0.1,
    system = system,
    messages = messages,
    stop_sequences = { "</lua_function>" },
  }

  vim.fn.writefile(vim.split(json_body, "\n"), LUAI_TMP_FILE)

  local ok, response = pcall(curl.post, {
    timeout = 1000 * 60,
    url = "https://api.anthropic.com/v1/messages",
    headers = {
      ["x-api-key"] = api_key,
      ["content-type"] = "application/json",
      ["anthropic-version"] = "2023-06-01",
      ["anthropic-beta"] = "prompt-caching-2024-07-31",
    },
    body = LUAI_TMP_FILE,
  })

  if not ok then
    error { error = true }
  end

  local decoded = vim.json.decode(response.body)
  if not decoded.content then
    error(string.format("Could not find content in response: %s", response.body))
  end

  -- print(vim.inspect(decoded.usage))
  local text = decoded.content[1].text

  -- get everything after <lua_function>
  local thoughts = vim.trim(text:match "(.*)<lua_function>")
  local implementation = vim.trim(text:match "<lua_function>(.*)")

  return {
    thoughts = thoughts,
    implementation = implementation,
    description = new_prompt.description,
    option_list = new_prompt.option_list,
    option_example = new_prompt.option_example,
  }
end

local function find_module(module, file)
  local parts = vim.split(module, ".", { plain = true })
  local paths = vim.api.nvim_get_runtime_file(vim.fs.joinpath("lua", parts[1]), true)
  if #paths == 1 then
    -- Replace the basepath
    parts[1] = paths[1]

    -- Append the file
    table.insert(parts, file .. ".lua")
    return vim.fs.joinpath(unpack(parts))
  end

  error "could not find module"
end

local function get_module_path(module) end

local store_new_function = function(filepath, key, new_function)
  ---@type luai.WriteFileOptions
  local generated = {
    function_name = key,
    filepath = filepath,
    history = {
      {
        version = 1,
        option_list = new_function.option_list,
        option_example = new_function.option_example,
        thoughts = new_function.thoughts,
        description = new_function.description,
        implementation = new_function.implementation,
      },
    },
    implementation = new_function.implementation,
  }

  write_generate_file(generated)
end

local update_existing_generation = function(filepath, function_name, value)
  local generated = assert(read_generated_file(filepath), "existing func")
  local latest_history = generated.history[#generated.history]

  local options
  if type(value) == "table" then
    options = vim.deepcopy(value)
  elseif type(value) == "string" then
    options = vim.deepcopy(latest_history.option_example)
    options.__description = value
  else
    error "Unsupported type"
  end

  ---@diagnostic disable-next-line: inject-field
  options.__history = string.format(
    [[
Previously, you thought:

<previous_thoughts>
%s
</previous_thoughts>

And you generated the implementation:
<previous_implementation>
%s
</previous_implementation>
]],
    latest_history.thoughts,
    latest_history.implementation
  )

  local updated = generate_new_function {
    function_name = function_name,
    options = options,
  }

  local history = vim.deepcopy(generated.history)
  table.insert(history, {
    version = 1,
    option_list = updated.option_list,
    option_example = vim.json.encode(updated.option_example),
    thoughts = updated.thoughts,
    description = updated.description,
    implementation = updated.implementation,
  })

  ---@type luai.WriteFileOptions
  local towrite = {
    function_name = function_name,
    filepath = filepath,
    history = history,
    implementation = updated.implementation,
  }
  write_generate_file(towrite)
end

---@class luai.CachedGeneration
---@field stat uv.aliases.fs_stat_table
---@field fn function
local cached = {}

local Generated = {}
Generated.__index = Generated

M.generate = setmetatable({}, Generated)

--- Get the generated function from the cache, or generate a new one if it doesn't exist
---@param key string
---@return function
function Generated:__index(key)
  local filepath = get_generated_filepath(key)

  -- Save things into memory, so we don't read from disk all the time
  if cached[key] and not path.is_file_newer(filepath, cached[key].stat) then
    return cached[key].fn
  end

  -- Read things from disk, so we don't ask AI to generate every time
  local generated_filepath = get_generated_filepath(key)
  local result = read_generated_file(generated_filepath)
  if result then
    local fn = result.implementation()
    cached[key] = {
      fn = fn,
      stat = vim.uv.fs_stat(filepath),
    }

    return fn
  end

  -- Generate new function from AI.
  return function(opts)
    local prompt = opts.__prompt

    local new_function = generate_new_function {
      function_name = key,
      options = opts,
    }

    if prompt then
      local win = require("luai.win").popup {
        name = "luai-implementation.lua",
        filetype = "lua",
      }

      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(new_function.implementation, "\n"))
      vim.cmd.redraw()

      local accept = vim.fn.input { prompt = "Accept (y/n)? ", default = "y", cancelreturn = "n" }
      pcall(vim.api.nvim_buf_delete, vim.api.nvim_win_get_buf(win), { force = true })
      pcall(vim.api.nvim_win_close, win, true)

      if accept ~= "y" then
        -- TODO: Re-request it
        return
      end
    end

    store_new_function(filepath, key, new_function)

    -- Load via cache mechanisms
    return M.generate[key](opts)
  end
end

function Generated:__newindex(key, value)
  local generated_filepath = get_generated_filepath(key)
  local generated = assert(read_generated_file(generated_filepath), "existing func")
  local latest_history = generated.history[#generated.history]

  local options
  if type(value) == "table" then
    options = vim.deepcopy(value)
  elseif type(value) == "string" then
    options = vim.deepcopy(latest_history.option_example)
    options.__description = value
  else
    error "Unsupported type"
  end

  ---@diagnostic disable-next-line: inject-field
  options.__history = string.format(
    [[
Previously, you thought:

<previous_thoughts>
%s
</previous_thoughts>

And you generated the implementation:
<previous_implementation>
%s
</previous_implementation>
]],
    latest_history.thoughts,
    latest_history.implementation
  )

  local updated = generate_new_function {
    function_name = key,
    options = options,
  }

  local history = vim.deepcopy(generated.history)
  table.insert(history, {
    version = 1,
    option_list = updated.option_list,
    option_example = vim.json.encode(updated.option_example),
    thoughts = updated.thoughts,
    description = updated.description,
    implementation = updated.implementation,
  })

  ---@type luai.WriteFileOptions
  local towrite = {
    function_name = key,
    filepath = get_generated_filepath(key),
    history = history,
    implementation = updated.implementation,
  }
  write_generate_file(towrite)
end

-- after you use demand, if you like it...
-- you just replace it with require
M.demand = function(module)
  -- generate: lua/luai/utils/init.lua
  -- generate: lua/luai/utils/split_string_on_vowels.lua
  local init_file = find_module(module, "init")

  -- If we haven't generated the init file, then we need to generate it.
  if not vim.uv.fs_stat(init_file) then
    vim.fn.mkdir(vim.fn.fnamemodify(init_file, ":h"), "p")
    local contents = string.format([[return require("luai")._require_init("%s")]], module)
    vim.fn.writefile({ contents }, init_file)
  end

  return require(module)
end

--- Improve a function that already exists. This must have been generated already.
---@param module string
---@return table
M.improve = function(module)
  return setmetatable({}, {
    __newindex = function(_, function_name, value)
      local generated_filepath = find_module(module, function_name)
      assert(vim.uv.fs_stat(generated_filepath), "generated function file must exist already")

      update_existing_generation(generated_filepath, function_name, value)
    end,
  })
end

--- Used by modules created from `demand`. This is not meant to be used by the user.
---@param module string
---@return table
M._require_init = function(module)
  return setmetatable({}, {
    __index = function(_, key)
      local path_fn = string.format("%s.%s", module, key)
      local ok, fn = pcall(require, path_fn)
      if not ok then
        return function(options)
          local filepath = find_module(module, key)

          local new_function = generate_new_function {
            function_name = key,
            options = options,
          }
          store_new_function(filepath, key, new_function)

          return require(path_fn)(options)
        end
      end

      return fn
    end,
  })
end

M.improve_select = function()
  local possible_inits = vim.api.nvim_get_runtime_file("lua/**/init.lua", true)

  local generated_inits = {}
  for _, file in ipairs(possible_inits) do
    local lines = vim.fn.readfile(file)
    if vim.startswith(lines[1], 'return require("luai")._require_init("') then
      table.insert(generated_inits, file)
    end
  end

  local items = {}
  for _, init in ipairs(generated_inits) do
    local dir = vim.fn.fnamemodify(init, ":h")
    local dirparts = vim.split(dir, "/lua/", { plain = true })
    table.remove(dirparts, 1)
    local module = table.concat(dirparts, "."):gsub("/", ".")

    for file in vim.fs.dir(dir) do
      if file ~= "init.lua" then
        table.insert(items, {
          module = module,
          fn = vim.fn.fnamemodify(file, ":r"),
          path = vim.fs.joinpath(dir, file),
        })
      end
    end
  end

  vim.ui.select(items, {
    prompt = "Which function to improve?",
    format_item = function(choice)
      return string.format('require("%s").%s', choice.module, choice.fn)
    end,
  }, function(choice)
    if choice then
      vim.schedule(function()
        local improvement = vim.fn.input "Improvement Prompt: "
        M.improve(choice.module)[choice.fn] = improvement
      end)
    end
  end)
end

return M
