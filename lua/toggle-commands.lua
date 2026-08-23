local M = {}

-- Default configuration options
M.opts = {
  terminal_opts = {
    id = 99,
    direction = "horizontal",
  },
  commands = {
    {
      name = "Run Python/Bash file",
      cmd = "chmod +x {input} && {input:p}",
    },
    {
      name = "Grep occurrences in project",
      cmd = "rg {input}",
    },
    {
      name = "Git log / history for file",
      cmd = "git log --follow -p -- {input}",
    },
    {
      name = "Find occurrences with file filter",
      cmd = "rg {input} -g {prompt:Glob pattern (e.g. *.lua)}",
    },
    {
      name = "Git commit staged changes",
      cmd = "git commit -m {prompt:Commit Message}",
    },
  },
}

-- Helper to extract visual selection
local function get_visual_selection()
  local mode_char = vim.fn.mode()
  local is_visual = mode_char:match("[vV\22]")
  local vstart = vim.fn.getpos(is_visual and "v" or "'<")
  local vend = vim.fn.getpos(is_visual and "." or "'>")
  local start_line, end_line = vstart[2], vend[2]
  local start_col, end_col = vstart[3], vend[3]

  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  if start_line == 0 then
    start_line = vim.api.nvim_win_get_cursor(0)[1]
    end_line = start_line
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return "", start_line, end_line
  end

  if is_visual and mode_char == "V" then
    return table.concat(lines, "\n"), start_line, end_line
  end

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  return table.concat(lines, "\n"), start_line, end_line
end

-- Helper to construct full context table
function M.build_context(mode)
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local sel_text, s_line, e_line = get_visual_selection()

  local is_file = false
  local input = ""
  local mode_name = "Auto"

  local current_mode = vim.fn.mode()
  local is_visual = current_mode:match("[vV\22]")

  if mode == "file" then
    input = filepath
    is_file = true
    mode_name = "File"
  elseif mode == "word" then
    input = vim.fn.expand("<cword>")
    is_file = false
    mode_name = "Word"
  elseif mode == "selection" then
    input = sel_text
    is_file = false
    mode_name = "Selection"
  else
    if is_visual and sel_text ~= "" then
      input = sel_text
      is_file = false
      mode_name = "Selection"
    elseif filepath and filepath ~= "" then
      input = filepath
      is_file = true
      mode_name = "File"
    else
      input = vim.fn.expand("<cword>")
      is_file = false
      mode_name = "Word"
    end
  end

  return {
    input = input,
    is_file = is_file,
    bufnr = bufnr,
    filepath = filepath,
    line = cursor_pos[1],
    line_count = vim.api.nvim_buf_line_count(bufnr),
    line_text = vim.api.nvim_get_current_line(),
    selection = sel_text,
    start_line = s_line,
    end_line = e_line,
    mode_name = mode_name,
  }
end

