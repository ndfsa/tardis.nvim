local adapters = require('tardis-nvim.adapters')
local buffer = require('tardis-nvim.buffer')

local M = {}

---@class TardisSession
---@field parent TardisSessionManager
---@field augroup integer
---@field filename string
---@field filetype string
---@field path string
---@field origin integer
---@field buffers TardisBuffer[]
---@field adapter TardisAdapter
M.Session = {}

---@param parent TardisSessionManager
---@param adapter TardisAdapter?
function M.Session:new(parent, adapter)
    local session = {}
    setmetatable(session, self)
    self.__index = self
    session:init(parent, adapter)

    return session
end

---@param revision string
function M.Session:create_buffer(index)
    local fd = vim.api.nvim_create_buf(false, true)
    local revision = self.log[index]
    local file_at_revision = self.adapter.get_file_at_revision(revision, self)

    vim.api.nvim_buf_set_lines(fd, 0, -1, false, file_at_revision)
    vim.api.nvim_set_option_value('filetype', self.filetype, { buf = fd })
    vim.api.nvim_set_option_value('readonly', true, { buf = fd })
    vim.api.nvim_buf_set_name(fd, string.format('%s (%s)', self.filename, revision))

    local keymap = self.parent.config.keymap
    vim.keymap.set('n', keymap.next, function() self:next_buffer() end, { buffer = fd })
    vim.keymap.set('n', keymap.prev, function() self:prev_buffer() end, { buffer = fd })
    vim.keymap.set('n', keymap.quit, function() self:close() end, { buffer = fd })
    vim.keymap.set('n', keymap.revision_message, function() self:create_info_buffer(revision) end, { buffer = fd })
    vim.keymap.set('n', keymap.commit, function() self:commit_to_origin() end, { buffer = fd })

    return buffer.Buffer:new(fd)
end

function M.Session:create_info_buffer(revision)
    local message = self.adapter.get_revision_info(revision, self)
    if not message or #message == 0 then
        vim.notify('revision_message was empty')
        return
    end
    local fd = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(fd, 0, -1, false, message)
    -- TODO: use appropriate filetype
    vim.api.nvim_set_option_value('filetype', 'gitrevision', { buf = fd })
    vim.api.nvim_set_option_value('readonly', true, { buf = fd })

    local current_ui = vim.api.nvim_list_uis()[1]
    if not current_ui then
        error('no ui found')
    end
    vim.api.nvim_open_win(fd, false, {
        relative = 'win',
        anchor = 'NE',
        width = 100,
        height = #message,
        row = 0,
        col = current_ui.width,
    })
end

---@param parent TardisSessionManager
---@param adapter_type string
function M.Session:init(parent, adapter_type)
    local adapter = adapters.get_adapter(adapter_type)
    if not adapter then
        return
    end

    self.adapter = adapter
    self.filetype = vim.api.nvim_get_option_value('filetype', { buf = 0 })
    self.filename = vim.api.nvim_buf_get_name(0)
    self.origin = vim.api.nvim_get_current_buf()
    self.parent = parent
    self.path = vim.fn.expand('%:p')
    self.buffers = {}
    self.log = self.adapter.get_revisions_for_current_file(self)

    if vim.tbl_isempty(self.log) then
        vim.notify('No previous revisions of this file were found', vim.log.levels.WARN)
        return
    end

    parent:on_session_opened(self)
end

function M.Session:close()
    for _, buf in ipairs(self.buffers) do
        buf:close()
    end
    if self.parent then
        self.parent:on_session_closed(self)
    end
end

---@return TardisBuffer
function M.Session:get_current_buffer()
    return self.buffers[self.curret_buffer_index]
end

---@param index integer
function M.Session:goto_buffer(index)
    if index < 1 or index >= #self.log then
        return false
    end
    if not self.buffers[index] then
        self.buffers[index] = self:create_buffer(index)
    end
    self.buffers[index]:focus()
    self.curret_buffer_index = index
    return true
end

function M.Session:next_buffer()
    if not self:goto_buffer(self.curret_buffer_index + 1) then
        vim.notify('No earlier revisions of file')
    end
end

function M.Session:prev_buffer()
    if not self:goto_buffer(self.curret_buffer_index - 1) then
        vim.notify('No earlier revisions of file')
    end
end

function M.Session:commit_to_origin()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.api.nvim_buf_set_lines(self.origin, 0, -1, false, lines)
    self:close()
end

return M
