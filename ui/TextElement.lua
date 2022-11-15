-- updates the label with a new label
-- also translates the label if needed
-- if no label is passed in it will translate the existing label
local function updateLabel(self, label)
  if label then
    self.label = label
  end

  if self.label and (self.translate or label) then
    self.text = love.graphics.newText(love.graphics.getFont(), self.translate and loc(self.label, unpack(self.extraLabels)) or self.label)
  end
  
  for _, uiElement in ipairs(self.children) do
    uiElement:updateLabel()
  end
end

local function implementsText(class, options)
  -- label to be displayed on ui element
  -- Only used for Buttons & Labels
  class.label = class.label
  -- list of parameters for translating the label
  if class.label then
    class.extraLabels = options.extra_labels or {}
  end

  -- whether we should translate the label or not
  class.translate = options.translate or options.translate == nil and true
  
  -- private members
  if class.label then
    class.text = love.graphics.newText(love.graphics.getFont(), class.translate and loc(class.label, unpack(class.extraLabels)) or class.label)
  end

  class.updateLabel = updateLabel

  -- text field is set in base class (UIElement)
  local textWidth, textHeight = class.text:getDimensions()
  -- stretch to fit text
  class.width = math.max(textWidth + 6, class.width)
  class.height = math.max(textHeight + 6, class.height)
end

return implementsText