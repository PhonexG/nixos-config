vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.mouse = "a"
vim.opt.scrolloff = 8

-- Перемикання на альтернативний файл через Tab у Normal mode
vim.keymap.set("n", "<Tab>", "<C-^>", { desc = "Toggle alternate file" })
-- Швидкий запуск коду на F5
vim.keymap.set("n", "<F5>", ":w<CR>:!python3 %<CR>", { desc = "Save and run" })

