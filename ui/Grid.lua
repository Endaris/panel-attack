local class = require("class")
local UiElement = require("ui.UIElement")
local tableUtils = require("tableUtils")
local GridElement = require("ui.GridElement")
local directsFocus = require("ui.FocusDirector")

local Grid = class(function(self, options)
  directsFocus(self)
  self.unitSize = options.unitSize
  self.gridHeight = options.gridHeight
  self.gridWidth = options.gridWidth
  self.width = self.gridWidth * self.unitSize
  self.height = self.gridHeight * self.unitSize
  self.grid = {}
  for row = 1, options.gridHeight do
    self.grid[row] = {}
    for col = 1, options.gridWidth do
      self.grid[row][col] = {}
    end
  end
end, UiElement)

-- width and height are sizes relative to the unitSize of the grid
-- id is a string identificator to indiate what kind of uiElement resides here
-- uiElement is the actual element on display that will perform user interaction when selected
function Grid:createElementAt(x, y, width, height, id, uiElement)
  local gridElement = GridElement({width = width * self.unitSize, height = height * self.unitSize, id = id, content = uiElement})
  self:addChild(gridElement)

  for row = y, y + height do
    for col = x, x + width do
      -- ensure the area is still free
      if tableUtils.length(self.grid[row][col]) > 0 then
        error("Error trying to create a grid element:\n" .. "There is already element " .. self.grid[row][col].id .. " at coordinate " .. row .. "|" .. col)
      else
        -- assign the gridElement to the respective areas to make sure they are blocked
        self.grid[row][col] = gridElement
      end
    end
  end

  gridElement.onSelect = function()
    if gridElement.content.isFocusable then
      self:setFocus(gridElement.content)
    else
      gridElement.content:onSelect()
    end
  end

end

function Grid.onSelect()

end

function Grid.onMove(x, y)

end

function Grid.onBack()

end

function Grid:draw()
  grectangle_color("line", self.x, self.y, self.width, self.height, 1, 1, 1, 1)
  if DEBUG_ENABLED then
    -- draw all units
    local left = self.x
    local right = self.x + self.width
    local top = self.y
    local bottom = self.y + self.height
    for i = 1, self.gridHeight - 1 do
      local y = top + self.unitSize * i
      gline_color(left, y, right, y, 1, 1, 1, 0.5)
    end
    for i = 1, self.gridWidth - 1 do
      local x = left + self.unitSize * i
      gline_color(x, top, x, bottom, 1, 1, 1, 0.5)
    end
  end
  for _, gridElement in ipairs(self.children) do
    if gridElement.isVisible then
      gridElement:draw()
    end
  end
end

return Grid