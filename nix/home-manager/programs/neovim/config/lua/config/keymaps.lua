-- Basic keymaps

local keymap = vim.keymap

-- Swap ; and :
keymap.set({"n", "v"}, ";", ":", { desc = "Command mode" })
keymap.set({"n", "v"}, ":", ";", { desc = "Repeat last f/F/t/T" })

-- File explorer
keymap.set("n", "<leader>e", ":Telescope file_browser path=%:p:h select_buffer=true hidden=true respect_gitignore=false<CR>", { desc = "File browser (current dir)" })

-- Telescope
keymap.set("n", "<leader>ff", ":Telescope find_files<CR>", { desc = "Find files" })
keymap.set("n", "<leader>fg", ":Telescope live_grep<CR>", { desc = "Live grep" })
keymap.set("n", "<leader>fh", ":Telescope help_tags<CR>", { desc = "Help tags" })

-- Buffer management
keymap.set("n", "<leader>r", ":Telescope buffers<CR>", { desc = "List buffers" })
keymap.set("n", "<leader>bd", ":bdelete<CR>", { desc = "Delete buffer" })
keymap.set("n", "<leader>bn", ":bnext<CR>", { desc = "Next buffer" })
keymap.set("n", "<leader>bp", ":bprevious<CR>", { desc = "Previous buffer" })
keymap.set("n", "<leader>bD", ":bufdo bd<CR>", { desc = "Delete all buffers" })
keymap.set("n", "]b", ":bnext<CR>", { desc = "Next buffer" })
keymap.set("n", "[b", ":bprevious<CR>", { desc = "Previous buffer" })

-- Window splits and navigation
keymap.set("n", "ss", ":split<CR><C-w>w", { desc = "Split horizontal" })
keymap.set("n", "sv", ":vsplit<CR><C-w>w", { desc = "Split vertical" })
keymap.set("n", "sh", "<C-w>h", { desc = "Navigate left" })
keymap.set("n", "sk", "<C-w>k", { desc = "Navigate up" })
keymap.set("n", "sj", "<C-w>j", { desc = "Navigate down" })
keymap.set("n", "sl", "<C-w>l", { desc = "Navigate right" })
keymap.set("n", "se", "<C-w>=", { desc = "Equal splits" })
keymap.set("n", "sx", ":close<CR>", { desc = "Close split" })

-- Window resize
keymap.set("n", "<C-Up>", ":resize +2<CR>", { desc = "Increase height" })
keymap.set("n", "<C-Down>", ":resize -2<CR>", { desc = "Decrease height" })
keymap.set("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease width" })
keymap.set("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase width" })

-- Keep Ctrl+hjkl for navigation (alternative)
keymap.set("n", "<C-h>", "<C-w>h", { desc = "Navigate left" })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "Navigate down" })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "Navigate up" })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "Navigate right" })

-- Move lines
keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Keep cursor centered
keymap.set("n", "<C-d>", "<C-d>zz")
keymap.set("n", "<C-u>", "<C-u>zz")
keymap.set("n", "n", "nzzzv")
keymap.set("n", "N", "Nzzzv")

-- Git blame and signs
keymap.set("n", "<leader>gb", ":Gitsigns toggle_current_line_blame<CR>", { desc = "Toggle git blame" })
keymap.set("n", "<leader>gB", ":Gitsigns blame_line<CR>", { desc = "Git blame line (popup)" })
keymap.set("n", "<leader>gp", ":Gitsigns preview_hunk<CR>", { desc = "Preview git hunk" })
keymap.set("n", "<leader>gr", ":Gitsigns reset_hunk<CR>", { desc = "Reset git hunk" })
keymap.set("n", "<leader>gR", ":Gitsigns reset_buffer<CR>", { desc = "Reset git buffer" })
keymap.set("n", "<leader>gs", ":Gitsigns stage_hunk<CR>", { desc = "Stage git hunk" })
keymap.set("n", "<leader>gS", ":Gitsigns stage_buffer<CR>", { desc = "Stage git buffer" })
keymap.set("n", "<leader>gu", ":Gitsigns undo_stage_hunk<CR>", { desc = "Undo stage hunk" })
keymap.set("n", "<leader>gd", ":Gitsigns diffthis<CR>", { desc = "Git diff this" })
keymap.set("n", "<leader>gD", ":Gitsigns diffthis ~<CR>", { desc = "Git diff this ~" })
keymap.set("n", "]h", ":Gitsigns next_hunk<CR>", { desc = "Next git hunk" })
keymap.set("n", "[h", ":Gitsigns prev_hunk<CR>", { desc = "Previous git hunk" })

-- Theme switcher (using Telescope)
keymap.set("n", "<leader>th", ":Telescope colorscheme<CR>", { desc = "Switch theme" })

-- Flash.nvim navigation
-- Override f/F/t/T for enhanced functionality
keymap.set({ "n", "x", "o" }, "f", function() require("flash").jump({ search = { mode = "search", max_length = 1 } }) end, { desc = "Flash f" })
keymap.set({ "n", "x", "o" }, "F", function() require("flash").jump({ search = { mode = "search", max_length = 1, forward = false } }) end, { desc = "Flash F" })
keymap.set({ "n", "x", "o" }, "t", function() require("flash").jump({ search = { mode = "search", max_length = 1 }, jump = { offset = 1 } }) end, { desc = "Flash t" })
keymap.set({ "n", "x", "o" }, "T", function() require("flash").jump({ search = { mode = "search", max_length = 1, forward = false }, jump = { offset = -1 } }) end, { desc = "Flash T" })

-- Additional flash commands
keymap.set({ "n", "x", "o" }, "gf", function() require("flash").jump() end, { desc = "Flash jump (multi-char)" })
keymap.set({ "n", "x", "o" }, "gF", function() require("flash").treesitter() end, { desc = "Flash Treesitter" })
keymap.set("c", "<c-s>", function() require("flash").toggle() end, { desc = "Toggle Flash Search" })
