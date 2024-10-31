return {
  popup = function(opts)
    -- Creates a Neovim floating window with specified options
    assert(opts.name, "Window name is required")
    assert(opts.filetype, "Filetype is required")

    local border = opts.border or "single"
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)

    local buf = vim.fn.bufnr(opts.name, true)
    vim.bo[buf].filetype = opts.filetype

    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = border,
    })

    return win
  end,
}
