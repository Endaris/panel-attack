local class = require("class")
local UIElement = require("ui.UIElement")
local util = require("util")
local GraphicsUtil = require("graphics_util")

local handleRadius = 7.5

--@module Slider
local Slider = class(
  function(self, options)
    self.min = options.min or 1
    self.max = options.max or 99
    self.value = options.value and util.bound(self.min, options.value, self.max) or math.floor((self.max - self.min) / 2)
    -- pixels per value change
    self.tickLength = options.tickLength or 1
    self.onValueChange = options.onValueChange or function() end
    
    self.minText = love.graphics.newText(love.graphics.getFont(), self.min)
    self.maxText = love.graphics.newText(love.graphics.getFont(), self.max)
    self.valueText = love.graphics.newText(love.graphics.getFont(), self.value)

    self.width = self.tickLength * (self.max - self.min + 1) + 2
    self.height = handleRadius * 2 + 12 -- magic

    self.TYPE = "Slider"
  end,
  UIElement
)

local yOffset = 15
local textOffset = 0
local sliderBarThickness = 5

function Slider:onTouch(x, y)
  self:setValueFromPos(x)
end

function Slider:onDrag(x, y)
  self:setValueFromPos(x)
end

function Slider:onRelease(x, y)
  self:setValueFromPos(x)
end

function Slider:receiveInputs(input)
  if input:shouldRespondToMenuLeft() then
    self:setValue(self.value - 1)
  elseif input:shouldRespondToMenuRight() then
    self:setValue(self.value + 1)
  end
end

function Slider:setValueFromPos(x)
  local screenX, screenY = self:getScreenPos()
  self:setValue(math.floor((x - screenX) / self.tickLength) + self.min)
end

function Slider:setValue(value)
  if value ~= self.value then
    self.value = util.bound(self.min, value, self.max)
    self.valueText:set(self.value)
    self:onValueChange()
  end
end

local SLIDER_CIRCLE_COLOR = {0.5, 0.5, 1, 0.8}
function Slider:drawSelf()
  local light_gray = .5
  local alpha = .7
  GraphicsUtil.setColor(light_gray, light_gray, light_gray, alpha)
  GraphicsUtil.drawRectangle("fill", self.x, self.y + yOffset, (self.max - self.min + 1) * self.tickLength, sliderBarThickness)

  GraphicsUtil.setColor(unpack(SLIDER_CIRCLE_COLOR))
  love.graphics.circle("fill", self.x + (self.value - self.min + .5) * self.tickLength, self.y + yOffset + sliderBarThickness / 2, handleRadius, 32)
  GraphicsUtil.setColor(1, 1, 1, 1)
  
  local textWidth, textHeight = self.minText:getDimensions()
  GraphicsUtil.draw(self.minText, self.x - textWidth * .3, self.y + textOffset, 0, 1, 1, 0, 0)
  
  textWidth, textHeight = self.maxText:getDimensions()
  GraphicsUtil.draw(self.maxText, self.x + (self.max - self.min + 1) * self.tickLength - textWidth, self.y + textOffset, 0, 1, 1, 0, 0)
  
  textWidth, textHeight = self.valueText:getDimensions()
  GraphicsUtil.draw(self.valueText, self.x + ((self.max - self.min + 1) / 2.0) * self.tickLength - textWidth / 2, self.y + textOffset, 0, 1, 1, 0, 0)
end

return Slider