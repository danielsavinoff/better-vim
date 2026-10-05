local M = {}
local pending_views = {}
local project_root
local load_generation = 0

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("(.)/$", "%1")
end

function M.config(opts)
  project_root = opts and opts.root and normalize(opts.root) or nil

  -- Netrw's default R mapping captures the last browsed directory. Resolve the
  -- selected entry's parent each time instead; UserMaps survives tree refreshes.
  vim.g.Netrw_UserMaps = { { "R", "NetrwTreeRename" } }
  vim.cmd([[
  function! NetrwTreeRename(islocal) abort
    if !a:islocal
      let user = netrw#Expose('user')
      let host = (user == '' ? '' : user.'@').netrw#Expose('machine')
      call netrw#Call('NetrwRemoteRename', host, netrw#Expose('path'))
      return ''
    endif

    if line('.') < get(w:, 'netrw_bannercnt', 1)
      return ''
    endif
    let word = netrw#Call('NetrwGetWord')
    if word == './' || word == '../'
      return ''
    endif

    let directory = b:netrw_curdir
    if get(w:, 'netrw_liststyle', 0) == 3
      let directory = netrw#Call('NetrwTreePath', w:netrw_treetop)
      " TreePath includes the entry itself for directories and displayed links.
      if word =~ '/$' || getline('.') =~ '@\s\+-->'
        let directory = fnamemodify(substitute(directory, '/$', '', ''), ':h')
      endif
    endif

    " Remove expanded descendants before netrw refreshes a renamed directory.
    let expanded = {}
    let selected = substitute(netrw#fs#ComposePath(directory, word), '/$', '', '')
    if get(w:, 'netrw_liststyle', 0) == 3 && isdirectory(selected)
      for path in keys(get(w:, 'netrw_treedict', {}))
        if path == selected || stridx(path, selected.'/') == 0
          let expanded[path] = remove(w:netrw_treedict, path)
        endif
      endfor
    endif

    " Refresh the selected entry's parent after renaming, including directories.
    let b:netrw_curdir = directory
    call netrw#Call('NetrwLocalRename', directory)
    " Keep expansion state when the prompt is cancelled or the rename fails.
    if !empty(expanded) && isdirectory(selected)
      let view = winsaveview()
      call extend(w:netrw_treedict, expanded)
      call netrw#LocalBrowseCheck(directory)
      call winrestview(view)
    endif
    return ''
  endfunction
  ]])
end

local function inside(path, root)
  if not path or path == "" then
    return false
  end
  path = normalize(path)
  return path == root or vim.startswith(path, root == "/" and root or root .. "/")
end

local function project_state(state, fallback_root)
  state = vim.deepcopy(state or {})
  local root = project_root or fallback_root or state.directory
  if not root then
    return nil
  end
  root = normalize(root)
  local outside = state.directory and not inside(state.directory, root)
  state.directory = root
  state.style = 3
  local expanded = {}
  for _, path in ipairs(state.expanded or {}) do
    if inside(path, root) then
      path = normalize(path)
      -- A saved subtree can omit its ancestors. Expand those as well so the
      -- restored listing always includes the entire project above it.
      while path ~= root and inside(path, root) do
        expanded[path] = true
        path = vim.fs.dirname(path)
      end
    end
  end
  state.expanded = vim.tbl_keys(expanded)
  state.view = state.view or { lnum = 1, col = 0, topline = 1 }
  if (state.selected_path and not inside(state.selected_path, root))
    or (outside and not state.selected_path) then
    state.selected_path = nil
    state.selected = nil
    state.view = { lnum = 1, col = 0, topline = 1 }
  elseif state.selected_path then
    state.selected_path = normalize(state.selected_path)
  end
  return state
end

local function return_file(path)
  if not path or path == "" then
    return nil
  end
  -- Netrw stores this path escaped for a Vim command, not as a filename.
  local filename = vim.fn.filereadable(path) == 1 and path or vim.fn.glob(path, false, true)[1]
  if filename and (not project_root or inside(filename, project_root)) then
    return vim.fn.fnameescape(filename)
  end
end

local function listing_paths()
  local paths = {}
  local parents = { [0] = vim.w.netrw_treetop or vim.b.netrw_curdir }
  if vim.w.netrw_liststyle ~= 3 or not parents[0] then
    return paths
  end
  for line, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local depth = 0
    while text:sub(1, 2) == "| " or text:sub(1, 4) == "│ " do
      text = text:sub(text:sub(1, 2) == "| " and 3 or 5)
      depth = depth + 1
    end
    text = text:gsub("\t%s*%-%->.*$", "")
    if depth > 0 and parents[depth - 1] then
      local path = vim.fs.joinpath(parents[depth - 1], (text:gsub("[/@*=|]$", "")))
      paths[line] = path
      parents[depth] = path
    end
  end
  return paths
end

local function capture_window()
  local directory = vim.w.netrw_treetop or vim.b.netrw_curdir
  if project_root and not inside(directory, project_root) then
    -- Browsing elsewhere must not replace the project's remembered tree.
    return project_state(vim.w.netrw_session_state, project_root)
  end
  return project_state({
    directory = directory,
    expanded = vim.tbl_keys(vim.w.netrw_treedict or {}),
    style = vim.w.netrw_liststyle or vim.g.netrw_liststyle,
    view = vim.fn.winsaveview(),
    selected = vim.fn.getline("."),
    selected_path = listing_paths()[vim.fn.line(".")],
  })
end

local function restore_view(state)
  local view = vim.deepcopy(state.view)
  local nearest
  local paths = listing_paths()
  for line, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local matches = state.selected_path and paths[line] == state.selected_path
      or not state.selected_path and text == state.selected
    if matches and (not nearest or math.abs(line - view.lnum) < math.abs(nearest - view.lnum)) then
      nearest = line
    end
  end
  view.lnum = nearest or math.min(view.lnum, vim.api.nvim_buf_line_count(0))
  vim.fn.winrestview(view)
end

local function restore_tree(state)
  state = project_state(state)
  if not state or vim.fn.isdirectory(state.directory) == 0 then
    return false
  end

  vim.w.netrw_treetop = nil
  vim.w.netrw_treedict = nil
  vim.w.netrw_liststyle = state.style
  vim.fn["netrw#LocalBrowseCheck"](state.directory)

  local parent = state.selected_path and vim.fs.dirname(state.selected_path)
  while parent and parent ~= state.directory and inside(parent, state.directory) do
    if not vim.tbl_contains(state.expanded, parent) then
      table.insert(state.expanded, parent)
    end
    parent = vim.fs.dirname(parent)
  end
  table.sort(state.expanded, function(a, b)
    return #a < #b
  end)
  for _, directory in ipairs(state.expanded) do
    if directory ~= state.directory and inside(directory, state.directory)
      and vim.fn.isdirectory(directory) == 1 then
      vim.fn["netrw#LocalBrowseCheck"](directory)
    end
  end
  restore_view(state)
  return true
end

-- File windows also carry the hidden tree history used by :Rex. Resession still
-- saves their file buffers and cursor positions; this extension restores the
-- window's buffer and its additional netrw state.
function M.is_win_supported(winid, bufnr)
  return vim.bo[bufnr].filetype == "netrw"
    or (vim.w[winid].netrw_session_state ~= nil
      and require("resession.config").buf_filter(bufnr))
end

function M.save_win(winid)
  return vim.api.nvim_win_call(winid, function()
    local visible = vim.bo.filetype == "netrw"
    return {
      tree = visible and capture_window() or project_state(vim.w.netrw_session_state),
      file = not visible and vim.api.nvim_buf_get_name(0) or nil,
      return_file = return_file(vim.w.netrw_rexfile),
    }
  end)
end

function M.on_pre_load()
  pending_views = {}
  load_generation = load_generation + 1
end

function M.on_save()
  -- Resession invokes the load callbacks for extensions with saved data.
  return {}
end

function M.load_win(winid, state)
  return vim.api.nvim_win_call(winid, function()
    local tree = project_state(state.tree)
    vim.w.netrw_session_state = tree
    if state.file and (not project_root or inside(state.file, project_root)) then
      local bufnr = vim.fn.bufadd(state.file)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.bo[bufnr].filetype = vim.bo[bufnr].filetype
      vim.b[bufnr].resession_restore_last_pos = nil
    elseif restore_tree(tree) then
      table.insert(pending_views, {
        winid = vim.api.nvim_get_current_win(),
        bufnr = vim.api.nvim_get_current_buf(),
        state = tree,
      })
    end
    vim.w.netrw_rexfile = return_file(state.return_file)
    return vim.api.nvim_get_current_win()
  end)
end

function M.on_post_load()
  -- Resession restores numeric cursor positions after load_win. Re-select by
  -- full path afterward, so new files don't move the cursor to another entry.
  local entries = pending_views
  local generation = load_generation
  for _, entry in ipairs(entries) do
    if vim.api.nvim_win_is_valid(entry.winid) then
      vim.api.nvim_win_call(entry.winid, function()
        if vim.bo.filetype == "netrw" then
          restore_view(entry.state)
        end
      end)
    end
  end
  pending_views = {}
  -- Resession ends load() with :edit, which empties the active nofile netrw
  -- buffer. Repair that listing after load() returns and before the next draw.
  vim.schedule(function()
    if generation ~= load_generation then
      return
    end
    for _, entry in ipairs(entries) do
      if vim.api.nvim_win_is_valid(entry.winid)
        and vim.api.nvim_win_get_buf(entry.winid) == entry.bufnr then
        vim.api.nvim_win_call(entry.winid, function()
          if vim.bo.filetype == "netrw" then
            if vim.api.nvim_buf_line_count(0) == 1 and vim.fn.getline(1) == "" then
              restore_tree(entry.state)
            else
              restore_view(entry.state)
            end
          end
        end)
      end
    end
  end)
end

function M.rex(root_directory)
  if vim.bo.filetype == "netrw" then
    local state = capture_window()
    vim.w.netrw_session_state = state
    local file = return_file(vim.w.netrw_rexfile)
    if file then
      vim.w.netrw_rexfile = file
      vim.cmd("Rexplore")
    elseif state then
      restore_tree(state)
    end
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  local state = project_state(vim.w.netrw_session_state or {
    directory = root_directory,
    expanded = {},
    style = 3,
    view = { lnum = 1, col = 0, topline = 1 },
    selected_path = file,
  }, root_directory)
  if restore_tree(state) then
    vim.w.netrw_rexfile = return_file(vim.fn.fnameescape(file))
  end
end

vim.api.nvim_create_autocmd("BufLeave", {
  group = vim.api.nvim_create_augroup("resession_netrw_history", { clear = true }),
  callback = function()
    if vim.bo.filetype == "netrw" and not require("resession").is_loading() then
      vim.w.netrw_session_state = capture_window()
    end
  end,
})

return M
