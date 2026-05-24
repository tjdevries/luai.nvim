local M = {}

---@param text string
---@return string
local function parse_ndjson(text)
  local parts = {}
  for line in text:gmatch("[^\r\n]+") do
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" and decoded.type == "text" then
      if type(decoded.part) == "table" and type(decoded.part.text) == "string" then
        table.insert(parts, decoded.part.text)
      end
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, "")
end

---@param prompt string
---@param model string
---@return string
M.request_generation = function(prompt, model)
  if vim.fn.executable "opencode" ~= 1 then
    error "[luai] Could not find `opencode` on PATH. Install opencode and make sure it is available in your shell."
  end

  local workspace = vim.uv.cwd() or vim.fn.getcwd()
  local cmd = {
    "opencode",
    "run",
    "-m",
    model,
    "--format",
    "json",
    "--dir",
    workspace,
    prompt,
  }
  -- Merge stderr into stdout so we see everything opencode produces.
  local cmdline = {}
  for _, v in ipairs(cmd) do
    cmdline[#cmdline + 1] = vim.fn.shellescape(v)
  end
  local merged = vim.system({
    "bash",
    "-c",
    table.concat(cmdline, " ") .. " 2>&1",
  }, { text = true }):wait()

  local output = merged.stdout or ""
  local exit_code = merged.code

  if exit_code ~= 0 then
    local trimmed = vim.trim(output)
    local details = trimmed ~= "" and trimmed or ("exit code " .. exit_code)
    error(string.format("[luai] opencode request failed: %s", details))
  end

  local response = parse_ndjson(output)

  if response == nil then
    error(string.format(
      "[luai] opencode returned no text response.\nFull output:\n%s",
      output ~= "" and output or "(empty)"
    ))
  end

  return response
end

return M
