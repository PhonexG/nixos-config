require("lazy").setup({
  spec = require("config.plugins"),

  defaults = { lazy = false },

  install = { missing = false },
  checker = { enabled = false },
  rocks = { enabled = false },
  pkg = { enabled = false },
  local_spec = false,

  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
})
