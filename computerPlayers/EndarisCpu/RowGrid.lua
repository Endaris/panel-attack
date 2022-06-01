require("computerPlayers.EndarisCpu.StackExtensions")

RowGrid = class(function(self, gridRows)
    self.gridRows = gridRows
    self.columnCount = 6
end)

function RowGrid.getGridRows(panels)
    local rowGridRows = {}
    StackExtensions.printAsAprilStackByPanels(panels)
    for rowIndex = 1, #panels do
        rowGridRows[rowIndex] = RowGridRow.FromPanels(rowIndex, panels[rowIndex])
    end

    return rowGridRows
end

function RowGrid.FromStack(stack)
    return RowGrid.FromPanels(stack.panels)
end

function RowGrid.FromPanels(panels)
    return RowGrid(RowGrid.getGridRows(panels))
end

function RowGrid.FromConnectedPanelSection(connectedPanelSection)
    return RowGrid.FromPanels(connectedPanelSection.panels)
end

function RowGrid.Subtract(rowgrid1, rowgrid2)
    local diffGridRows = {}

    for gridRowIndex = 1, #rowgrid1.gridRows do
        diffGridRows[gridRowIndex] = RowGridRow.Subtract(rowgrid1.gridRows[gridRowIndex], rowgrid2.gridRows[gridRowIndex])
    end

    return RowGrid(diffGridRows)
end

function RowGrid.SubtractColumn(self, column)
  local diffGrid = deepcpy(self)

  for gridRowIndex = 1, #diffGrid.gridRows do
      diffGrid.gridRows[gridRowIndex].colorColumns[column.color] = diffGrid.gridRows[gridRowIndex].colorColumns[column.color] - column:GetCountInRow(gridRowIndex)
  end

  return diffGrid
end

function RowGrid.MoveDownPanel(self, color, row)
    if self:DropIsValid(row) then
        local rowToDropFrom = self.gridRows[row]
        local receivingRow = self.gridRows[row - 1]
        rowToDropFrom:RemovePanel(color)
        receivingRow:AddPanel(color)
        return self
    else
        return nil
    end
end

function RowGrid.DropIsValid(self, row)
    if row <= 0 then
        return false
    else
      local rowsBelow = table.filter(self.gridRows, function(gridRow) return gridRow.rowIndex < row end)
      return table.trueForAny(rowsBelow, function(gridRow) return gridRow.emptyPanelCount > 0 end)
    end
end

