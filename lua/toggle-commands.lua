local M = {}

-- Default configuration options
M.opts = {
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

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts or {}, opts or {})
end

-- Helper to substitute {input} and optional modifiers
local function substitute(cmd, val, is_file)
  -- Find matches for {input:MODIFIERS} or {input}
  local result = cmd:gsub("({input:?([^}]*)})", function(match, modifier)
    if modifier == "" then
      local resolved = is_file and vim.fn.fnamemodify(val, ":.") or val
      return vim.fn.shellescape(resolved)
    else
      if is_file then
        local resolved = vim.fn.fnamemodify(val, ":" .. modifier)
        return vim.fn.shellescape(resolved)
      else
        return vim.fn.shellescape(val)
      end
    end
  end)
  return result
end

-- Execute in ToggleTerm
function M.run_in_toggleterm(cmd, terminal_opts)
  local toggleterm = require("toggleterm")
  local id = 99 -- Dedicated ID to keep main terminal clean

  local opts = {
    direction = "horizontal",
  }

  if terminal_opts then
    opts = vim.tbl_deep_extend("force", opts, terminal_opts)
  end

  -- exec(cmd, num, size, dir, direction, name, go_back, open)
  toggleterm.exec(cmd, id, nil, nil, opts.direction, nil, nil, nil)
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

-- Open the picker
function M.open_picker(val, is_file)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local items = {}
  for _, cmd_opt in ipairs(M.opts.commands) do
    local substituted = substitute(cmd_opt.cmd, val, is_file)
    table.insert(items, {
      name = cmd_opt.name,
      cmd_raw = cmd_opt.cmd,
      cmd_substituted = substituted,
      terminal_opts = cmd_opt.terminal_opts,
    })
  end

  -- Dynamically calculate the maximum command name length for clean alignment
  local max_name_len = 20
  for _, item in ipairs(items) do
    local name_len = vim.fn.strdisplaywidth(item.name)
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

  local display_name = is_file and "File" or "Word"
  local display_val = vim.fn.fnamemodify(val, ":t")
  if display_val == "" then
    display_val = val
  end

  pickers.new({}, {
    prompt_title = "Run command (" .. display_name .. ": " .. display_val .. ")",
    finder = finders.new_table {
      results = items,
      entry_maker = function(entry)
        local make_display = function(ent)
          return displayer {
            ent.value.name,
            ent.value.cmd_substituted,
          }
        end

        return {
          value = entry,
          display = make_display,
          ordinal = entry.name .. " " .. entry.cmd_substituted,
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

-- Main interface function
function M.open(mode)
  local val = ""
  local is_file = false

  if mode == "file" then
    val = vim.api.nvim_buf_get_name(0)
    if val == "" then
      vim.notify("No file active in current buffer", vim.log.levels.WARN)
      return
    end
    is_file = true
  elseif mode == "word" then
    val = vim.fn.expand("<cword>")
    if val == "" then
      vim.ui.input({ prompt = "No word under cursor. Enter input: " }, function(input)
        if input and input ~= "" then
          M.open_picker(input, false)
        end
      end)
      return
    end
  end

  M.open_picker(val, is_file)
end

return M
