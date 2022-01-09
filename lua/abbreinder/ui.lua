local abbreinder = require('abbreinder')
local default_config = require('abbreinder.config')

local api = vim.api
local ns_name = 'abbreinder'
local ui = {
    -- [id] = {tooltip_id}
    _ext_data = {},
}

local function close_tooltip(win_id)
    -- nvim_win_is_valid doesn't check if id is nil
    if win_id ~= nil and api.nvim_win_is_valid(win_id) then
        api.nvim_win_close(win_id, true)
    end
end

local function open_tooltip(abbr_data, text, ext_id)
    local buf = api.nvim_create_buf(false, true) -- create new emtpy buffer

    api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf, 'buflisted', false)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_lines(buf, 0, -1, true, { text })
    api.nvim_buf_set_option(buf, 'modifiable', false)
    api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { silent = true, nowait = true, noremap = true })

    -- set some options
    local opts = {
        style = 'minimal',
        relative = 'win',
        anchor = 'SW',
        width = #text,
        height = 1,
        focusable = false,
        noautocmd = true,
        bufpos = { abbr_data.row, abbr_data.col },
    }

    opts = vim.tbl_extend('force', opts, ui.config.output.tooltip.opts)

    -- and finally create it with buffer attached
    local tooltip_id = api.nvim_open_win(buf, false, opts)
    api.nvim_buf_add_highlight(buf, -1, ui.config.output.tooltip.highlight, 0, 0, -1)
    ui._ext_data[ext_id].tooltip_id = tooltip_id

    vim.defer_fn(function()
        close_tooltip(tooltip_id)
    end, ui.config.output.tooltip.time_open)
end

-- uses extmarks to manage highlights of value based on user-given config
-- @return ext_id
local function highlight_unexpanded_abbr(abbr_data)
    local buf = api.nvim_get_current_buf()

    local ns_id = api.nvim_create_namespace(ns_name)

    local ext_id = api.nvim_buf_set_extmark(buf, ns_id, abbr_data.row, abbr_data.col + 1, {
        end_col = abbr_data.col_end + 1,
        hl_group = ui.config.output.msg.highlight,
    })

    ui._ext_data[ext_id] = {}

    if ui.config.output.msg.highlight_time ~= -1 then
        vim.defer_fn(function()
            api.nvim_buf_del_extmark(0, ns_id, ext_id)
        end, ui.config.output.msg.highlight_time)
    end

    return ext_id
end

-- @param abbr {trigger, value, row, col, col_end, on_change}
local function output_reminder(abbr_data)

    -- case of people using abbreviations to correct typos
    if #abbr_data.trigger == #abbr_data.value then
        return
    end

    local msg = ui.config.output.msg.format(abbr_data.trigger, abbr_data.value)

    local ext_id = highlight_unexpanded_abbr(abbr_data)
    abbr_data.on_change(function()
        ui.close_reminders(ext_id)
    end)

    if ui.config.output.as.tooltip then
        -- if not scheduled, E523 because can't manipulate buffers
        -- on InsertCharPre
        vim.schedule(function()
            open_tooltip(abbr_data, msg, ext_id)
        end)
    end

    if ui.config.output.as.echo then
        api.nvim_echo({ { msg } }, { false }, {})
    end
end

function ui.close_reminders(ext_id)

    local ext_data = ui._ext_data[ext_id]
    local ns_id = api.nvim_create_namespace(ns_name)
    -- todo: abstract to function remove highlight??
    api.nvim_buf_del_extmark(0, ns_id, ext_id)
    close_tooltip(ext_data.tooltip_id)
end

local function create_ex_commands()
    vim.cmd([[
    command! -bang AbbreinderEnable lua require('abbreinder.ui').enable()
    command! -bang AbbreinderDisable lua require('abbreinder.ui').disable()
    ]])
end

function ui.enable()
    create_ex_commands()
    abbreinder.on_abbr_forgotten(output_reminder)
end

function ui.disable()
    -- unsubscribe from all
end

-- @Summary Sets up abbreinder
-- @Description launch abbreinder with specified config (falling back to defaults from ./abbreinder/config.lua)
-- @Param config(table) - user specified config
function ui.setup(user_config)
    user_config = user_config or {}

    ui.config = vim.tbl_deep_extend('force', default_config, user_config)
    ui.enable()
end

return ui
