# clock.nvim

A fairly simple plugin that allows creating timers and clocks to count up and down.
My main motivation for creating this was so that I could keep track of how much time I spend in my dotfiles... 😅

<img width="1716" alt="image" src="https://user-images.githubusercontent.com/22454918/174431720-90e712bf-90ac-4d9e-ad0b-00d2222c29c1.png">

## Status

_Highly_ Unstable

## Planned features

- [ ] Pomodoro timer
- [ ] More clock styles (as the desire arises, not on demand)
- [ ] Clock colour effects e.g. as the deadline approaches etc.

## Installation

```lua
use {'akinsho/clock.nvim', config = function()
  require('clock').setup({
    border = 'rounded',
    style = 'dark_shadow' -- | 'default'
  })
end}
```

## Usage

```lua
local Clock = require('clock').Clock
local thirty_mins = Clock:new()
thirty_mins:count_up({duration = {minutes = 30}}) -- thirty_mins:count_down()
-- cancel early based on a condition
if my_condition then
  thirty_mins:cancel()
end

--- Thresholds will change the highlight of the clock if they are breached e.g.
thirty_mins:count_down({
  duration = {minutes = 30},
  threshold = {late = "00:15"}, -- at 15mins the clock will become red
})
```

### Commands

- `ClockCancelAll` - Does what it says on the tin 😄

## Feature requests / Issues

This plugin was designed for my usage/use cases, I don't intend to implement feature requests. I only plan on working on what I have stated already.
If it does not work for you I also do not intend to provide customer support so please try and solve any configuration issues yourself.
Please do not raise issues like `How do I do X?`.

I am always happy to accept contributions so if you have an idea you would like to contribute please raise a PR 🥇.
