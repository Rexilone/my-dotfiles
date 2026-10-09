local o = vim.opt

o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.cursorlineopt = "number"
o.termguicolors = true
o.showmode = false
o.laststatus = 3
o.cmdheight = 1
o.winborder = "rounded"
o.fillchars = { eob = " ", fold = " " }
o.list = true
o.listchars = { tab = "  ", trail = "·", nbsp = "␣" }
o.scrolloff = 8
o.sidescrolloff = 8
o.wrap = false
o.pumheight = 10

o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true

o.ignorecase = true
o.smartcase = true
o.splitright = true
o.splitbelow = true
o.undofile = true
o.swapfile = false
o.updatetime = 250
o.timeoutlen = 400
o.clipboard = "unnamedplus"
o.mouse = "a"
o.confirm = true

vim.diagnostic.config({
  virtual_text = { prefix = "●", spacing = 2 },
  severity_sort = true,
  float = { border = "rounded" },
  signs = { text = { "●", "●", "●", "●" } },
})

-- подсветка скопированного
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- вернуться на последнюю позицию в файле
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(a)
    local mark = vim.api.nvim_buf_get_mark(a.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(a.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
