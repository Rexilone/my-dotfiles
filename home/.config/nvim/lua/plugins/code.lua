return {
  -- подсветка синтаксиса
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install({
        "bash", "c", "cpp", "css", "html", "javascript", "json", "kdl", "lua",
        "markdown", "markdown_inline", "python", "qmljs", "query", "rust",
        "toml", "typescript", "vim", "vimdoc", "yaml",
      })
      vim.treesitter.language.register("qmljs", "qml")
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(a)
          if pcall(vim.treesitter.start, a.buf) then
            vim.bo[a.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- автодополнение
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = "InsertEnter",
    opts = {
      keymap = { preset = "enter" },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        menu = { border = "rounded", scrollbar = false },
        documentation = { auto_show = true, window = { border = "rounded" } },
      },
      signature = { enabled = true, window = { border = "rounded" } },
      sources = { default = { "lsp", "path", "buffer" } },
    },
  },

  -- LSP: серверы ставятся через :Mason
  {
    "mason-org/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "mason-org/mason.nvim", opts = { ui = { border = "rounded" } } },
      "neovim/nvim-lspconfig",
    },
    opts = { ensure_installed = { "lua_ls", "bashls" } },
    config = function(_, opts)
      require("mason-lspconfig").setup(opts)

      vim.lsp.config("lua_ls", {
        settings = { Lua = { diagnostics = { globals = { "vim" } } } },
      })

      -- QML (quickshell): qmlls из Qt
      vim.lsp.config("qmlls", { cmd = { "/usr/lib/qt6/bin/qmlls" } })
      vim.lsp.enable("qmlls")

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(a)
          local map = function(k, f, d) vim.keymap.set("n", k, f, { buffer = a.buf, desc = d }) end
          map("gd", vim.lsp.buf.definition, "Definition")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>cr", vim.lsp.buf.rename, "Rename")
          map("<leader>cf", vim.lsp.buf.format, "Format")
        end,
      })
    end,
  },
}
