__TESTING = false

require 'global'
local observer = require 'observer'
local object = require 'object'
local timer = require 'timer'
local input = require 'input'
local color = require 'color'
local graphics = require 'graphics'
local rectangle = require 'rectangle'

random = love.math.random

util = {
  lerp = function(y1, y2, x)
    return y1 + (x * (y2 - y1))
  end,
  sign = function(x)
    if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end
  end,
}

image_component = {
  load_image = function(self, name)
    self._image = love.graphics.newImage(name)
    self._image:setFilter("nearest", "nearest")
  end,

  draw_image = function(self, x, y)
    love.graphics.draw(self._image, x, y)
  end,

  image_width = function(self) return self._image:getWidth() end,
  image_height = function(self) return self._image:getHeight() end,
}

slide_component = {
  speed = 2.5,

  slide_init = function(self)
    self:on("update", self:bind(self.slide_update))
    self.slide_info = {}
  end,

  slide_to = function(self, x, y, speed)
    print ("slide to", x, y)
    self.slide_info.active = true
    self.slide_info.speed = speed or self.speed
    self.slide_info.to_x = x
    self.slide_info.to_y = y
    local x, y = self:tile_position()
    self.slide_info.from_x = x
    self.slide_info.from_y = y
    self.slide_info.frame = 0
  end,

  slide_update = function(self, dt)
    if self.slide_info.active then
      local info = self.slide_info
      info.frame = math.min(1, info.frame + (info.speed * dt))
      local x, y
      x = util.lerp(info.from_x, info.to_x, info.frame)
      y = util.lerp(info.from_y, info.to_y, info.frame)
      self:tile_position(x, y)
      if info.frame == 1 then
        info.active = false
      end
    end
  end,

  slide_active = function(self)
    return self.slide_info.active
  end,

  slide_target = function(self)
    if self.slide_info.active then
      return self.slide_info.to_x, self.slide_info.to_y
    else
      return self:tile_position()
    end
  end,
}

tile = object(slide_component, image_component, {
  tile_value = 2,
  tile_merged_with = nil,
  tile_width = 32,
  tile_height = 32,

  _init = function(self)
    self.rect = rectangle {
      w = tile_width,
      h = tile_height,
    }
    self:load_image("tile.png")
    self:slide_init()
    self:on("draw", self:bind(self.tile_draw))
  end,

  tile_position = function(self, x, y)
    if x == nil then return self.rect:left_top() end
    self.rect:left_top(x, y)
  end,

  tile_draw = function(self, offset_x, offset_y)
    local x, y, w, h = self.rect:rectangle()
    local text = tostring(self.tile_value)
    local centering = text:len() * 4
    graphics:set_color(color.PUREWHITE)
    self:draw_image(offset_x + x, offset_y + y)
    graphics:set_color(color.PUREBLACK)
    graphics:write(offset_x + x + 17 - centering, offset_y + y+12, text)
  end,
})


array2d = {
  create = function(class, w, h)
    local self = setmetatable({}, class)
    self.w = w
    self.h = h
    return self
  end,

  __index = {
    get = function(self, x, y)
      local pos = 1 + (y-1)*self.w + (x-1)
      return self[pos]
    end,

    set = function(self, x, y, v)
      local pos = 1 + (y-1)*self.w + (x-1)
      self[pos] = v
    end,

    clone = function(self)
      local copy = setmetatable({}, getmetatable(self))
      for k, v in pairs(self) do copy[k] = v end
      return copy
    end
  },
}