-- returns true if the rowGrid is valid
-- additionally returns the index of the invalid row if false
function RowGrid.IsValid(self)
    -- local invalidRow = table.firstOrDefault(self.gridRows, function(row) return not row:IsValid() end)
    -- if invalidRow then
    --  return false, invalidRow.rowIndex
    -- else
    --    local emptyPanelCount = gridRows[#gridRows].emptyPanelCount
    --    for i = #gridRows - 1, 1 do
    --      if gridRows[i].emptyPanelCount > emptyPanelCount then
    --          return false, i
    --      end
    --    end
    --    return true
    -- end
end

function RowGrid.GetColorColumn(self, color)
    return ColorGridColumn(self, color)
end

function RowGrid.GetTotalEmptyPanelCountInRowAndBelow(self, rowIndex)
    -- measure the empty panels per row to see later how low the stack can potentially get
    local totalEmptyPanelCountInRowAndBelow = 0
    for row=1,rowIndex do
        totalEmptyPanelCountInRowAndBelow =
            totalEmptyPanelCountInRowAndBelow + self.gridRows[row].emptyPanelCount
    end

    return totalEmptyPanelCountInRowAndBelow
end

function RowGrid.GetTotalPanelCountAboveRow(self, rowIndex)
    local totalPanelCountAboveRow = 0
    for row = rowIndex + 1, #self.gridRows do
        totalPanelCountAboveRow = totalPanelCountAboveRow + self.gridRows[row].panelCount
    end

    return totalPanelCountAboveRow
end

function RowGrid.GetTopRowWithPanels(self)
  for i=#self.gridRows, 1, -1 do
    -- at least one panel that is neither empty nor garbage
    if self.columnCount - self.gridRows[i].emptyPanelCount - self.gridRows[i].colorColumns[9] > 0 then
      return i
    end
  end
end

-- returns the top row that has no empty panels, 0 if the bottom row isn't full
function RowGrid.GetTopFullRow(self)
  for i = 1, #self.gridRows do
    if self.gridRows[i].emptyPanelCount > 0 then
      return i - 1
    end
  end
end

-- returns the minimum rowindex the rowgrid can be downstacked into
function RowGrid.GetMinimumTopRowIndex(self)
    local totalEmptyPanelCountInRowAndBelow = 0
    local totalPanelCountAboveRow = self:GetTotalPanelCountAboveRow(0)
    for row = 1, #self.gridRows do
        totalEmptyPanelCountInRowAndBelow = totalEmptyPanelCountInRowAndBelow + self.gridRows[row].emptyPanelCount
        totalPanelCountAboveRow = totalPanelCountAboveRow - self.gridRows[row].panelCount
        if totalEmptyPanelCountInRowAndBelow >= totalPanelCountAboveRow then
            return row
        end
    end
end

function RowGrid.GetEmptyPanelsCountInRow(self, row)
  return self.gridRows[row].emptyPanelCount
end

RowGridRow = class(function(self, rowIndex, colorColumns)
    self.rowIndex = rowIndex
    self.colorColumns = colorColumns
    self.panelCount = 0
    for column = 1, #self.colorColumns do
      if column == 9 then
        self.garbagePanelCount = self.colorColumns[column]
      else
        self.panelCount = self.panelCount + self.colorColumns[column]
      end
    end
    self.emptyPanelCount = 6 - self.panelCount
end)

function RowGridRow.FromPanels(rowIndex, rowPanels)
    -- always use at least 9: shockpanels (8) and garbage (9) appear on every level
    -- column 10 is for storing arbitrary panels during downstack analysis

                  --color 1  2  3  4  5  6  7  8  9 10
    local colorColumns = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
    for column = 1, #rowPanels do
        -- the idea is that columnnumber=color number for readability
        -- exclude garbage but include color 9 panels
        if rowPanels[column].color > 0 and not rowPanels[column].garbage then
          colorColumns[rowPanels[column].color] = colorColumns[rowPanels[column].color] + 1
        end
    end

    return RowGridRow(rowIndex, colorColumns)
end

function RowGridRow.AddPanel(self, color)
    self.colorColumns[color] = self.colorColumns[color] + 1
    self.emptyPanelCount = self.emptyPanelCount - 1
    self.panelCount = self.panelCount + 1
end

function RowGridRow.RemovePanel(self, color)
    self.colorColumns[color] = self.colorColumns[color] - 1
    self.emptyPanelCount = self.emptyPanelCount + 1
    self.panelCount = self.panelCount - 1
end

function RowGridRow.GetColorCount(self, color)
    return self.colorColumns[color]
end

function RowGridRow.IsValid(self)
    return self.emptyPanelCount >= 0
end

function RowGridRow.Subtract(gridrow1, gridrow2)
    assert(gridrow1.rowIndex == gridrow2.rowIndex, "Subtracting 2 completely different rows doesn't make sense")
    local diffGridRowColumns = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

    for column = 1, #gridrow1.columns do
        diffGridRowColumns[column] = gridrow1.colorColumns[column] - gridrow2.colorColumns[column]
    end

    return RowGridRow(gridrow1.rowIndex, diffGridRowColumns)
end

function RowGridRow.TransformToColor10Except(self, exceptColor)
  -- to 9 instead of #self.colorColumns cause converting 10 to 10 really doesn't make sense
  for color = 1, 9 do
    if exceptColor == nil or exceptColor ~= color then
      local count = self.colorColumns[color]
      self.colorColumns[10] = self.colorColumns[10] + count
      self.colorColumns[color] = 0
    end
  end

  return self
end

ColorGridColumn = class(function(self, rowGrid, color)
    self.sourceRowGrid = rowGrid
    self.color = color
end)

function ColorGridColumn.GetColumnRepresentation(self)
    local count = {}
    for row = 1, #self.sourceRowGrid.gridRows do
        count[row] = self.sourceRowGrid.gridRows[row]:GetColorCount(self.color)
    end
    return count
end

function ColorGridColumn.GetLatentMatches(self)
    local consecutiveRowCount = 0
    local columnRepresentation = self:GetColumnRepresentation()
    local matches = {}

    for row = 1, #columnRepresentation do
        -- horizontal 3 matches
        if columnRepresentation[row] >= 3 then
            table.insert(matches, {type = "H", row = row})
        -- vertical 3 matches
        elseif columnRepresentation[row] < 3 and columnRepresentation[row] > 0 then
            consecutiveRowCount = consecutiveRowCount + 1
            if consecutiveRowCount >= 3 then
                table.insert(matches, {type = "V", rows = {row - 2, row - 1, row}})
            end
        else
            consecutiveRowCount = 0
        end
    end

    return matches
end

-- drops one panel in the specified row by one row and returns the new column representation
function ColorGridColumn.DropPanelOneRow(self, row)
    local newRowGrid = self.sourceRowGrid:MoveDownPanelOneRow(self.color, row)
    if newRowGrid then
        return self:GetColumnRepresentation()
    else
        return nil
    end
end

-- drops all panels in that row so that each row contains a valid amount of empty panels
function ColorGridColumn.DropPanels(self, row)
  local topFullRow = self.sourceRowGrid:GetTopFullRow()
  if row <= topFullRow then
    -- impossible to drop panels from this row
    return
  end

  while self:GetCountInRow(row) > 0 do
    -- drop immediately by 1 row
    self.sourceRowGrid:MoveDownPanel(self.color, row)

    for i = row - 1, 2, -1 do
      if row <= topFullRow then
        break
      end

      if self.sourceRowGrid.gridRow[i].emptyPanelCount < self.sourceRowGrid.gridRow[i - 1].emptyPanelCount then
        -- invalid position, need to drop the panel further
        self.sourceRowGrid:MoveDownPanel(self.color, i)
      end
    end
  end
end

function ColorGridColumn.GetTotalPanelCount(self)
    local count = 0
    for row = 1, #self.sourceRowGrid.gridRows do
        count = count + self.sourceRowGrid.gridRows[row]:GetColorCount(self.color)
    end
    return count
end

function ColorGridColumn.GetCountInRow(self, row)
    return self.sourceRowGrid.gridRows[row]:GetColorCount(self.color)
end

function ColorGridColumn.Subtract(self, column)
  assert(self.color == column.color)

  local diffGrid = self.sourceRowGrid:SubtractColumn(column)
  return diffGrid:GetColorColumn(self.color)
end

function ColorGridColumn.GetTopRowWithPanel(self)
  for i = #self.sourceRowGrid.gridRows, 1, -1 do
    if self:GetCountInRow(i) > 0 then
      return i
    end
  end

  return 0
end
