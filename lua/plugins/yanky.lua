vim.pack.add({
	{ src = "https://github.com/gbprod/yanky.nvim" },
}, { confirm = false, load = true })

require("yanky").setup({
	highlight = {
		on_yank = true,
		on_put = false,
		timer = 200,
	},
})
