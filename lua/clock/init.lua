local M = {}
local api = vim.api

---@class Duration
---@field hours number
---@field minutes number

local numbers = require('clock.numbers')
local PADDING = ' '

local chars = {
  [1] = '█',
}

local config = (function()
  local block = string.rep(PADDING, 5)
  return {
    border = 'rounded',
    separator = {
      block,
      PADDING .. chars[1]:rep(2) .. PADDING:rep(2),
      block,
      PADDING .. chars[1]:rep(2) .. PADDING:rep(2),
      block,
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

---@param str string
---@return string[]
local split = function(str)
  return vim.split(str, '\n')
end

local str_to_time_parts = function(time)
  local hr, min, sec = unpack(vim.split(time, ':'))
  local h1, h2 = unpack(vim.split(hr, ''))
  local m1, m2 = unpack(vim.split(min, ''))
  local s1, s2 = unpack(vim.split(sec, ''))
  return h1, h2, m1, m2, s1, s2
end

---Converts a string into an array of said string `size` number of times
---@param str string
---@param size number
---@return string[]
local function expand(str, size)
  local res = {}
  for i = 1, size, 1 do
    res[#res + 1] = str
  end
  return res
end

--- Takes a time represented as HH:MM and returns a list of lines to render in the buffer
---@param time string
---@param width number
---@return string[]
local function get_lines(time, width)
  local sep = config.separator
  local inner_padding_width = 2

  local h1, h2, m1, m2, s1, s2 = str_to_time_parts(time)
  local hour1 = split(numbers[h1 + 1])
  local char_width = api.nvim_strwidth(hour1[1])
  local sep_width = api.nvim_strwidth(sep[1])
  local clock_width = (char_width * 6) + (sep_width * 2)
  local inner_padding = expand(PADDING:rep(inner_padding_width), char_width)
  -- 4 is for padding between time parts each of which has 2 characters
  local available_space = width - clock_width - (5 * inner_padding_width)
  local side_size = math.floor(available_space / 2)

  ---@type string[]
  local side_padding = expand(PADDING:rep(side_size), char_width)

  local h1_lines = join({
    before = side_padding,
    list = hour1,
    after = inner_padding,
  })

  local h2_lines = join({
    list = split(numbers[h2 + 1]),
    after = inner_padding,
  })

  local m1_lines = join({
    before = sep,
    list = split(numbers[m1 + 1]),
    after = inner_padding,
  })

  local m2_lines = join({
    list = split(numbers[m2 + 1]),
    after = inner_padding,
  })

  local s1_lines = join({
    before = sep,
    list = split(numbers[s1 + 1]),
    after = inner_padding,
  })

  local s2_lines = join({
    list = split(numbers[s2 + 1]),
    after = side_padding,
  })

  local result = {}
  for i, _ in ipairs(h1_lines) do
    table.insert(
      result,
      table.concat({
        h1_lines[i],
        h2_lines[i],
        m1_lines[i],
        m2_lines[i],
        s1_lines[i],
        s2_lines[i],
      })
    )
  end
  return result
end

--- Create a clock window
---@param time string
---@param conf table
---@return number window
---@return number buf
local draw_clock = function(time, conf)
  local width = conf.width or 60
  local buf = api.nvim_create_buf(false, true)
  local lines = get_lines(time, width)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = api.nvim_open_win(buf, false, {
    relative = 'editor',
    anchor = 'SE',
    row = vim.o.lines - tonumber(vim.o.cmdheight) - 1 - 1,
    col = vim.o.columns,
    border = conf.border,
    height = conf.height or #lines,
    width = width,
    style = 'minimal',
  })
  return win, buf
end

--- Set a new time in an existing clock buffer
---@param time string
---@param win number
---@param buf number
---@param timer userdata
local update_clock = function(time, win, buf, timer)
  if not api.nvim_win_is_valid(win) then
    return vim.notify_once('Window is invalid! cannot update the time', 'error', {
      title = 'Clock.nvim',
    })
  end
  if not timer then
    api.nvim_win_close(win, true)
    api.nvim_buf_delete(buf, { force = true })
  else
    ---@type table
    local win_config = api.nvim_win_get_config(win)
    local lines = get_lines(time, win_config.width)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

local timers = {}

---@param deadline number
---@param callback fun(userdata, number)
local function start_timer(deadline, callback)
  assert(callback, 'A callback must be passed to a timer')
  local timer = vim.loop.new_timer()
  timers[timer] = deadline
  timer:start(0, 1000, function()
    if timers[timer] <= os.time() then
      timer:stop()
      timer:close()
      timer = nil
    end
    vim.schedule(function()
      callback(timer)
    end)
  end)
end

local countdown = function(deadline, _)
  return os.date('%X', deadline - os.time())
end

---@param duration Duration
---@param direction number
---@return fun(userdata)
local function create_counter(duration, direction)
  vim.schedule(function()
    local minutes = duration.minutes or 0
    local hours = duration.hours or 0
    local seconds = (minutes * 60) + (hours * 60 * 60)
    local deadline = seconds + os.time()
    local start_time = '00:00:00'
    local win, buf = draw_clock(start_time, config)
    local timer = start_timer(deadline, function(timer)
      update_clock(countdown(deadline), win, buf, timer)
    end)
    return function()
      if timer then
        timer:stop()
        timer:close()
      end
    end
  end)
end

---@type Clock[]
local clocks = {}

local function next_id()
  return #clocks + 1
end

---@param clock Clock
---@return boolean exists
local function add_clock(clock)
  if not vim.tbl_contains(clocks, clock) then
    clocks[#clocks + 1] = clock
    return false
  end
  return true
end

local direction = { UP = 1, DOWN = 2 }

--- @class Clock
local Clock = {}
function Clock:new(o)
  o = o or {}
  self.id = next_id()
  self.__index = self
  return setmetatable(o, self)
end

---Countdown for the amount of time specified
---@param duration Duration
---@return Clock
function Clock:count_down(duration)
  local exists = add_clock(self)
  if not exists then
    self.cancel = create_counter(duration, direction.DOWN)
  end
  return self
end

M.Clock = Clock

function M.setup(c)
  config = vim.tbl_deep_extend('force', config, c)
end

return M
