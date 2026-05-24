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

local path = require "luai.path"

local M = {}
local config = {
  provider = "cursor",
  model = "composer-2-fast",
}

-- Basepath for generated functions from luai, that are not from `demand(...)`
local basepath = vim.fs.joinpath(vim.fn.stdpath "data" --[[@as string]], "luai", "generated")
vim.fn.mkdir(basepath, "p")

---@class luai.Settings
---@field provider? string: Default LLM provider. Defaults to `cursor`.
---@field model? string: Default Agent model. Defaults to `composer-2-fast`.

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
---@field option_list string
---@field option_example table
---@field description string
---@field implementation string

---@class luai.GenerateFunctionOpts
---@field function_name string
---@field options table

--- Setup the luai module. This is currently optional and kept for API compatibility.
---@param opts? luai.Settings
M.setup = function(opts)
  opts = opts or {}
  config = vim.tbl_extend("force", config, opts)
end

---@param implementation string
---@return boolean
---@return string?
local validate_generated_code = function(implementation)
  local loader = loadstring or load
  local _, err = loader(implementation)
  if err then
    return false, err
  end

  return true
end

---@param response_text string
---@return string
local normalize_generated_code = function(response_text)
  local normalized = vim.trim(response_text)
  if normalized == "" then
    error "[luai] Cursor Agent returned an empty response."
  end

  local candidates = { normalized }

  local fenced = normalized:match("```lua%s*(.-)%s*```") or normalized:match("```%s*(.-)%s*```")
  if fenced then
    table.insert(candidates, vim.trim(fenced))
  end

  local tagged = normalized:match "<lua_function>%s*(.-)%s*</lua_function>"
  if tagged then
    table.insert(candidates, vim.trim(tagged))
  end

  local start = normalized:find("return%s+function%s*%(")
  if start then
    local lines = vim.split(normalized:sub(start), "\n")
    for last = #lines, 1, -1 do
      local candidate_lines = {}
      for i = 1, last do
        table.insert(candidate_lines, lines[i])
      end

      table.insert(candidates, vim.trim(table.concat(candidate_lines, "\n")))
    end
  end

  for _, candidate in ipairs(candidates) do
    if candidate ~= "" and candidate:match "^return%s+function%s*%(" then
      local ok = validate_generated_code(candidate)
      if ok then
        return candidate
      end
    end
  end

  error(string.format(
    "[luai] Cursor Agent response did not contain valid Lua starting with `return function(opts)`:\n%s",
    response_text
  ))
end

---@param prompt string
---@param provider string
---@param model string
---@return string
local request_generation = function(prompt, provider, model)
  if provider == nil or provider == "" then
    vim.notify("[luai] provider is required", vim.log.levels.ERROR)
    return ""
  end

  if model == nil or model == "" then
    vim.notify("[luai] model is required", vim.log.levels.ERROR)
    return ""
  end

  if not provider:match "^[%w_%-%+]+$" then
    vim.notify(
      string.format("[luai] provider '%s' contains invalid characters. Only alphanumeric, _, -, + are allowed.", provider),
      vim.log.levels.ERROR
    )
    return ""
  end

  local p = require("luai.provider_" .. provider)
  return p.request_generation(prompt, model)
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

