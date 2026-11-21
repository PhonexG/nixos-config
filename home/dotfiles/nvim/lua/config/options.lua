vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.mouse = "a"
vim.opt.scrolloff = 8

-- Switch to alternate file via Tab in Normal mode
vim.keymap.set("n", "<Tab>", "<C-^>", { desc = "Toggle alternate file" })
-- Quick-run code on F5
vim.keymap.set("n", "<F5>", ":w<CR>:!python3 %<CR>", { desc = "Save and run" })

