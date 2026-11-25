return {
	"MeanderingProgrammer/render-markdown.nvim",

	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-mini/mini.nvim",
	},

	---@module 'render-markdown'
	---@type render.md.UserConfig
	opts = {
		image = {
			enabled = true,
			max_width = 100,
			max_height = 20,
		},
		-- Override default window options for the rendered view
		win_options = {
			conceallevel = { default = vim.o.conceallevel, rendered = 3 },
			concealcursor = { default = vim.o.concealcursor, rendered = "" },
		},
		-- Prevent code block padding from triggering unnecessary line wrapping
		overrides = {
			buftype = {
				nofile = {
					code = { left_pad = 0, right_pad = 0 },
				},
			},
		},
	},
}
