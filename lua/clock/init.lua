--- Source of good ASCII numbers
--- @reference: https://texteditor.com/multiline-text-art/
--- Handling dates in Lua
--- @reference: https://www.lua.org/pil/22.1.html

local M = {}
local api = vim.api
local numbers = require('clock.numbers')

---@class Timer
---@field close fun()
---@field stop fun()
---@field start fun(number, number, function)

---@class ClockConfig
---@field style 'dark_shadow' | 'default'
---@field border string

---@class Duration
---@field hours number
---@field minutes number

---@class Direction
---@field UP 1
---@field DOWN 2

---@type Direction
local direction = { UP = 1, DOWN = 2 }

---@class Clock
---@field timer Timer?
local Clock = {}

local PADDING = ' '
local INNER_PADDING_WIDTH = 2

local chars = {
  [1] = '█',
}

--- Create the column of separator characters
---@param char_height number
---@return string[]
local function generate_separator(char_height)
  local SIDE_PADDING = #PADDING * 3 -- 3 columns of padding
  local sep_size = (api.nvim_strwidth(chars[1]) * 2) + SIDE_PADDING
  local block = string.rep(PADDING, sep_size)
  local separator = {
    block,
    PADDING .. chars[1]:rep(2) .. PADDING:rep(2),
    block,
    PADDING .. chars[1]:rep(2) .. PADDING:rep(2),
    block,
  }
  if #separator < char_height then
    for i = #separator, char_height, 1 do
      separator[i + 1] = block
    end
  end
  return separator
end

---@type ClockConfig
local config = {
  style = 'dark_shadow',
  border = 'rounded',
}

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
  for _ = 1, size, 1 do
    res[#res + 1] = str
  end
  return res
end

--- Calculate approximately how width the clock will be per style
---@return number clock width
---@return number character width
local function get_clock_width()
  local NUM_OF_CHARS = 6
  local NUM_OF_SEPARATORS = 2
  local NUM_OF_PADDING_COLUMNS = 5
  local nums = numbers[config.style]
  local first_char = split(nums[1])
  local sep = generate_separator(#first_char)
  local char_width = api.nvim_strwidth(first_char[1])
  local sep_width = api.nvim_strwidth(sep[1])
  local clock_width = (char_width * NUM_OF_CHARS)
    + (sep_width * NUM_OF_SEPARATORS)
    + (NUM_OF_PADDING_COLUMNS * INNER_PADDING_WIDTH)
  return clock_width, char_width
end

--- Takes a time represented as HH:MM and returns a list of lines to render in the buffer
---@param time string
---@param width number
---@return string[]
local function get_lines(time, width)
  local nums = numbers[config.style]

  local h1, h2, m1, m2, s1, s2 = str_to_time_parts(time)
  local hour1 = split(nums[h1 + 1])
  local clock_width, char_width = get_clock_width()
  local sep = generate_separator(#hour1)
  local inner_padding = expand(PADDING:rep(INNER_PADDING_WIDTH), char_width)
  local available_space = width - clock_width
  local side_size = math.floor(available_space / 2)

  ---@type string[]
  local side_padding = expand(PADDING:rep(side_size), char_width)

  local h1_lines = join({
    before = side_padding,
    list = hour1,
    after = inner_padding,
  })

  local h2_lines = join({
    list = split(nums[h2 + 1]),
    after = inner_padding,
  })

  local m1_lines = join({
    before = sep,
    list = split(nums[m1 + 1]),
    after = inner_padding,
  })

  local m2_lines = join({
    list = split(nums[m2 + 1]),
    after = inner_padding,
  })

  local s1_lines = join({
    before = sep,
    list = split(nums[s1 + 1]),
    after = inner_padding,
  })

  local s2_lines = join({
    list = split(nums[s2 + 1]),
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
  local width = get_clock_width() + 10
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

---@type Timer[]
local timers = {}

function M.cancel_all()
  for timer, callback in pairs(timers) do
    if timer then
      timer:stop()
      timer:close()
      callback()
    end
  end
end

---@param callback fun(userdata, number)
---@param stop_condition fun(timer): boolean
local function start_timer(callback, stop_condition)
  assert(callback, 'A callback must be passed to a timer')
  local timer = vim.loop.new_timer()
  timers[timer] = callback
  timer:start(0, 1000, function()
    if stop_condition(timer) then
      timer:stop()
      timer:close()
      timer = nil
    end
    vim.schedule(function()
      callback(timer)
    end)
  end)
end

--- Return the difference between the time when the timer ends and the current time
-- `!` means UTC and `%X` returns the time as `HH:MM`
-- @see: https://www.lua.org/pil/22.1.html
---@param end_time number time when the timer ends in seconds
---@return number difference between now and the end time
local function countdown(end_time)
  return os.date('!%X', end_time - os.time())
end

local function countup(end_time, duration)
  return os.date('!%X', (os.time() + duration) - end_time)
end

---@param duration Duration
---@param dir Direction
---@return Timer
local function create_counter(duration, dir)
  vim.schedule(function()
    local is_counting_up = dir == direction.UP
    local minutes = duration.minutes or 0
    local hours = duration.hours or 0
    local seconds = (minutes * 60) + (hours * 60 * 60)
    local start_time = '00:00:00'
    local win, buf = draw_clock(start_time, config)
    local deadline = seconds + os.time()
    local getter = is_counting_up and countup or countdown
    local condition = function(_)
      if is_counting_up then
        return deadline <= os.time()
      end
      return deadline <= os.time()
    end
    local updater = function(t)
      update_clock(getter(deadline, seconds), win, buf, t)
    end
    return start_timer(updater, condition)
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
    self.timer = create_counter(duration, direction.DOWN)
  end
  return self
end

---Count up for the amount of time specified
---@param duration Duration
---@return Clock
function Clock:count_up(duration)
  local exists = add_clock(self)
  if not exists then
    self.timer = create_counter(duration, direction.UP)
  end
  return self
end

function Clock:cancel()
  if self.timer ~= nil then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
end

M.Clock = Clock

function M.setup(c)
  config = vim.tbl_deep_extend('force', config, c)
end

api.nvim_create_user_command('ClockCancelAll', function()
  M.cancel_all()
end, { desc = 'Cancel all running clocks', force = true })

return M
