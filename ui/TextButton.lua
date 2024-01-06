local class = require("class")
local Button = require("ui.Button")

local TEXT_WIDTH_PADDING = 15
local TEXT_HEIGHT_PADDING = 6

-- A TextButton is a button that sets itself apart from Button by automatically scaling its own size to fit the text inside
-- This is different from the regular button that scales its content to fit inside itself
local TextButton = class(function(self, options)
  self.label = options.label
  self.label.hAlign = "center"
  self.label.vAlign = "center"
  self:addChild(self.label)

  -- stretch to fit text
  self.width = math.max(self.label.width + TEXT_WIDTH_PADDING, self.width)
  self.height = math.max(self.label.height + TEXT_HEIGHT_PADDING, self.height)

  self.TYPE = "Button"
end, Button)

return TextButton
