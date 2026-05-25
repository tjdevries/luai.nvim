local M = {}

---@param prompt string
---@param model string
---@return string
M.request_generation = function(prompt, model)
  if vim.fn.executable "claude" ~= 1 then
    error "[luai] Could not find `claude` on PATH. Install Claude CLI and make sure it is available in your shell."
  end

  local result = vim.system({
    "claude",
    "-p",
    "--model",
    model,
    prompt,
  }, { text = true }):wait()

  local stdout = result.stdout or ""
  local stderr = result.stderr or ""

  if result.code ~= 0 then
    stderr = vim.trim(stderr)
    stdout = vim.trim(stdout)
    local details = stderr ~= "" and stderr or stdout
    if details ~= "" then
      error(string.format("[luai] Claude request failed: %s", details))
    end

    error(string.format("[luai] Claude request failed with exit code %s", result.code))
  end

  stdout = vim.trim(stdout)
  if stdout == "" then
    error "[luai] Claude returned an empty response."
  end

  return stdout
end

return M
