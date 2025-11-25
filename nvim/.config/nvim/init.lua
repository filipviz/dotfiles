-- Lazy setup
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local repo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out,                            "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

-- Basic options
vim.g.mapleader = " "

vim.opt.splitright = true
vim.opt.undofile = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.cursorlineopt = "both"
vim.opt.signcolumn = "yes"
-- vim.opt.scrolloff = 2
vim.opt.clipboard = "unnamedplus"
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.winborder = "rounded"
vim.opt.list = true
vim.opt.listchars = { trail = "-", nbsp = "+", tab = "  ", extends = ">", precedes = "<" }
vim.opt.shortmess:append("I")
vim.opt.updatetime = 500
vim.g.markdown_fenced_languages = { "html", "css", "javascript", "python", "lua", "go", "bash=sh", "c", "cpp" }

vim.opt.grepprg = "rg --vimgrep"
vim.opt.grepformat = "%f:%l:%c:%m"
vim.cmd.packadd("cfilter")

-- netrw
vim.g.netrw_keepdir = 0
vim.g.netrw_winsize = 18
vim.g.netrw_banner = 0

-- Theme
local function update_background()
	local color, bg, everforest_bg = "everforest", "dark", "hard"
	if vim.env.TERMUX_VERSION then
		color, bg = "quiet", "light"
	else
		local status, output = pcall(vim.fn.system, "defaults read -g AppleInterfaceStyle 2>/dev/null")
		if status and not output:match("Dark") then
			bg = "light"
			everforest_bg = "soft"
		end
	end

	if vim.g.everforest_background ~= everforest_bg then
		vim.g.everforest_background = everforest_bg
	end
	if vim.o.background ~= bg then vim.opt.background = bg end
	if vim.g.colors_name ~= color then vim.cmd.colorscheme(color) end
end

vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
	callback = update_background,
})

-- Keymaps
vim.keymap.set("n", "<Tab>", "<Cmd>bnext<CR>")
vim.keymap.set("n", "<S-Tab>", "<Cmd>bprevious<CR>")
vim.keymap.set("n", "<leader>e", "<Cmd>Le<CR>")
vim.keymap.set("t", "<leader><Esc>", "<C-\\><C-n>")

local term_bottom = { height = 12 }
local function toggle_term_bottom()
	if term_bottom.win and vim.api.nvim_win_is_valid(term_bottom.win) then
		vim.api.nvim_win_close(term_bottom.win, true)
		term_bottom.win = nil
		return
	end

	vim.cmd("botright " .. term_bottom.height .. "split")
	term_bottom.win = vim.api.nvim_get_current_win()

if term_bottom.buf and vim.api.nvim_buf_is_valid(term_bottom.buf) then
		vim.api.nvim_win_set_buf(term_bottom.win, term_bottom.buf)
	else
		vim.cmd("terminal")
		term_bottom.buf = vim.api.nvim_get_current_buf()
		vim.bo[term_bottom.buf].buflisted = false
	end

	vim.cmd.startinsert()
end

vim.api.nvim_create_autocmd("TermClose", {
	callback = function(args)
		if args.buf == term_bottom.buf then
			term_bottom.buf = nil
		end
	end,
})

vim.keymap.set("n", "<leader>t", toggle_term_bottom)

for _, key in ipairs({ "h", "j", "k", "l" }) do
	vim.keymap.set("n", "<C-" .. key .. ">", "<C-w>" .. key)
	vim.keymap.set("t", "<C-" .. key .. ">", "<C-\\><C-n><C-w>" .. key)
end

vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { desc = "Clear search highlight", silent = true })
vim.api.nvim_create_autocmd("CmdlineEnter", {
	pattern = { "/", "?" },
	callback = function()
		vim.opt.hlsearch = true
	end,
})

-- View diagnostics
vim.keymap.set("n", "gl", function()
	local win = vim.diagnostic.open_float()
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
end, { desc = "Show line diagnostics" })

