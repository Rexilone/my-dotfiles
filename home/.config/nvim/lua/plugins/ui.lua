return {
  -- тема: выбирается в Настройках Quickshell (Персонализация) и применяется через qs_theme
  {
    "vague2k/vague.nvim",
    lazy = false,
    priority = 1000,
    config = function() require("qs_theme").apply() end,
  },
  { "gbprod/nord.nvim", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true },
  { "rose-pine/neovim", name = "rose-pine", lazy = true },

  -- набор маленьких модулей: иконки, статуслайн, пары, окружения, отступы
  {
    "nvim-mini/mini.nvim",
    version = false,
    lazy = false,
    config = function()
      require("mini.icons").setup()
      MiniIcons.mock_nvim_web_devicons()

      require("mini.pairs").setup()
      require("mini.surround").setup()
      require("mini.ai").setup()
      require("mini.cursorword").setup()
      require("mini.notify").setup({ window = { config = { border = "rounded" } } })
      vim.notify = MiniNotify.make_notify()

      local indent = require("mini.indentscope")
      indent.setup({ symbol = "│", draw = { delay = 50, animation = indent.gen_animation.none() } })

      local starter = require("mini.starter")
      starter.setup({
        header = "neovim",
        footer = "",
        items = {
          starter.sections.recent_files(6, false),
          { name = "Find file", action = "FzfLua files", section = "Actions" },
          { name = "Grep", action = "FzfLua live_grep", section = "Actions" },
          { name = "Yazi", action = "Yazi cwd", section = "Actions" },
          { name = "Lazy", action = "Lazy", section = "Actions" },
          { name = "Quit", action = "qall", section = "Actions" },
        },
        content_hooks = { starter.gen_hook.aligning("center", "center") },
      })
    end,
  },

  -- статуслайн с треугольными разделителями, цвета под бар
  {
    "nvim-lualine/lualine.nvim",
    lazy = false,
    config = function()
      local p = dofile(vim.fn.stdpath("config") .. "/lua/qs_palette.lua")
      require("lualine").setup({
        options = {
          theme = require("qs_theme").lualine_theme(p),
          section_separators = { left = "", right = "" },
          component_separators = { left = "", right = "" },
          globalstatus = true,
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff" },
          lualine_c = { { "filename", path = 1, symbols = { modified = " ●", readonly = " 󰌾" } } },
          lualine_x = { "diagnostics", "filetype" },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      })
    end,
  },

  -- подсказки по клавишам
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = { preset = "helix", delay = 400, icons = { mappings = false } },
  },

  -- git-метки в колонке знаков
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "│" }, change = { text = "│" }, delete = { text = "_" },
        topdelete = { text = "‾" }, changedelete = { text = "│" },
      },
    },
    keys = {
      { "]h", "<cmd>Gitsigns next_hunk<cr>", desc = "Next hunk" },
      { "[h", "<cmd>Gitsigns prev_hunk<cr>", desc = "Prev hunk" },
      { "<leader>gp", "<cmd>Gitsigns preview_hunk<cr>", desc = "Preview hunk" },
      { "<leader>gb", "<cmd>Gitsigns blame_line<cr>", desc = "Blame line" },
    },
  },
}
