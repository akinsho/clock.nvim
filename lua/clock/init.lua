--- Source of good ASCII numbers
--- @reference: https://texteditor.com/multiline-text-art/
--- Handling dates in Lua
--- @reference: https://www.lua.org/pil/22.1.html

local M = {}
local api = vim.api
local notify = vim.notify
local once = vim.notify_once
local numbers = require('clock.numbers')

---@class Coordinates
---@field start_row number
---@field end_row number
---@field start_col number[]
---@field end_col number[]

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

---@class CountOpts
---@field duration Duration
---@field threshold Threshold

---@class Direction
---@field UP 1
---@field DOWN 2

---@type Direction
local direction = { UP = 1, DOWN = 2 }

---@alias Threshold table<string, string>

---@class Clock
---@field timer Timer?
---@field threshold Threshold
local Clock = {}

local PADDING = ' '
local INNER_PADDING_WIDTH = 2
local NAMESPACE = api.nvim_create_namespace('clock-space')
local NOTIFICATION_TITLE = ' Clock.nvim'

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
  local separator_dot = PADDING .. chars[1]:rep(2) .. PADDING:rep(2)
  local separator = { block, separator_dot, block, separator_dot, block }
  if #separator < char_height then
    for i = #separator + 1, char_height, 1 do
      separator[i] = block
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
local function join(opts)
  local after, list, before = opts.after or {}, opts.list or {}, opts.before or {}
  local result = {}
  for index, item in ipairs(list) do
    local before_item = before[index] or ''
    local after_item = after[index] or ''
    local line = before_item .. item .. after_item
    result[#result + 1] = line
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
---@generic T
---@param arg T
---@param size number
---@return string[]
local function expand(arg, size)
  local res = {}
  for _ = 1, size, 1 do
    res[#res + 1] = arg
  end
  return res
end

---@class CharacterAttributes
---@field height number
---@field width number
---@field byte_width number

---@param char string[]
---@return CharacterAttributes
local function get_dimensions(char)
  local char_width, byte_width = 0, 0
  for _, line in ipairs(char) do
    local current = api.nvim_strwidth(line)
    local bytes = #line
    if current > char_width or bytes > byte_width then
      char_width = current
      byte_width = bytes
    end
  end
  return { width = char_width, byte_width = byte_width, height = #char }
end

---@return CharacterAttributes
local function get_char_dimensions()
  local nums = numbers[config.style]
  local first_char = split(nums[1])
  return get_dimensions(first_char)
end

local function get_separator_dimensions(height)
  return get_dimensions(generate_separator(height))
end

---Calculate approximately how width the clock will be per style
---@param char_attrs CharacterAttributes
---@return number clock width
local function get_clock_width(char_attrs, sep_width)
  local NUM_OF_CHARS = 6
  local NUM_OF_SEPARATORS = 2
  local NUM_OF_PADDING_COLUMNS = 5
  local clock_width = (char_attrs.width * NUM_OF_CHARS)
    + (sep_width * NUM_OF_SEPARATORS)
    + (NUM_OF_PADDING_COLUMNS * INNER_PADDING_WIDTH)
  return clock_width, sep_width
end

---@param offset number[]
---@param lines string[]
---@return number[]
local function get_col_widths(offset, lines)
  local res = {}
  for i, line in ipairs(lines) do
    res[#res + 1] = offset[i] + #line
  end
  return res
end

--- Takes a time represented as HH:MM and returns a list of lines to render in the buffer
---@param time string
---@param width number
---@return string[]
local function get_lines(time, width)
  local nums = numbers[config.style]

  local h1, h2, m1, m2, s1, s2 = str_to_time_parts(time)
  local char_attrs = get_char_dimensions()
  local sep_attrs = get_separator_dimensions(char_attrs.height)
  local clock_width = get_clock_width(char_attrs, sep_attrs.width)
  local sep = generate_separator(char_attrs.height)
  local inner_padding_char = PADDING:rep(INNER_PADDING_WIDTH)
  local inner_padding = expand(inner_padding_char, char_attrs.height)
  local available_space = width - clock_width
  local side_size = math.floor(available_space / 2)

  local side_padding_char = PADDING:rep(side_size)
  ---@type string[]
  local side_padding = expand(side_padding_char, char_attrs.height)

  local start_row = 1
  local end_row = char_attrs.height

  local h1_lines = join({
    before = side_padding,
    list = split(nums[h1 + 1]),
    after = inner_padding,
  })

  local start_col = expand(0, char_attrs.height)
  local h1_coordinates = {
    start_row = start_row,
    end_row = end_row,
    start_col = get_col_widths(start_col, side_padding),
    end_col = get_col_widths(start_col, h1_lines),
  }

  local h2_lines = join({
    list = split(nums[h2 + 1]),
    after = inner_padding,
  })

  local h2_coordinates = {
    start_row = start_row,
    end_row = end_row,
    start_col = h1_coordinates.end_col,
    end_col = get_col_widths(h1_coordinates.end_col, h2_lines),
  }

  local sep_lines = join({ list = sep })
  local sep1_offset = get_col_widths(h2_coordinates.end_col, sep_lines)

  local m1_lines = join({
    list = split(nums[m1 + 1]),
    after = inner_padding,
  })

  local m1_coordinates = {
    start_row = start_row,
    end_row = end_row,
    start_col = sep1_offset,
    end_col = get_col_widths(sep1_offset, m1_lines),
  }

  local m2_lines = join({
    list = split(nums[m2 + 1]),
    after = inner_padding,
  })

  local m2_coordinates = {
    start_row = start_row,
    end_row = end_row,
    start_col = m1_coordinates.end_col,
    end_col = get_col_widths(m1_coordinates.end_col, m2_lines),
  }

  local s1_lines = join({
    list = split(nums[s1 + 1]),
    after = inner_padding,
  })

  local sep2_offset = get_col_widths(m2_coordinates.end_col, sep_lines)
  local s1_coordinates = {
    start_row = start_row,
    end_row = end_row,
    start_col = sep2_offset,
    end_col = get_col_widths(sep2_offset, s1_lines),
  }

  local s2_lines = join({
    list = split(nums[s2 + 1]),
    after = side_padding,
  })

  local s2_coordinates = {
    start_row = start_row,
    end_row = end_row,
    start_col = s1_coordinates.end_col,
    end_col = get_col_widths(s1_coordinates.end_col, s2_lines),
  }

  local result = {}
  for i, _ in ipairs(h1_lines) do
    table.insert(
      result,
      table.concat({
        h1_lines[i],
        h2_lines[i],
        sep_lines[i],
        m1_lines[i],
        m2_lines[i],
        sep_lines[i],
        s1_lines[i],
        s2_lines[i],
      })
    )
  end

  local coordinates = {
    h1 = h1_coordinates,
    h2 = h2_coordinates,
    m1 = m1_coordinates,
    m2 = m2_coordinates,
    s1 = s1_coordinates,
    s2 = s2_coordinates,
  }

  return result, coordinates
end

local section_hl = {
  default = {
    h1 = 'String',
    h2 = 'String',
    m1 = 'String',
    m2 = 'String',
    s1 = 'String',
    s2 = 'String',
  },
  late = {
    h1 = 'ErrorMsg',
    h2 = 'ErrorMsg',
    m1 = 'ErrorMsg',
    m2 = 'ErrorMsg',
    s1 = 'ErrorMsg',
    s2 = 'ErrorMsg',
  },
}

---@param buf number
---@param coordinates Coordinates
---@param threshold string
local function highlight_characters(buf, coordinates, threshold)
  for key, coords in pairs(coordinates) do
    local hl = section_hl[threshold][key]
    for index = coords.start_row, coords.end_row, 1 do
      api.nvim_buf_add_highlight(
        buf,
        NAMESPACE,
        hl,
        index - 1,
        coords.start_col[index],
        coords.end_col[index]
      )
    end
  end
end

---@param time string
---@return number
local function str_to_timestamp(time)
  local hour, minute, second = time:match('(%d+):(%d+):(%d+)')
  local today = os.date('!*t')
  local timestamp = os.time({
    year = today.year,
    month = today.month,
    day = today.day,
    hour = tonumber(hour),
    min = tonumber(minute),
    sec = tonumber(second),
  })
  return timestamp
end

-- Get the current threshold which is one a users threshold which are times which convey a meaning
-- for them e.g. the threshold could be the point where something is late in a timer e.g. 5mins to
-- the end. Each threshold should correspond to a highlight which is then used to change the clocks
-- appearance
---@param time string
---@param user_thresholds Threshold
local function get_curr_threshold(time, user_thresholds)
  local threshold = 'default'
  local curr_timestamp = str_to_timestamp(time)
  if not threshold then
    return threshold
  end
  for name, str in pairs(user_thresholds) do
    local t = str_to_timestamp(str)
    local next_threshold = next(user_thresholds, name)
    local next_time = next_threshold and str_to_timestamp(next_threshold) or nil
    if curr_timestamp >= t and (not next_time or curr_timestamp <= next_time) then
      threshold = name
      break
    end
  end
  return threshold
end

--- Create a clock window
---@param time string
---@param user_thresholds Threshold
---@param conf table
---@return number window
---@return number buf
local function draw_clock(time, user_thresholds, conf)
  local threshold = get_curr_threshold(time, user_thresholds)
  local char_attrs = get_char_dimensions()
  local sep_attrs = get_separator_dimensions(char_attrs.height)
  local width = get_clock_width(char_attrs, sep_attrs.width) + 10
  local buf = api.nvim_create_buf(false, true)
  local lines, coordinates = get_lines(time, width)
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
  highlight_characters(buf, coordinates, threshold)
  return win, buf
end

--- Set a new time in an existing clock buffer
---@param time string
---@param win number
---@param buf number
---@param timer Timer
---@param threshold Threshold
local function update_clock(win, buf, time, timer, threshold)
  if not api.nvim_win_is_valid(win) then
    return once('Window is invalid! cannot update the time', 'error', {
      title = NOTIFICATION_TITLE,
    })
  end
  if not timer then
    api.nvim_win_close(win, true)
    api.nvim_buf_delete(buf, { force = true })
  else
    ---@type table
    local win_config = api.nvim_win_get_config(win)
    local lines, coordinates = get_lines(time, win_config.width)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    highlight_characters(buf, coordinates, get_curr_threshold(time, threshold))
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

---@param opts CountOpts
---@param dir Direction
---@param _ Clock
---@return Timer
local function create_counter(opts, dir, _)
  vim.schedule(function()
    local is_counting_up = dir == direction.UP
    local duration = opts.duration
    if not opts.duration then
      return notify('A clock cannot be started without a duration', 'error', {
        title = NOTIFICATION_TITLE,
      })
    end
    local minutes = duration.minutes or 0
    local hours = duration.hours or 0
    local seconds = (minutes * 60) + (hours * 60 * 60)
    local start_time = '00:00:00'
    local win, buf = draw_clock(start_time, opts.threshold, config)
    local deadline = seconds + os.time()
    local getter = is_counting_up and countup or countdown
    local condition = function(_)
      if is_counting_up then
        return deadline <= os.time()
      end
      return deadline <= os.time()
    end
    local updater = function(t)
      update_clock(win, buf, getter(deadline, seconds), t, opts.threshold)
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
---@param opts CountOpts
---@return Clock
function Clock:count_down(opts)
  local exists = add_clock(self)
  if not exists then
    self.timer = create_counter(opts, direction.DOWN, self)
  end
  return self
end

---Count up for the amount of time specified
---@param opts CountOpts
---@return Clock
function Clock:count_up(opts)
  local exists = add_clock(self)
  if not exists then
    self.timer = create_counter(opts, direction.UP, self)
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
