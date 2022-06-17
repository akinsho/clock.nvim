local M = {}
local api = vim.api

local numbers = require('clock.numbers')

local chars = {
  [1] = '█',
}

local config = (function()
  local padding = string.rep(' ', 5)
  return {
    border = 'rounded',
    separator = {
      padding,
      ' ' .. chars[1]:rep(2) .. '  ',
      padding,
      ' ' .. chars[1]:rep(2) .. '  ',
      padding,
    },
  }
end)()

---@class JoinOpts
---@field before string[]
---@field list string[]
---@field after string[]

---@param opts JoinOpts
---@return string[]
local join = function(opts)
  local after, list, before = opts.after or {}, opts.list or {}, opts.before or {}
  local result = {}
  for index, item in ipairs(list) do
    local before_item = before[index] or ''
    local after_item = after[index] or ''
    table.insert(result, before_item .. item .. after_item)
  end
  return result
end

local split = function(str)
  return vim.split(str, '\n')
end

--- Takes a time represented as HH:MM and returns a list of lines to render in the buffer
---@param h1 number
---@param h2 number
---@param m1 number
---@param m2 number
---@return string[]
local function get_lines(h1, h2, m1, m2)
  local sep = config.separator
  local padding = vim.split(string.rep(' ', 5), '')

  local h1_lines = join({
    before = padding,
    list = split(numbers[h1 + 1]),
    after = padding,
  })

  local h2_lines = join({
    list = split(numbers[h2 + 1]),
    after = padding,
  })

  local m1_lines = join({
    before = sep,
    list = split(numbers[m1 + 1]),
    after = padding,
  })

  local m2_lines = join({
    list = split(numbers[m2 + 1]),
    after = padding,
  })

  local result = {}
  for i, _ in ipairs(h1_lines) do
    table.insert(result, table.concat({ h1_lines[i], h2_lines[i], m1_lines[i], m2_lines[i] }))
  end
  return result
end

local draw_clock = function(conf)
  local buf = api.nvim_create_buf(false, true)
  local lines = get_lines(1, 2, 3, 0)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = api.nvim_open_win(buf, false, {
    relative = 'editor',
    anchor = 'SE',
    row = vim.o.lines - tonumber(vim.o.cmdheight) - 1 - 1,
    col = vim.o.columns,
    border = conf.border,
    height = conf.height or #lines,
    width = conf.width or 40,
    style = 'minimal',
  })
  return win, buf
end

local update_clock = function(time, _, buf)
  local hr, min = unpack(vim.split(time, ':'))
  local h1, h2 = unpack(vim.split(hr, ''))
  local m1, m2 = unpack(vim.split(min, ''))
  local lines = get_lines(h1, h2, m1, m2)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local timers = {}

local function start_timer(duration, callback)
  assert(callback, 'A callback must be passed to a timer')
  local timer = vim.loop.new_timer()
  timers[timer] = os.time() + duration
  timer:start(0, 1000, function()
    if timers[timer] <= os.time() then
      timer:close()
      timer:close()
    end
    vim.schedule(function()
      callback(timer)
    end)
  end)
end

local function start_clock()
  local win, buf = draw_clock(config)
  update_clock(os.date('%X', os.time()), win, buf)
end

---@param duration number
local function create_clock_timer(duration)
  start_timer(duration, start_clock)
end

--- @class Timer
--- @field directory string
--- @field duration number
--- @field condition fun(): boolean
local Timer = {}

function Timer:new(o)
  o = o or {}
  self.__index = self
  o.duration = o.duration or 15000
  return setmetatable(o, self)
end

--- @class Clock
local Clock = {}
function Clock:new(o)
  o = o or {}
  self.__index = self
  return setmetatable(o, self)
end

function Timer:start()
  create_clock_timer(self.duration)
end

M.Timer = Timer
M.Clock = Clock

function M.setup(c)
  config = vim.tbl_deep_extend('force', config, c)
end

return M