grid_funcs = {
  merge = function(grid, sx, sy, ex, ey, dx, dy)
    local x_step, y_step = util.sign(ex - sx), util.sign(ey - sy)
    for y = sy, ey, y_step do
      for x = sx, ex, x_step do
        local tile = grid:get(x, y)
        if tile then
          local other = grid:get(x+dx, y+dy)
          if other and (tile.tile_value == other.tile_value) then
            grid:set(x, y, nil)
            tile.tile_merged_with = other
          end
        end
      end
    end
  end,

  compress = function(grid, sx, sy, ex, ey, dx, dy, repetitions)
    local x_step, y_step = util.sign(ex - sx), util.sign(ey - sy)
    for r = 1, repetitions do
      for y = sy, ey, y_step do
        for x = sx, ex, x_step do
          local tile = grid:get(x, y)
          if tile then
            local other = grid:get(x+dx, y+dy)
            if not other then
              grid:set(x+dx, y+dy, tile)
              grid:set(x, y, nil)
            end
          end
        end
      end
    end
  end,

  move = function(grid, direction)
    local newgrid = grid:clone()
    local sx, sy = 1, 1
    local ex, ey = newgrid.w, newgrid.h
    local dx, dy = 0, 0
    local reps = newgrid.h-2+1

    if direction == "up" then
      sy, dy = 2, -1
    elseif direction == "down" then
      sy, ey, dy = ey - 1, sy, 1
    elseif direction == "left" then
      sx, dx = 2, -1
    elseif direction == "right" then
      sx, ex, dx = ex - 1, sx, 1
    end

    grid_funcs.compress(newgrid, sx, sy, ex, ey, dx, dy, reps)
    grid_funcs.merge(newgrid, sx, sy, ex, ey, dx, dy)
    grid_funcs.compress(newgrid, sx, sy, ex, ey, dx, dy, reps)
    return newgrid
  end,
}

game_controls = {
  controls_init = function(self)
    self:on("update", self:bind(self.game_update))
  end,

  game_update = function(self, dt)
    if self.active_mode == "input" then
      if input.tap.up then self:move("up") end
      if input.tap.down then self:move("down") end
      if input.tap.left then self:move("left") end
      if input.tap.right then self:move("right") end
    end
  end,
}

grid_component = {

  grid_rows = 4,
  grid_colums = 4,

  grid_init = function(self)
    self.tile_grid = array2d:create(self.grid_colums, self.grid_rows)
    self.tile_set = {}
    self.active_mode = "input"
    self:on("draw", self:bind(self.grid_draw))
    self:on("update", self:bind(self.grid_update))
  end,

  add_tile = function(self, tile, x, y)
    self.tile_set[tile] = true
  end,

  randomly_add_tile = function(self, tile)
    local c, tx, ty = 1
    for y = 1, self.grid_rows do
      for x = 1, self.grid_colums do
        if self.tile_grid:get(x, y) == nil then
          if (c == 1) or (random(1, c) == 1) then
            tx, ty = x, y
          end
          c = c + 1
        end
      end
    end
    if c == 1 then
      return "gameover"
    end

    tile:tile_position((tx-1)*tile.tile_width, (ty-1)*tile.tile_height)
    self.tile_set[tile] = true
    self.tile_grid:set(tx, ty, tile)
    return "play"
  end,

  grid_update = function(self, dt)
    for tile, _ in pairs(self.tile_set) do
      tile:send("update", dt)
    end

    if self.active_mode == "slide" then
      local should_merge = true
      for tile, _ in pairs(self.tile_set) do
        if tile:slide_active() then
          should_merge = false
          break
        else
          if tile.tile_merged_with then
            self.tile_set[tile] = nil
            tile.tile_merged_with.tile_value = tile.tile_merged_with.tile_value + tile.tile_value
          end
        end
      end
      if should_merge then
        self.active_mode = "input"
      end
    end
  end,

  grid_draw = function(self, offset_x, offset_y)

    local grid_offset_x = 56 + offset_x
    local grid_offset_y = 16 + offset_y

    graphics:set_color(color.GRAY)
    for y = 0, 4 do
      graphics:draw_rect(grid_offset_x, grid_offset_y + (tile.tile_height * y), tile.tile_width * 4, 1)
    end
    for x = 0, 4 do
      graphics:draw_rect(grid_offset_x + (tile.tile_width * x), grid_offset_y, 1, tile.tile_height * 4)
    end

    for tile, _ in pairs(self.tile_set) do
      tile:send("draw", grid_offset_x, grid_offset_y)
    end
  end,

  move = function(self, direction)
    if self.active_mode ~= "input" then
      print "not in active mode"
      return
    end

    local newgrid = grid_funcs.move(self.tile_grid, direction)

    for y = 1, newgrid.h do
      for x = 1, newgrid.w do
        local tile = newgrid:get(x, y)
        if tile then
          local x, y = (x-1)*tile.tile_width, (y-1)*tile.tile_height
          tile:slide_to(x, y)
        end
      end
    end

    for tile, _ in pairs(self.tile_set) do
      if tile.tile_merged_with then
        local x, y = tile.tile_merged_with:slide_target()
        tile:slide_to(x, y)
      end
    end

    self.active_mode = "slide"
    self.tile_grid = newgrid
  end,
}

