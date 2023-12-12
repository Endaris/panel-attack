local utf8 = require("utf8")
local util = require("util")

local class = require("class")
local UIElement = require("ui.UIElement")
local inputFieldManager = require("ui.inputFieldManager")
local touchable = require("ui.Touchable")

--@module InputField
local InputField = class(
  function(self, options)
    self.placeholderText = love.graphics.newText(love.graphics.getFont(), options.placeholder) or love.graphics.newText(love.graphics.getFont(), "Input Field")
    self.value = options.value or ""
    self.charLimit = options.charLimit or 16
    self.filterAlphanumeric = options.filterAlphanumeric or (options.filterAlphanumeric == nil and true)

    self.backgroundColor = options.backgroundColor or {.3, .3, .3, .7}
    self.outlineColor = options.outlineColor or {.5, .5, .5, .7}

    -- text alignments settings
    -- must be one of the following values:
    -- left, right, center
    self.hAlign = options.hAlign or 'left'
    self.vAlign = options.vAlign or 'center'
    
    self.text = love.graphics.newText(love.graphics.getFont(), self.value)
    -- stretch to fit text
    local textWidth, textHeight = self.text:getDimensions()
    self.width = math.max(textWidth + 6, self.width)
    self.height = math.max(textHeight + 6, self.height)

    self.hasFocus = false
    self.offset = 0
    self.textCursorPos = nil

    inputFieldManager.inputFields[self.id] = self.isVisible and self or nil
    touchable(self)
    self.TYPE = "InputField"
  end,
  UIElement
)

function InputField:onTouch(x, y)
  self:setFocus(x, y)
end

function InputField:onDrag(x, y)
  if self:inBounds(x, y) then
    self:setFocus(x, y)
  end
end

function InputField:onRelease(x, y)
  if self:inBounds(x, y) then
    self:setFocus(x, y)
  end
end

local textOffset = 4
local textCursor = love.graphics.newText(love.graphics.getFont(), "|")

function InputField:onVisibilityChanged()
  if self.isVisible then
    inputFieldManager.inputFields[self.id] = self
  else
    inputFieldManager.inputFields[self.id] = nil
  end
end

function InputField:getCursorPos()
  if self.offset == 0 then
    return self.x + textOffset
  end

  local byteoffset = utf8.offset(self.value, self.offset)
  local text = string.sub(self.value, 1, byteoffset)
  return self.x + textOffset + love.graphics.newText(love.graphics.getFont(), text):getWidth()
end

function InputField:unfocus()
  inputFieldManager.selectedInputField = nil
  love.keyboard.setTextInput(false)
  self.hasFocus = false
end

function InputField:setFocus(x, y)
  inputFieldManager.selectedInputField = self
  love.keyboard.setTextInput(true)
  self.hasFocus = true
  self.offset = 0
  local prevX = self:getCursorPos()
  local currX = self:getCursorPos()
  while self.offset < utf8.len(self.value) and x > currX do
    prevX = currX
    self.offset = self.offset + 1
    currX = self:getCursorPos()
  end
  if math.abs(x - prevX) < math.abs(x - currX) then
    self.offset = self.offset - 1
  end
end

function InputField:onBackspace()
  if self.offset == 0 then
    return 
  end

  -- get the byte offset to the last UTF-8 character in the string.
  local strByteLength = utf8.offset(self.value, -1) or 0
  local byteoffset = utf8.offset(self.value, self.offset - 1) or 0
  local byteoffset2 = utf8.offset(self.value, self.offset) or 0

  if self.offset == 1 then
    self.value = string.sub(self.value, byteoffset2 + 1, strByteLength)
  elseif self.offset == utf8.len(self.value) then
    self.value = string.sub(self.value, 1, byteoffset)
  else
    self.value = string.sub(self.value, 1, byteoffset) .. string.sub(self.value, byteoffset2 + 1, strByteLength)
  end
  self.text = love.graphics.newText(love.graphics.getFont(), self.value)
  self.offset = self.offset - 1
end

function InputField:onMoveCursor(dir)
  self.offset = util.bound(0, self.offset + dir, utf8.len(self.value))
end

function InputField:textInput(t)
  if self.filterAlphanumeric and string.find(t, "[^%w]+") then
    return
  end
  if utf8.len(self.value) < self.charLimit then
    local strByteLength = utf8.offset(self.value, -1) or 0
    local byteoffset = utf8.offset(self.value, self.offset) or 0
    if self.offset == 0 then
      self.value = t .. string.sub(self.value, 1, strByteLength)
    elseif self.offset == utf8.len(self.value) then
      self.value = string.sub(self.value, 1, strByteLength) .. t
    else
      self.value = string.sub(self.value, 1, byteoffset) .. t .. string.sub(self.value, byteoffset + 1, strByteLength)
    end
    self.text = love.graphics.newText(love.graphics.getFont(), self.value)
    self.offset = self.offset + 1
  end
end

function InputField:drawSelf()
  love.graphics.setColor(self.outlineColor)
  love.graphics.rectangle("line", self.x, self.y, self.width, self.height)
  love.graphics.setColor(self.backgroundColor)
  love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
  
  local text = self.value ~= "" and self.text or self.placeholderText
  local textColor = self.value ~= "" and {1, 1, 1, 1} or {.5, .5, .5, 1}
  
  love.graphics.setColor(textColor)
  love.graphics.draw(text, self.x + textOffset, self.y + 0, 0, 1, 1)
  
  if self.hasFocus then
    local cursorFlashPeriod = .5
    if (math.floor(love.timer.getTime() / cursorFlashPeriod)) % 2 == 0 then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(textCursor, self:getCursorPos(), self.y, 0, 1, 1)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return InputField