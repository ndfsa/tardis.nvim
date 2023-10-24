local Job = require('plenary.job')

local config = {
    keymap = {
        next = 'n',
        prev = 'p',
        quit = 'q',
        commit_message = 'm',
    },
    commits = 32,
}

local function get_git_root()
    return Job:new({
        command = 'git',
        args = { 'rev-parse', '--show-toplevel' },
        on_exit = function (j, status)
            if status ~= 0 then
                error("git couldn't resolve the root", 4)
            end

            return j:result()
        end
    }):sync()[1]
end

local function file_at_rev(revision, path)
    return Job:new {
        command = 'git',
        args = { 'show', string.format('%s:%s', revision, path)}
    }:sync()
end

local function get_git_commits_for_current_file(file)
    local log = Job:new({
        command = 'git',
        args = { '-C', get_git_root(), 'log', '-n', config.commits, '--pretty=format:%h', '--', file },
    }):sync()
    return log
end

local function show_commit_message(buffer_info)
    return function ()
        local message = Job:new({
            command = 'git',
            args = { '-C', get_git_root(), 'show', '--compact-summary', buffer_info.commit }
        }):sync()

        local buffer = vim.api.nvim_create_buf(false, true)
        vim.keymap.set('n', config.keymap.quit, vim.api.nvim_buf_delete, { buffer = buffer })
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, message)
        vim.api.nvim_buf_set_option(buffer, 'filetype', 'gitcommit')
        vim.api.nvim_buf_set_option(buffer, 'readonly', true)
        vim.api.nvim_open_win(buffer, true, { relative = 'win', width = 100, height = #message, bufpos = {10, 10} })
    end
end

local function goto_buffer(buffers, index)
    return function()
        local current_pos = vim.api.nvim_win_get_cursor(0)
        vim.api.nvim_win_set_buf(0, buffers[index].fd)
        vim.api.nvim_win_set_cursor(0, current_pos)
    end
end

local function exit_all(buffers)
    return function()
        for _, buffer in ipairs(buffers) do
            vim.api.nvim_buf_delete(buffer.fd, { force = true })
        end
    end
end

local function setup_keymap(buffers)
    for i, buffer_info in ipairs(buffers) do
        local buffer = buffer_info.fd
        vim.keymap.set('n', config.keymap.quit, exit_all(buffers), { buffer = buffer })
        vim.keymap.set('n', config.keymap.commit_message, show_commit_message(buffers), { buffer = buffer })

        if i > 1 then
            vim.keymap.set('n', config.keymap.prev, goto_buffer(buffers, i - 1), { buffer = buffer })
        else
            vim.keymap.set('n', config.keymap.prev, '<Nop>', { buffer = buffer })
        end
        if i < #buffers then
            vim.keymap.set('n', config.keymap.next, goto_buffer(buffers, i + 1), { buffer = buffer })
        else
            vim.keymap.set('n', config.keymap.next, '<Nop>', { buffer = buffer })
        end
    end
end

local function tardis()
    local path = vim.fn.expand('%')
    local filetype = vim.bo.filetype

    local log = get_git_commits_for_current_file(path)

    local buffers = {}
    for i, commit in ipairs(log) do
        buffers[i] = {
            fd = vim.api.nvim_create_buf(false, true),
            commit = commit
        }
        local buffer = buffers[i].fd
        local file_at_commit = file_at_rev(commit, path)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, file_at_commit)
        vim.api.nvim_buf_set_option(buffer, 'filetype', filetype)
        vim.api.nvim_buf_set_option(buffer, 'readonly', true)
        vim.api.nvim_buf_set_name(buffer, commit)
    end
    setup_keymap(buffers)

    goto_buffer(buffers, 1)()
end

local function setup(user_config)
    user_config = user_config or {}
    config = vim.tbl_deep_extend('keep', user_config, config)

    vim.api.nvim_create_user_command("Tardis", tardis, {})
end

return {
    setup = setup,
    tardis = tardis,
}
