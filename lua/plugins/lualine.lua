vim.pack.add({
	{ src = "https://github.com/nvim-lualine/lualine.nvim" },
}, { confirm = false, load = true })

require("lualine").setup({
	options = {
		globalstatus = true,
		icons_enabled = true,
		component_separators = { left = "", right = "" },
		section_separators = { left = "", right = "" },
	},
	sections = {
		lualine_a = { "mode" },
		lualine_b = { "branch" },
		lualine_c = {
			{
				"filename",
				path = 1,
				file_status = true,
				symbols = {
					modified = "[+]",
					readonly = "[-]",
					unnamed = "[No Name]",
				},
			},
		},
		lualine_x = {
			{
				"diagnostics",
				sources = { "nvim_diagnostic" },
				sections = { "error", "warn", "info", "hint" },
				symbols = { error = " ", warn = " ", info = " ", hint = " " },
			},
			"filetype",
		},
		lualine_y = { "encoding", "fileformat" },
		lualine_z = { "location" },
	},
})
