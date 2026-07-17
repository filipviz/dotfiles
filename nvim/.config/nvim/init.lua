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
if vim.env.SSH_CONNECTION then
	vim.g.clipboard = "osc52"
end
vim.opt.mouse = ""
vim.opt.splitright = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.undofile = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.cursorlineopt = "both"
vim.opt.signcolumn = "yes"
vim.opt.completeopt = "menu,menuone,noselect,popup,fuzzy"
vim.opt.clipboard = "unnamedplus"
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.winborder = "rounded"
vim.opt.list = true
vim.opt.listchars = { trail = "-", nbsp = "+", tab = "  ", extends = ">", precedes = "<" }
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.breakindentopt = "shift:0"
vim.opt.showbreak = "↪"
vim.opt.shortmess:append("I")
vim.opt.updatetime = 500
vim.opt.termguicolors = true
vim.env.COLORTERM = "truecolor"
vim.g.markdown_fenced_languages = { "html", "css", "javascript", "python", "lua", "go", "bash=sh", "c", "cpp" }
vim.opt.grepprg = "rg --vimgrep"
vim.opt.grepformat = "%f:%l:%c:%m"
vim.opt.diffopt:append("linematch:60")
vim.cmd.packadd("cfilter")

-- netrw
vim.g.netrw_keepdir = 0
vim.g.netrw_winsize = 18
vim.g.netrw_banner = 0

-- Keymaps
vim.keymap.set("n", "<leader>e", "<Cmd>Le<CR>")
vim.keymap.set("t", "<C-s>", "<C-\\><C-n>")

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
	local _, win = vim.diagnostic.open_float()
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
end, { desc = "Show line diagnostics" })

-- LSP: rely on the default keymaps (:h lsp-defaults) — grn rename, gra code
-- action, grr references, gri implementation, grt type definition, gO symbols,
-- K hover, CTRL-]/CTRL-T definition via tagfunc, <C-s> signature help (insert)
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
	callback = function(args)
		vim.keymap.set("n", "<leader>ih", function()
			vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf }), { bufnr = args.buf })
		end, { buffer = args.buf, desc = "Toggle inlay hints" })

		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client:supports_method("textDocument/completion") then
			vim.lsp.completion.enable(true, args.data.client_id, args.buf, { autotrigger = false })
		end
	end,
})

-- Native LSP completion: manual trigger, fuzzy matching, docs in a popup
vim.keymap.set("i", "<C-Space>", vim.lsp.completion.get, { desc = "Trigger completion" })
vim.keymap.set("i", "<Tab>", function()
	return vim.fn.pumvisible() == 1 and "<C-n>" or "<Tab>"
end, { expr = true })
vim.keymap.set("i", "<S-Tab>", function()
	return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
end, { expr = true })
vim.keymap.set("i", "<CR>", function()
	return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true })

-- Command for writing docs/prose with a specific max line length.
vim.api.nvim_create_user_command("ProseSettings", function(opts)
	local width = tonumber(opts.args) or 80
	vim.opt_local.textwidth = width
	vim.opt_local.colorcolumn = tostring(width)
end, { nargs = "?", desc = "Set prose-friendly wrapping (default 80)" })