game_grid = object(grid_component, game_controls, {
  _init = function(self)
    self:controls_init()
    self:grid_init()
  end
})

game_mode = object({

  _init = function(self)
    self.grid = game_grid()
    self.mode = nil
    self:on("draw", self:bind(self.game_draw))
    self:on("update", self:bind(self.game_update))
  end,

  game_draw = function(self, offset_x, offset_y)
    self.grid:send("draw", offset_x, offset_y)
  end,

  game_update = function(self, dt)
    if self.grid.active_mode ~= self.mode then
      self:change_state(self.mode, self.grid.active_mode)
    end

    self.grid:send("update", dt)
  end,

  change_state = function(self, from, to)
    print("mode", from, to)
    if to == "input" then
      local continue = self.grid:randomly_add_tile(tile({
        tile_value = random() < 0.9 and 2 or 4,
      }))

      if continue == "gameover" then
        self:send("gameover")
      end
    end
    self.mode = to
  end,
})

title_mode = object({
  _init = function(self)
    self:on("draw", self:bind(self.title_draw))
    self:on("update", self:bind(self.title_update))
    self.clock = 0
  end,
  title_update = function(self, dt)
    self.clock = self.clock + dt
    if input.tap.menu_enter then self:send("start") end
  end,
  title_draw = function(self)
    if (self.clock - math.floor(self.clock)) < 0.75 then
      graphics:set_color(color.PUREWHITE)
      graphics:write("center", "center", "PRESS ENTER TO START")
    end
  end
})


main = object {
  load = function(self)
    graphics:init()
    input:reset()
    self:restart()
  end,

  update = function(self, dt)
    if dt > 0.2 then dt = 0.2 end

    input:update(dt)

    if input.tap.screenshot then graphics:save_screenshot() end
    if input.tap.changescale then graphics:next_scale() end
    if input.tap.debug_terminate then love.event.quit() end
    if input.tap.debug_reset then self:restart() end
    if input.tap.fullscreen then graphics:toggle_fullscreen() end

    self.mode:send("update", dt)

    timer:update_timers(dt)
  end,

  draw = function(self)
    graphics:start()
    self.mode:send("draw", 0, 0)
    graphics:stop()
  end,

  resize = function(self, w, h)
    graphics:on_resize(w, h)
  end,

  restart = function(self)
    self.mode = title_mode()
    self.mode:on("start", self:bind(self.start))
  end,

  start = function(self)
    self.mode = game_mode()
    self.mode:on("gameover", self:bind(self.restart))
  end,
}


-- Fill out love event handlers with Main object calls
for _, callback in ipairs({ "load", "update", "draw", "resize" }) do
  love[callback] = function(...)
    RESET_DEBUG_HOOK()
    main[callback](main, ...)
  end
end

-- All input controls go to the input singleton
for _, callback in ipairs {
  "keypressed", "keyreleased", "textinput",
  "gamepadpressed", "gamepadreleased", "gamepadaxis"
} do
  love[callback] = function(...)
    input[callback](input, ...)
  end
end

