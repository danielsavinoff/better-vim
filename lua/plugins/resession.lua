vim.pack.add({
  { src = "https://github.com/stevearc/resession.nvim" },
}, { confirm = false, load = true })

local resession = require("resession")
local args = vim.fn.argv()
local root = vim.fn.getcwd()
if #args > 0 then
  root = vim.fn.fnamemodify(args[1], vim.fn.isdirectory(args[1]) == 1 and ":p" or ":p:h")
end
root = vim.fs.normalize(root):gsub("(.)/$", "%1")
local launch_root = root
root = vim.fs.root(root, ".git") or root
local restore_on_start = #args == 0 or (#args == 1 and vim.fn.isdirectory(args[1]) == 1)
local netrw = require("resession.extensions.netrw")
netrw.config({ root = root })
resession.setup({
  dir = "dirsession",
  buf_filter = function(bufnr)
    if not resession.default_buf_filter(bufnr) then
      return false
    end
    if vim.bo[bufnr].buftype == "help" then
      return true
    end
    local file = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    return file == root or vim.startswith(file, root == "/" and root or root .. "/")
  end,
  extensions = {
    netrw = { enable_in_tab = true, root = root },
  },
})

vim.api.nvim_create_user_command("Rex", function()
  netrw.rex(root)
end, { desc = "Return to the project tree and its saved cursor position" })

local group = vim.api.nvim_create_augroup("resession_lifecycle", { clear = true })
local interactive = vim.v.vim_did_enter == 1 and #vim.api.nvim_list_uis() > 0
local enabled = true
local using_stdin = false

local function load_session()
  resession.load(root, { silence_errors = true })
  if resession.get_current() then
    return
  end

  -- Import the previous manager's session once, leaving its files intact.
  local function legacy_path(directory)
    local encoded = directory:gsub("[^%w%-_]", function(char)
      return string.format("%%%02X", string.byte(char))
    end)
    return vim.fn.stdpath("state") .. "/netrw_session/" .. encoded .. ".vim"
  end
  local legacy = legacy_path(root)
  if vim.fn.filereadable(legacy) == 0 and launch_root ~= root then
    legacy = legacy_path(launch_root)
  end
  if vim.fn.filereadable(legacy) == 0 then
    return
  end
  local lines = {}
  for _, line in ipairs(vim.fn.readfile(legacy)) do
    if line == "vim :" or line == ":" then
      break
    end
    table.insert(lines, line)
  end
  local temporary = vim.fn.tempname() .. ".vim"
  vim.fn.writefile(lines, temporary)
  local ok, err = pcall(vim.cmd.source, vim.fn.fnameescape(temporary))
  vim.fn.delete(temporary)
  if not ok then
    error(err)
  end
  if vim.fn.filereadable(legacy .. ".json") == 1 then
    local data = vim.json.decode(table.concat(vim.fn.readfile(legacy .. ".json"), "\n"))
    local tabs = vim.api.nvim_list_tabpages()
    netrw.on_pre_load()
    for _, state in ipairs(data.netrw or {}) do
      local tab = tabs[state.tab]
      local win = tab and vim.api.nvim_tabpage_list_wins(tab)[state.window]
      if win then
        netrw.load_win(win, {
          tree = state,
          file = state.visible == false and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) or nil,
          return_file = vim.w[win].netrw_rexfile,
        })
      end
    end
    netrw.on_post_load()
  end
  resession.save(root, { notify = false })
end

vim.api.nvim_create_autocmd("StdinReadPre", {
  group = group,
  callback = function()
    using_stdin = true
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  nested = true,
  callback = function()
    -- Headless commands must not overwrite interactive sessions.
    interactive = #vim.api.nvim_list_uis() > 0
    if restore_on_start and interactive and not using_stdin then
      local ok, err = pcall(load_session)
      if not ok then
        enabled = false
        vim.notify("Could not restore session: " .. err, vim.log.levels.ERROR)
      end
    end
  end,
})

vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, {
  group = group,
  callback = function()
    if interactive and enabled and not using_stdin then
      resession.save(root, { notify = false })
    end
  end,
})
