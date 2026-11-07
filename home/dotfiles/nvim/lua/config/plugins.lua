local p = vim.g.nix_plugins

return {
  {
    name = "tokyonight.nvim",
    dir = p.tokyonight,
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("tokyonight-night")
    end,
  },

  {
    name = "plenary.nvim",
    dir = p.plenary,
    lazy = true,
  },

  {
    name = "telescope.nvim",
    dir = p.telescope,
    dependencies = { "plenary.nvim" },
    cmd = "Telescope",
    keys = {
      {
        "<leader>ff",
        "<cmd>Telescope find_files<cr>",
        desc = "Пошук файлів",
      },
      {
        "<leader>fg",
        "<cmd>Telescope live_grep<cr>",
        desc = "Пошук тексту",
      },
    },
    opts = {},
  },

  {
    name = "nvim-autopairs",
    dir = p.autopairs,
    event = "InsertEnter",
    opts = {},
  },
}