-- Set up treesitter (FileType rather than BufReadPost: start() infers the
-- language from the filetype, which isn't detected yet at BufReadPost time)
vim.api.nvim_create_autocmd("FileType", {
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
		vim.hl.on_yank({ higroup = "IncSearch", timeout = 140 })
	end,
})

local zen_mode_buffer
local zen_mode_tmux_status
local zen_mode_tmux_status_is_local
local zen_mode_window
local zen_mode_was_fullscreen
local zen_mode_unclutter

local function tmux(command)
	if not vim.env.TMUX then return end
	local result = vim.system(vim.list_extend({ "tmux" }, command), { text = true }):wait()
	if result.code == 0 then return vim.trim(result.stdout) end
end

local function fullscreen_state(window)
	if vim.fn.executable("xprop") == 0 then return end
	local result = vim.system({ "xprop", "-id", window, "_NET_WM_STATE" }, { text = true }):wait()
	if result.code == 0 then return result.stdout:find("_NET_WM_STATE_FULLSCREEN", 1, true) ~= nil end
end

local function set_fullscreen(window, enabled)
	if vim.fn.executable("wmctrl") == 0 then return end
	vim.system({ "wmctrl", "-i", "-r", window, "-b", (enabled and "add" or "remove") .. ",fullscreen" }):wait()
end

local function stop_zen_unclutter()
	if not zen_mode_unclutter then return end
	pcall(zen_mode_unclutter.kill, zen_mode_unclutter, 15)
	zen_mode_unclutter = nil
end

vim.api.nvim_create_autocmd("VimLeavePre", { callback = stop_zen_unclutter })

require("lazy").setup({
	spec = {
		{
			"rose-pine/neovim",
			name = "rose-pine",
			priority = 1000,
			config = function()
				require("rose-pine").setup({
					variant = "moon",
					styles = { italic = false },
					palette = { moon = { base = "#000000" } },
				})
				vim.cmd.colorscheme("rose-pine")
				-- vim.cmd.colorscheme("rose-pine-dawn")
			end,
		},
		{
			url = "https://codeberg.org/andyg/leap.nvim",
			lazy = false,
			config = function()
				vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap)")
				vim.keymap.set("n", "S", "<Plug>(leap-from-window)")
			end,
		},
		{
			"ibhagwan/fzf-lua",
			dependencies = { "nvim-tree/nvim-web-devicons" },
			opts = {},
			keys = {
				{ "<leader>ff", "<cmd>FzfLua files<CR>",     desc = "FzfLua files" },
				{ "<leader>fb", "<cmd>FzfLua blines<CR>",    desc = "FzfLua buffer lines" },
				{ "<leader>fs", "<cmd>FzfLua git_status<CR>", desc = "FzfLua git status" },
				{ "<leader>fg", "<cmd>FzfLua live_grep<CR>", desc = "FzfLua live grep" },
				{ "<leader>ft", "<cmd>FzfLua grep<CR>",      desc = "FzfLua grep" },
				{ "<leader>fo", "<cmd>FzfLua lsp_document_symbols<CR>", desc = "FzfLua document symbols" },
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
					map("n", "]c", function()
						if vim.wo.diff then
							vim.cmd.normal({ "]c", bang = true })
						else
							gs.nav_hunk("next")
						end
					end, "Next Hunk")
					map("n", "[c", function()
						if vim.wo.diff then
							vim.cmd.normal({ "[c", bang = true })
						else
							gs.nav_hunk("prev")
						end
					end, "Prev Hunk")
					map("n", "]C", function() gs.nav_hunk("last") end, "Last Hunk")
					map("n", "[C", function() gs.nav_hunk("first") end, "First Hunk")
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
		{
			"sindrets/diffview.nvim",
			cmd = { "DiffviewOpen", "DiffviewFileHistory" },
			keys = {
				{ "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "Diff review (working tree)" },
			},
			opts = {
				keymaps = {
					view = { { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } } },
					file_panel = { { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } } },
				},
			},
		},
		{
			"folke/zen-mode.nvim",
			cmd = "ZenMode",
			keys = {
				{ "<leader>z", "<cmd>ZenMode<CR>", desc = "Toggle zen mode" },
			},
			opts = {
				window = {
					width = 80,
					options = {
						signcolumn = "no",
						number = false,
						relativenumber = false,
						cursorline = false,
						foldcolumn = "0",
						list = false,
						listchars = "",
						showbreak = "",
					},
				},
				plugins = {
					options = {
						laststatus = 0,
						listchars = "",
						showbreak = "",
					},
					twilight = { enabled = false },
					alacritty = {
						enabled = true,
						font = "12",
					},
				},
				on_open = function(win)
					zen_mode_buffer = vim.api.nvim_win_get_buf(win)
					vim.keymap.set({ "n", "x" }, "j", "gj", {
						buffer = zen_mode_buffer,
						desc = "Down by screen line (Zen Mode)",
					})
					vim.keymap.set({ "n", "x" }, "k", "gk", {
						buffer = zen_mode_buffer,
						desc = "Up by screen line (Zen Mode)",
					})

					local session_status = tmux({ "show-options", "-qv", "status" })
					if session_status ~= nil then
						zen_mode_tmux_status_is_local = session_status ~= ""
						zen_mode_tmux_status = zen_mode_tmux_status_is_local and session_status
							or tmux({ "show-options", "-gv", "status" })
						if zen_mode_tmux_status then tmux({ "set-option", "status", "off" }) end
					end

					local window = tonumber(vim.env.ALACRITTY_WINDOW_ID or vim.env.WINDOWID)
					if window then
						zen_mode_window = ("0x%x"):format(window)
						zen_mode_was_fullscreen = fullscreen_state(zen_mode_window)
						if zen_mode_was_fullscreen == false then set_fullscreen(zen_mode_window, true) end
					end

					if vim.env.DISPLAY and vim.fn.executable("unclutter") == 1 then
						zen_mode_unclutter = vim.system({ "unclutter", "--timeout", "0.05", "--start-hidden" })
					end
				end,
				on_close = function()
					if zen_mode_buffer and vim.api.nvim_buf_is_valid(zen_mode_buffer) then
						pcall(vim.keymap.del, { "n", "x" }, "j", { buffer = zen_mode_buffer })
						pcall(vim.keymap.del, { "n", "x" }, "k", { buffer = zen_mode_buffer })
					end
					zen_mode_buffer = nil

					if zen_mode_tmux_status then
						if zen_mode_tmux_status_is_local then
							tmux({ "set-option", "status", zen_mode_tmux_status })
						else
							tmux({ "set-option", "-u", "status" })
						end
					end
					zen_mode_tmux_status = nil
					zen_mode_tmux_status_is_local = nil

					if zen_mode_window and zen_mode_was_fullscreen == false then
						set_fullscreen(zen_mode_window, false)
					end
					zen_mode_window = nil
					zen_mode_was_fullscreen = nil

					stop_zen_unclutter()
				end,
			},
		},
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
			"nvim-treesitter/nvim-treesitter",
			branch = "main",
			build = ":TSUpdate",
			config = function()
				require("nvim-treesitter").install({
					"python", "go", "bash", "javascript", "typescript", "html", "css",
					"json", "toml", "yaml", "rust", "c", "cpp",
				})
			end,
		},
		{
			"neovim/nvim-lspconfig",
			config = function()
				vim.lsp.config("lua_ls", {
					settings = {
						Lua = {
							runtime = { version = "LuaJIT" },
							workspace = {
								checkThirdParty = false,
								library = { vim.env.VIMRUNTIME },
							},
							diagnostics = { globals = { "vim" } },
						},
					},
				})

				vim.lsp.config("basedpyright", {
					settings = {
						basedpyright = {
							analysis = {
								typeCheckingMode = "off",
								diagnosticMode = "openFilesOnly",
							},
						},
					},
				})

				vim.lsp.config("gopls", {
					settings = {
						gopls = {
							analyses = { unusedparams = true },
							staticcheck = true,
						},
					},
				})

				vim.lsp.config("clangd", {
					cmd = { "clangd", "--background-index", "--clang-tidy" },
					filetypes = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
				})

				vim.lsp.enable({ "lua_ls", "basedpyright", "bashls", "gopls", "clangd", "ts_ls", "html", "cssls" })
			end,
		},
	},
	-- Keep the lockfile next to the real init.lua so it lives in the dotfiles repo
	lockfile = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.stdpath("config") .. "/init.lua"), ":h") .. "/lazy-lock.json",
	install = { colorscheme = { "rose-pine" } },
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