-- Helper to substitute placeholders in command templates
local function substitute(cmd, ctx)
  -- 1. {input:MODIFIERS} or {input}
  local result = cmd:gsub("({input:?([^}]*)})", function(match, modifier)
    if modifier == "" then
      local resolved = ctx.is_file and vim.fn.fnamemodify(ctx.input, ":.") or ctx.input
      return vim.fn.shellescape(resolved)
    else
      if ctx.is_file then
        local resolved = vim.fn.fnamemodify(ctx.input, ":" .. modifier)
        return vim.fn.shellescape(resolved)
      else
        return vim.fn.shellescape(ctx.input)
      end
    end
  end)

  -- 2. Line context (numbers kept unquoted for clean range syntax)
  result = result:gsub("{line}", tostring(ctx.line or 1))
  result = result:gsub("{line_count}", tostring(ctx.line_count or 1))
  result = result:gsub("{start_line}", tostring(ctx.start_line or ctx.line or 1))
  result = result:gsub("{end_line}", tostring(ctx.end_line or ctx.line or 1))

  -- 3. Line text and selection
  result = result:gsub("{line_text}", function()
    return vim.fn.shellescape(ctx.line_text or "")
  end)
  result = result:gsub("{selection}", function()
    return vim.fn.shellescape(ctx.selection or "")
  end)

  -- 4. Clipboard contents
  result = result:gsub("{clipboard}", function()
    local cb = vim.fn.getreg("+")
    if cb == "" then
      cb = vim.fn.getreg('"')
    end
    return vim.fn.shellescape(cb)
  end)

  -- 5. Git context
  result = result:gsub("{git_branch}", function()
    local dir = (ctx.filepath and ctx.filepath ~= "") and vim.fs.dirname(ctx.filepath) or vim.fn.getcwd()
    local res = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --abbrev-ref HEAD 2>/dev/null")
    local branch = (vim.v.shell_error == 0 and res and #res > 0) and res[1] or ""
    return vim.fn.shellescape(branch)
  end)

  result = result:gsub("{git_root}", function()
    local dir = (ctx.filepath and ctx.filepath ~= "") and vim.fs.dirname(ctx.filepath) or vim.fn.getcwd()
    local res = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")
    local root = (vim.v.shell_error == 0 and res and #res > 0) and res[1] or ""
    return vim.fn.shellescape(root)
  end)

  result = result:gsub("{blame_commit}", function()
    if not ctx.filepath or ctx.filepath == "" then
      return ""
    end
    local dir = vim.fs.dirname(ctx.filepath)
    local line_num = ctx.line or 1
    local res = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " blame -L " .. line_num .. "," .. line_num .. " -l --porcelain " .. vim.fn.shellescape(ctx.filepath) .. " 2>/dev/null")
    if vim.v.shell_error == 0 and res and #res > 0 then
      local commit = res[1]:match("^(%x+)")
      return vim.fn.shellescape(commit or "")
    end
    return ""
  end)

  return result
end

-- Execute in ToggleTerm
function M.run_in_toggleterm(cmd, terminal_opts)
  local toggleterm = require("toggleterm")

  local opts = {
    id = 99,
    direction = "horizontal",
  }

  if M.opts.terminal_opts then
    opts = vim.tbl_deep_extend("force", opts, M.opts.terminal_opts)
  end

  if terminal_opts then
    opts = vim.tbl_deep_extend("force", opts, terminal_opts)
  end

  local id = opts.id or opts.num or 99

  -- exec(cmd, num, size, dir, direction, name, go_back, open)
  toggleterm.exec(
    cmd,
    id,
    opts.size,
    opts.dir,
    opts.direction,
    opts.name,
    opts.go_back,
    opts.open
  )
end

-- Handle prompt and execute command
function M.execute_command(entry)
  local cmd = entry.cmd_substituted
  local prompt_pattern = "({prompt:?([^}]*)})"
  local match, label = cmd:match(prompt_pattern)

  if match then
    local prompt_label = (label and label ~= "") and label or "Input"
    vim.ui.input({ prompt = "Enter value for [" .. prompt_label .. "]: " }, function(input)
      if input then
        local escaped_input = vim.fn.shellescape(input)
        local pattern_escaped = match:gsub("([^%w])", "%%%1")
        local final_cmd = cmd:gsub(pattern_escaped, escaped_input)
        M.run_in_toggleterm(final_cmd, entry.terminal_opts)
      end
    end)
  else
    M.run_in_toggleterm(cmd, entry.terminal_opts)
  end
end

-- Helper to find a command by name, index, or table
local function find_command(identifier)
  if type(identifier) == "table" then
    return identifier
  end
  if type(identifier) == "number" then
    return M.opts.commands and M.opts.commands[identifier]
  end
  if type(identifier) == "string" then
    local num = tonumber(identifier)
    if num and M.opts.commands and M.opts.commands[num] then
      return M.opts.commands[num]
    end
    for _, cmd in ipairs(M.opts.commands or {}) do
      if cmd.name:lower() == identifier:lower() then
        return cmd
      end
    end
  end
  return nil
end

-- Launch a command directly from Neovim without opening the picker
function M.run(identifier, context_mode)
  local cmd_opt = find_command(identifier)
  if not cmd_opt then
    vim.notify("toggle-commands: Command not found: " .. tostring(identifier), vim.log.levels.ERROR)
    return
  end

  local mode = context_mode or cmd_opt.context or "auto"
  local ctx = M.build_context(mode)
  local substituted = substitute(cmd_opt.cmd, ctx)

  M.execute_command({
    name = cmd_opt.name,
    cmd_raw = cmd_opt.cmd,
    cmd_substituted = substituted,
    terminal_opts = cmd_opt.terminal_opts,
  })
end

-- Open the picker
function M.open_picker(val, is_file, extra_ctx)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local ctx
  if type(val) == "table" and val.input ~= nil then
    ctx = val
  else
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)

    ctx = {
      input = val,
      is_file = is_file,
      bufnr = bufnr,
      filepath = vim.api.nvim_buf_get_name(bufnr),
      line = cursor_pos[1],
      line_count = vim.api.nvim_buf_line_count(bufnr),
      line_text = vim.api.nvim_get_current_line(),
    }

    if extra_ctx then
      ctx = vim.tbl_deep_extend("force", ctx, extra_ctx)
    end
  end

  local items = {}
  for _, cmd_opt in ipairs(M.opts.commands) do
    local substituted = substitute(cmd_opt.cmd, ctx)
    local key = cmd_opt.key or cmd_opt.keys or cmd_opt.mapping
    local key_label = ""
    if key then
      key_label = type(key) == "table" and table.concat(key, ", ") or tostring(key)
    end
    local display_label = (key_label ~= "") and (cmd_opt.name .. " [" .. key_label .. "]") or cmd_opt.name

    table.insert(items, {
      name = cmd_opt.name,
      display_label = display_label,
      cmd_raw = cmd_opt.cmd,
      cmd_substituted = substituted,
      terminal_opts = cmd_opt.terminal_opts,
      key = key,
    })
  end

  -- Dynamically calculate the maximum command name length for clean alignment
  local max_name_len = 20
  for _, item in ipairs(items) do
    local name_len = vim.fn.strdisplaywidth(item.display_label)
    if name_len > max_name_len then
      max_name_len = name_len
    end
  end

  local displayer = entry_display.create {
    separator = " │ ",
    items = {
      { width = max_name_len },
      { remaining = true },
    },
  }

  local display_name = ctx.mode_name or (ctx.is_file and "File" or "Word")
  local display_val = ctx.is_file and vim.fn.fnamemodify(ctx.input, ":t") or ctx.input
  if #display_val > 25 then
    display_val = display_val:sub(1, 22) .. "..."
  end

  pickers.new({}, {
    prompt_title = "Run command (" .. display_name .. ": " .. display_val .. ")",
    finder = finders.new_table {
      results = items,
      entry_maker = function(entry)
        local make_display = function(ent)
          return displayer {
            ent.value.display_label,
            ent.value.cmd_substituted,
          }
        end

        return {
          value = entry,
          display = make_display,
          ordinal = entry.display_label .. " " .. entry.cmd_substituted,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          M.execute_command(selection.value)
        end
      end)

      -- Bind direct shortcuts for configured commands
      for _, item in ipairs(items) do
        if item.key then
          local keys = type(item.key) == "table" and item.key or { item.key }
          for _, k in ipairs(keys) do
            local run_item = function()
              actions.close(prompt_bufnr)
              M.execute_command(item)
            end
            map("i", k, run_item)
            map("n", k, run_item)
          end
        end
      end

      -- Edit command in-line before execution with <C-e>
      local edit_cmd = function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)
          vim.ui.input({
            prompt = "Edit command: ",
            default = selection.value.cmd_substituted,
          }, function(edited_cmd)
            if edited_cmd and edited_cmd ~= "" then
              M.run_in_toggleterm(edited_cmd, selection.value.terminal_opts)
            end
          end)
        end
      end

      map("i", "<C-e>", edit_cmd)
      map("n", "<C-e>", edit_cmd)

      return true
    end,
  }):find()
