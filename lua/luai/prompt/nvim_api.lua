local remove_all_comments = function(text)
  local lines = vim.split(text, "\n")

  local result = {}
  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if not vim.startswith(line, "--") and not vim.startswith(line, "error") and line ~= "" then
      table.insert(result, line)
    end
  end

  return table.concat(result, "\n")
end

local remove_function_and_end = function(text)
  local lines = vim.split(text, "\n")

  local result = {}
  for _, line in ipairs(lines) do
    line = line:gsub("^function ", "")
    line = line:gsub("end$", "")
    table.insert(result, line)
  end

  return table.concat(result, "\n")
end

local metas = {
  {
    name = "api.lua",
    description = "The following are type stups for all the functions available on `vim.api.*`. "
      .. "Prefer these functions where possible. ",
    process = { remove_all_comments, remove_function_and_end },
  },
  { name = "builtin.lua", description = "Various APIs that are provided by neovim, that are unique to the Lua API" },
  { name = "api_keysets.lua", description = "The following describe various types that are used in neovim's API" },
  { name = "api_keysets_extra.lua", description = "Additional types that are used in neovim's API" },
  { name = "builtin_types.lua", description = "Various types used by Neovim's builtin APIs" },
  {
    name = "vimfn.lua",
    description = "Functions avaiable from Neovim's vimscript APIs. They are available via vim.fn",
    process = { remove_all_comments, remove_function_and_end },
  },
  -- { name = "vvars.lua", description = "Various vimscript variables" },
}

local read = {}

for _, meta in ipairs(metas) do
  local file = vim.api.nvim_get_runtime_file("lua/vim/_meta/" .. meta.name, false)[1]
  if file then
    local lines = vim.fn.readfile(file)
    for i, line in ipairs(lines) do
      lines[i] = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    end

    local text = table.concat(lines, "\n")
    if meta.process then
      for _, fn in ipairs(meta.process) do
        text = fn(text)
      end
    end

    table.insert(read, "-----")
    table.insert(read, meta.description)
    table.insert(read, text)
  end
end

local result = table.concat(read, "\n\n")
-- vim.api.nvim_buf_set_lines(302, 0, -1, false, vim.split(result, "\n"))

return result
