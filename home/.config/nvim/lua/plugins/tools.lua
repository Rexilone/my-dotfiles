return {
  -- поиск файлов, текста, буферов
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    opts = {
      winopts = { height = 0.8, width = 0.8, border = "rounded", preview = { layout = "flex" } },
      fzf_colors = true,
    },
    keys = {
      { "<leader>f", "<cmd>FzfLua files<cr>", desc = "Files" },
      { "<leader>/", "<cmd>FzfLua live_grep<cr>", desc = "Grep" },
      { "<leader>b", "<cmd>FzfLua buffers<cr>", desc = "Buffers" },
      { "<leader>r", "<cmd>FzfLua oldfiles<cr>", desc = "Recent files" },
      { "<leader>h", "<cmd>FzfLua helptags<cr>", desc = "Help" },
      { "<leader>s", "<cmd>FzfLua lsp_document_symbols<cr>", desc = "Symbols" },
      { "<leader>D", "<cmd>FzfLua diagnostics_document<cr>", desc = "Diagnostics" },
    },
  },

  -- yazi внутри neovim
  {
    "mikavilpas/yazi.nvim",
    version = "*",
    event = "VeryLazy",
    dependencies = { { "nvim-lua/plenary.nvim", lazy = true } },
    keys = {
      { "<leader>e", "<cmd>Yazi<cr>", desc = "Yazi (current file)" },
      { "<leader>E", "<cmd>Yazi cwd<cr>", desc = "Yazi (cwd)" },
    },
    opts = {
      open_for_directories = true,
      floating_window_scaling_factor = 0.85,
      yazi_floating_window_border = "rounded",
    },
    init = function() vim.g.loaded_netrwPlugin = 1 end,
  },
}