end

-- Main interface function to open picker
function M.open(mode)
  local val = ""
  local is_file = false
  local extra_ctx = {}

  if mode == "file" then
    val = vim.api.nvim_buf_get_name(0)
    if val == "" then
      vim.notify("No file active in current buffer", vim.log.levels.WARN)
      return
    end
    is_file = true
    extra_ctx.mode_name = "File"
  elseif mode == "word" then
    val = vim.fn.expand("<cword>")
    if val == "" then
      vim.ui.input({ prompt = "No word under cursor. Enter input: " }, function(input)
        if input and input ~= "" then
          M.open_picker(input, false, { mode_name = "Word" })
        end
      end)
      return
    end
    extra_ctx.mode_name = "Word"
  elseif mode == "selection" then
    local sel_text, s_line, e_line = get_visual_selection()
    val = sel_text
    is_file = false
    extra_ctx.selection = sel_text
    extra_ctx.start_line = s_line
    extra_ctx.end_line = e_line
    extra_ctx.mode_name = "Selection"
  end

  M.open_picker(val, is_file, extra_ctx)
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts or {}, opts or {})

  -- Register global keybindings for configured commands
  for idx, cmd_opt in ipairs(M.opts.commands or {}) do
    local key = cmd_opt.key or cmd_opt.keys or cmd_opt.mapping
    if key then
      local keys = type(key) == "table" and key or { key }
      local key_modes = cmd_opt.key_mode or cmd_opt.key_modes
      if not key_modes then
        if cmd_opt.context == "selection" then
          key_modes = { "v" }
        else
          key_modes = { "n", "v" }
        end
      end
      if type(key_modes) == "string" then
        key_modes = { key_modes }
      end

      local target_cmd = cmd_opt
      for _, k in ipairs(keys) do
        vim.keymap.set(key_modes, k, function()
          M.run(target_cmd, target_cmd.context)
        end, {
          desc = target_cmd.name or ("Toggle Command " .. idx),
          silent = true,
        })
      end
    end
  end

  -- Register user commands
  pcall(vim.api.nvim_create_user_command, "ToggleCommand", function(cmd_opts)
    if cmd_opts.args and cmd_opts.args ~= "" then
      M.run(cmd_opts.args)
    else
      M.open("file")
    end
  end, {
    nargs = "?",
    complete = function(arg_lead)
      local matches = {}
      for _, cmd in ipairs(M.opts.commands or {}) do
        if not arg_lead or arg_lead == "" or cmd.name:lower():find(arg_lead:lower(), 1, true) then
          table.insert(matches, cmd.name)
        end
      end
      return matches
    end,
    desc = "Run a toggle-command directly by name or index",
  })

  pcall(vim.api.nvim_create_user_command, "ToggleCommands", function(cmd_opts)
    local mode = (cmd_opts.args and cmd_opts.args ~= "") and cmd_opts.args or "file"
    M.open(mode)
  end, {
    nargs = "?",
    complete = function()
      return { "file", "word", "selection" }
    end,
    desc = "Open toggle-commands picker",
  })
end

return M
