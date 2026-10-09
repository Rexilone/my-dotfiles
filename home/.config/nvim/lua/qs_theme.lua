-- тема Neovim по схеме из Quickshell: выбирает colorscheme, подгоняет фон и статуслайн
local M = {}

local function palette()
  local ok, p = pcall(dofile, vim.fn.stdpath("config") .. "/lua/qs_palette.lua")
  return ok and p or {}
end

-- схема шелла -> colorscheme nvim
local schemes = {
  dark = { name = "vague", setup = function() require("vague").setup({}) end },
  wallpaper = { name = "vague", setup = function() require("vague").setup({}) end },
  light = { name = "default" },
  nord = { name = "nord", plugin = "nord.nvim" },
  gruvbox = { name = "gruvbox", plugin = "gruvbox.nvim", setup = function() require("gruvbox").setup({ contrast = "hard" }) end },
  rose = { name = "rose-pine", plugin = "rose-pine", setup = function() require("rose-pine").setup({ variant = "main" }) end },
}

function M.lualine_theme(p)
  local mode = function(color)
    return {
      a = { fg = p.bg, bg = color, gui = "bold" },
      b = { fg = p.fg, bg = p.surfaceHi2 },
      c = { fg = p.dim, bg = p.bg },
    }
  end
  return {
    normal = mode(p.accent),
    insert = mode(p.green),
    visual = mode(p.yellow),
    replace = mode(p.red),
    command = mode(p.blue),
    inactive = mode(p.dim),
  }
end

function M.apply()
  local p = palette()
  local s = schemes[p.scheme] or schemes.dark

  vim.o.background = p.light and "light" or "dark"
  if s.plugin then pcall(function() require("lazy").load({ plugins = { s.plugin } }) end) end
  if s.setup then pcall(s.setup) end
  pcall(vim.cmd.colorscheme, s.name)

  -- фон и рамки — как у шелла и терминала
  local set = function(g, v) vim.api.nvim_set_hl(0, g, v) end
  local keep = function(g, v)
    set(g, vim.tbl_extend("force", vim.api.nvim_get_hl(0, { name = g, link = false }), v))
  end
  if p.bg then
    for _, g in ipairs({ "Normal", "NormalNC", "SignColumn", "EndOfBuffer", "LineNr", "FoldColumn" }) do
      keep(g, { bg = p.bg })
    end
    set("NormalFloat", { fg = p.fg, bg = p.surface })
    set("FloatBorder", { fg = p.line, bg = p.surface })
    set("WinSeparator", { fg = p.surfaceHi2 })
    set("CursorLine", { bg = p.surface })
    set("CursorLineNr", { fg = p.accent, bold = true })
    set("Pmenu", { fg = p.fg, bg = p.surface })
    set("PmenuSel", { fg = p.bg, bg = p.accent })
  end

  local ok, lualine = pcall(require, "lualine")
  if ok and p.bg then
    local cfg = lualine.get_config()
    cfg.options.theme = M.lualine_theme(p)
    lualine.setup(cfg)
  end
  return 0
end

return M