-- Command for writing docs/prose with a specific max line length.
vim.api.nvim_create_user_command("ProseSettings", function(opts)
	local width = tonumber(opts.args) or 80
	vim.opt_local.textwidth = width
	vim.opt_local.colorcolumn = tostring(width)
end, { nargs = "?", desc = "Set prose-friendly wrapping (default 80)" })

-- Set up treesitter
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
	callback = function(args)
		if vim.bo[args.buf].buftype == "" then
			pcall(vim.treesitter.start, args.buf)
		end
	end,
})

-- Visual feedback on yank
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Briefly highlight yanked text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank({ higroup = "IncSearch", timeout = 140 })
	end,
})


require("lazy").setup({
	spec = {
		{
			"sainnhe/everforest",
			priority = 1000,
			lazy = false,
			config = update_background,
		},
		{
			"ggandor/leap.nvim",
			lazy = false,
			config = function()
				require("leap").add_default_mappings()
			end,
		},
		{
			"akinsho/bufferline.nvim",
			event = "VeryLazy",
			dependencies = { "nvim-tree/nvim-web-devicons" },
			opts = {
				options = {
					show_buffer_close_icons = false,
					show_close_icon = false,
					diagnostics = "nvim_lsp",
					separator_style = "thin",
				},
			},
		},
		{
			"ibhagwan/fzf-lua",
			dependencies = { "nvim-tree/nvim-web-devicons" },
			opts = {},
			keys = {
				{ "<leader>ff", "<cmd>FzfLua files<CR>",     desc = "FzfLua files" },
				{ "<leader>fs", "<cmd>FzfLua grep<CR>",      desc = "FzfLua grep" },
				{ "<leader>fg", "<cmd>FzfLua live_grep<CR>", desc = "FzfLua live grep" },
				{ "<leader>fd", "<cmd>FzfLua<CR>",           desc = "FzfLua default" },
			},
		},
		{
			"lewis6991/gitsigns.nvim",
			event = { "BufReadPre", "BufNewFile" },
			opts = {
				on_attach = function(buffer)
					local gs = package.loaded.gitsigns
					if not gs then return end

					local function map(mode, lhs, rhs, desc)
						vim.keymap.set(mode, lhs, rhs, { buffer = buffer, desc = desc, silent = true })
					end

					-- stylua: ignore start
					map("n", "]h", function()
						if vim.wo.diff then
							vim.cmd.normal({ "]c", bang = true })
						else
							gs.nav_hunk("next")
						end
					end, "Next Hunk")
					map("n", "[h", function()
						if vim.wo.diff then
							vim.cmd.normal({ "[c", bang = true })
						else
							gs.nav_hunk("prev")
						end
					end, "Prev Hunk")
					map("n", "]H", function() gs.nav_hunk("last") end, "Last Hunk")
					map("n", "[H", function() gs.nav_hunk("first") end, "First Hunk")
					map({ "n", "v" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
					map({ "n", "v" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
					map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
					map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo Stage Hunk")
					map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
					map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk Inline")
					map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame Line")
					map("n", "<leader>ghB", function() gs.blame() end, "Blame Buffer")
					map("n", "<leader>ghd", gs.diffthis, "Diff This")
					map("n", "<leader>ghD", function() gs.diffthis("~") end, "Diff This ~")
					map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "GitSigns Select Hunk")
					-- stylua: ignore end
				end,
			},
		},
		{ 'nvim-telescope/telescope.nvim', tag = '0.1.8' },
		{
			"nvim-lualine/lualine.nvim",
			event = "VeryLazy",
			dependencies = { "nvim-tree/nvim-web-devicons" },
			opts = {
				options = {
					globalstatus = true,
				},
			},
		},
		{
			"hrsh7th/nvim-cmp",
			event = "InsertEnter",
			dependencies = {
				"hrsh7th/cmp-nvim-lsp",
				"hrsh7th/cmp-buffer",
				"hrsh7th/cmp-path",
			},
			config = function()
				local cmp = require("cmp")

					cmp.setup({
					completion = { autocomplete = false, completeopt = "menu,menuone,noselect" },
					snippet = { expand = function() end },
					sources = cmp.config.sources({
						{ name = "nvim_lsp" },
						{ name = "path" },
					}, {
						{ name = "buffer" },
					}),
					mapping = cmp.mapping.preset.insert({
						["<C-n>"] = cmp.mapping.select_next_item(),
						["<C-p>"] = cmp.mapping.select_prev_item(),
						["<C-Space>"] = cmp.mapping.complete(),
						["<C-e>"] = cmp.mapping.abort(),
						["<CR>"] = cmp.mapping.confirm({ select = true }),
						["<Tab>"] = cmp.mapping(function(fallback)
							if cmp.visible() then
								cmp.select_next_item()
							else
								fallback()
							end
						end, { "i", "s" }),
						["<S-Tab>"] = cmp.mapping(function(fallback)
							if cmp.visible() then
								cmp.select_prev_item()
							else
								fallback()
							end
						end, { "i", "s" }),
					}),
					enabled = function()
						return vim.bo.buftype ~= "prompt"
					end,
				})

				cmp.setup.filetype("markdown", { enabled = false })
			end,
		},
		{ "mason-org/mason.nvim",          opts = {} },
		{
			"neovim/nvim-lspconfig",
			dependencies = { "hrsh7th/cmp-nvim-lsp" },
			config = function()
				local capabilities = require("cmp_nvim_lsp").default_capabilities()

				local function on_attach(client, bufnr)
					local keymap = function(keys, fn, desc)
						vim.keymap.set("n", keys, fn, { buffer = bufnr, desc = desc })
					end

					keymap("gd", vim.lsp.buf.definition, "Go to definition")
					keymap("gr", vim.lsp.buf.references, "Go to references")
					keymap("gD", vim.lsp.buf.declaration, "Go to declaration")
					keymap("gi", vim.lsp.buf.implementation, "Go to implementation")
					keymap("K", vim.lsp.buf.hover, "Hover")
					keymap("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
					keymap("<leader>ca", vim.lsp.buf.code_action, "Code action")
					keymap("[d", vim.diagnostic.goto_prev, "Previous diagnostic")
					keymap("]d", vim.diagnostic.goto_next, "Next diagnostic")

					if client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
						pcall(vim.lsp.inlay_hint, bufnr, true)
					end
				end

				vim.lsp.config("lua_ls", {
					capabilities = capabilities,
					on_attach = on_attach,
					settings = {
						Lua = {
							runtime = { version = "LuaJIT" },
							workspace = {
								checkThirdParty = false,
								library = vim.api.nvim_get_runtime_file("", true),
							},
							diagnostics = { globals = { "vim" } },
							telemetry = { enable = false },
						},
					},
				})

				vim.lsp.config("basedpyright", {
					capabilities = capabilities,
					on_attach = function(client, bufnr)
						on_attach(client, bufnr)
						if client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
							pcall(vim.lsp.inlay_hint, bufnr, false)
						end
					end,
					settings = {
						basedpyright = {
							analysis = {
								typeCheckingMode = "off",
								diagnosticMode = "openFilesOnly",
							},
						},
					},
				})

				vim.lsp.config("bashls", {
					capabilities = capabilities,
					on_attach = on_attach,
					filetypes = { "sh", "bash" },
				})

				vim.lsp.config("gopls", {
					capabilities = capabilities,
					on_attach = on_attach,
					settings = {
						gopls = {
							analyses = {
								unusedparams = true,
								fieldalignment = true,
							},
							staticcheck = true,
						},
					},
				})

				vim.lsp.config("clangd", {
					capabilities = capabilities,
					on_attach = on_attach,
					cmd = { "clangd", "--background-index", "--clang-tidy" },
					filetypes = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
				})

				vim.lsp.enable({ "lua_ls", "basedpyright", "bashls", "gopls", "clangd" })

				vim.diagnostic.config({ float = { border = "rounded" } })
			end,
		},
	},
	install = { colorscheme = { "everforest" } },
	change_detection = { notify = false },
	performance = {
		rtp = {
			disabled_plugins = {
				"gzip",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
			},
		},
	},
})