---@param value any
---@return string
local format_json_for_history = function(value)
  local encoded = vim.json.encode(value)
  if vim.fn.executable "jq" ~= 1 then
    return encoded
  end

  local result = vim.system({ "jq", "--sort-keys", "." }, {
    stdin = encoded,
    text = true,
  }):wait()

  if result.code ~= 0 then
    return encoded
  end

  return vim.trim(result.stdout or "")
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
    format_json_for_history(options.history),
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
  local provider = opts.options.__provider or config.provider
  local model = opts.options.__model or config.model
  local response_text = request_generation(new_prompt.prompt, provider, model)
  local implementation = normalize_generated_code(response_text)

  return {
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

---@param options table
---@param latest_history luai.RawGeneratedFunctionResult
local add_previous_implementation_context = function(options, latest_history)
  ---@diagnostic disable-next-line: inject-field
  options.__history = string.format(
    [[
Here is the previous implementation. Keep the parts that are still correct and update it to satisfy the new request.

Previous implementation:
%s
]],
    latest_history.implementation
  )
end

local store_new_function = function(filepath, key, new_function)
  ---@type luai.WriteFileOptions
  local generated = {
    function_name = key,
    filepath = filepath,
    history = {
      {
        option_list = new_function.option_list,
        option_example = new_function.option_example,
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

  add_previous_implementation_context(options, latest_history)

  local updated = generate_new_function {
    function_name = function_name,
    options = options,
  }

  local history = vim.deepcopy(generated.history)
  table.insert(history, {
    option_list = updated.option_list,
    option_example = vim.json.encode(updated.option_example),
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

  add_previous_implementation_context(options, latest_history)

  local updated = generate_new_function {
    function_name = key,
    options = options,
  }

  local history = vim.deepcopy(generated.history)
  table.insert(history, {
    option_list = updated.option_list,
    option_example = vim.json.encode(updated.option_example),
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

local generated_module_pattern = '^return require%("luai"%)%._require_init%("([^"]+)"%)'

---@return table[]
local get_generated_modules = function()
  local possible_inits = vim.api.nvim_get_runtime_file("lua/**/init.lua", true)
  local items = {}
  for _, file in ipairs(possible_inits) do
    local lines = vim.fn.readfile(file)
    local module = lines[1] and lines[1]:match(generated_module_pattern)
    if module then
      table.insert(items, {
        module = module,
        dir = vim.fn.fnamemodify(file, ":h"),
        init = file,
      })
    end
  end

  table.sort(items, function(left, right)
    return left.module < right.module
  end)

  return items
end

---@param module_item table
---@return table[]
local get_generated_functions_for_module = function(module_item)
  local items = {}
  for file, filetype in vim.fs.dir(module_item.dir) do
    if filetype == "file" and file ~= "init.lua" and vim.endswith(file, ".lua") then
      table.insert(items, {
        module = module_item.module,
        fn = vim.fn.fnamemodify(file, ":r"),
        path = vim.fs.joinpath(module_item.dir, file),
      })
    end
  end

  table.sort(items, function(left, right)
    return left.fn < right.fn
  end)

  return items
end

---@param module string|table
---@return table?
local resolve_generated_module = function(module)
  if type(module) == "table" then
    return module
  end

  for _, item in ipairs(get_generated_modules()) do
    if item.module == module then
      return item
    end
  end
end

---@param choice table
local prompt_for_improvement = function(choice)
  vim.schedule(function()
    local improvement = vim.fn.input(string.format('Improve `require("%s").%s`: ', choice.module, choice.fn))
    if improvement == nil or vim.trim(improvement) == "" then
      return
    end

    M.improve(choice.module)[choice.fn] = improvement
  end)
end

---@param module string|table
M.improve_module_select = function(module)
  local module_item = resolve_generated_module(module)
  assert(module_item, string.format("[luai] Could not find generated module: %s", module))

  local items = get_generated_functions_for_module(module_item)
  if vim.tbl_isempty(items) then
    vim.notify(string.format("[luai] No generated functions found for %s", module_item.module))
    return
  end

  vim.ui.select(items, {
    prompt = string.format("Which function in %s should be improved?", module_item.module),
    format_item = function(choice)
      return string.format('require("%s").%s', choice.module, choice.fn)
    end,
  }, function(choice)
    if choice then
      prompt_for_improvement(choice)
    end
  end)
end

M.improve_select = function()
  local items = get_generated_modules()
  if vim.tbl_isempty(items) then
    vim.notify "[luai] No generated modules found on runtimepath."
    return
  end

  vim.ui.select(items, {
    prompt = "Which module should be improved?",
    format_item = function(choice)
      return choice.module
    end,
  }, function(choice)
    if choice then
      vim.schedule(function()
        M.improve_module_select(choice)
      end)
    end
  end)
end

return M
