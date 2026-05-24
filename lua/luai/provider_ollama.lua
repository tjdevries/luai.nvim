local M = {}

---@param text string
---@return string
local function strip_ansi(text)
  text = text:gsub("\27%[[0-9;]*[A-Za-z]", "")
  text = text:gsub("\27[A-Za-z]", "")
  text = text:gsub("\27", "")
  return text
end

---@param prompt string
---@param model string
---@return string
M.request_generation = function(prompt, model)
  if vim.fn.executable "ollama" ~= 1 then
    error "[luai] Could not find `ollama` on PATH. Install Ollama and make sure it is available in your shell."
  end

  local cmd = {
    "ollama",
    "run",
    model,
    prompt,
    "--hidethinking",
    "--nowordwrap",
  }

  local env = vim.deepcopy(vim.fn.environ())
  env["TERM"] = "dumb"

  local result = vim.system(cmd, { text = true, env = env }):wait()

  local stdout = result.stdout or ""
  local stderr = result.stderr or ""

  if result.code ~= 0 then
    stderr = vim.trim(stderr)
    stdout = vim.trim(stdout)
    local details = stderr ~= "" and stderr or stdout
    if details ~= "" then
      error(string.format("[luai] Ollama request failed: %s", details))
    end

    error(string.format("[luai] Ollama request failed with exit code %s", result.code))
  end

  local cleaned = strip_ansi(stdout)
  return vim.trim(cleaned)
end

return M
