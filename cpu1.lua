cpu_configs = {
    ["DevConfig"] =
    {
        {"ReadingBehaviour", "WaitAll"},
    },
    ["DummyTestOption"] =
    {
        {"ReadingBehaviour", "WaitAll"},
    }
}

active_cpuConfig = cpu_configs[1]

CPU1Config = class(function(cpuConfig)
    cpuConfig.ReadingBehaviour = "WaitAll"
end)


CPU1 = class(function(cpu)
    cpu.panelsChanged = false
    cpu.cursorChanged = false
    cpu.actions = {}
    cpu.currentAction = nil
    cpu.actionQueue = {}
    cpu.inputQueue = {}
    cpu.moveRateLimit = 20
    cpu.swapRateLimit = 20
    cpu.idleFrames = 0
    cpu.stack = nil
    cpu.enable_stealth = true
    cpu.enable_inserts = true
    cpu.enable_slides = false
    cpu.enable_catches = false
    cpu.enable_doubleInsert = false
    end)

local wait = 0
--inputs directly as variables cause there are no input devices
local right = 1
local left = 2
local down = 4
local up = 8
local swap = 16
local raise = 32
--these won't be sent as input but serve as indicators when the CPU needs to wait with an input for the correct time instead of performing the swap at the rate limit (and thus failing the trick)
--whether they will see much use or not remains to be seen
local insert = 64
local slide = 128
local catch = 256
local doubleInsert = 512
--technically more than just a swap, combine this with the direction to find out in which direction the stealth is going
--the CPU should make sure to save up enough idleframes for all moves and then perform the inputs in one go
local stealth = 1024

function CPU1.send_controls(self)

    if self.stack and (self.stack.countdown_timer == 0 or not self.stack.countdown_timer) and 
        self.inputQueue and #self.inputQueue > 0 and self.idleFrames >= self.moveRateLimit then
        local input = table.remove(self.inputQueue, 1)
        print("executing input " .. input)
        self.idleFrames = 0
        return base64encode[input + 1]
    else
        if not self.idleFrames then
            self.idleFrames = 0
        else
            self.idleFrames = self.idleFrames + 1
        end
        -- print("#self.inputQueue is " .. #self.inputQueue)
        -- print("self.idleFrames is " .. self.idleFrames)
        -- print("self.moveRateLimit is " .. self.moveRateLimit)

        return base64encode[1]
    end
end

function CPU1.updateStack(self, stack)
    self.stack = stack
    self:evaluate()
end

function CPU1.evaluate(self)    
    if #self.inputQueue == 0 then
        self:finalizeAction(self.currentAction)
        if #self.actionQueue > 0 then
            local action = table.remove(self.actionQueue, 1)
            self.currentAction = action
        else
            self:findActions()
            self:calculateCosts()
            self:chooseAction()
        end
    end
end

function CPU1.finalizeAction(self, action)
    self.currentAction = nil
end

function CPU1.findActions(self)
    self.actions = {}
    local grid = self:panelsToRowGrid()
    
    --find matches, i is row, j is panel color, grid[i][j] is the amount of panels of that color in the row, k is the column the panel is in
    for j=1,#grid[1] do
        local colorConsecutiveRowCount = 0
        local colorConsecutivePanels = {}
        for i=1,#grid do       
            -- horizontal 3 matches
            --  if grid[i][j] >= 3 then
            --     --fetch the actual panels
            --     print("found horizontal 3 match in row " .. i .. " for color " .. j)
            --     local actionPanels = {}
            --     for k=1, #self.stack.panels[i] do
            --         if self.stack.panels[i][k].color == j then
            --             local actionPanel = ActionPanel(j, i, k)
            --             table.insert(actionPanels, actionPanel)
            --         end
            --     end
            --     --create the action and put it in our list
            --     table.insert(self.actions, H3Match(actionPanels))
            --  end
             -- vertical 3 matches
             if grid[i][j] > 0 then
                colorConsecutiveRowCount = colorConsecutiveRowCount + 1
                colorConsecutivePanels[colorConsecutiveRowCount] = {}
                for k=1, #self.stack.panels[i] do
                    if self.stack.panels[i][k].color == j then
                        local actionPanel = ActionPanel(j, i, k)
                        table.insert(colorConsecutivePanels[colorConsecutiveRowCount], actionPanel)
                    end
                end
                if colorConsecutiveRowCount >= 3 then
                    -- technically we need action for each unique combination of panels to find the best option
                    local combinations = #colorConsecutivePanels[colorConsecutiveRowCount - 2] * #colorConsecutivePanels[colorConsecutiveRowCount - 1] * #colorConsecutivePanels[colorConsecutiveRowCount]
                    print("found " ..combinations .. " combination(s) for a vertical 3 match in row " .. i-2 .. " to " .. i .. " for color " .. j)

                    for q=1,#colorConsecutivePanels[colorConsecutiveRowCount - 2] do
                        for r=1,#colorConsecutivePanels[colorConsecutiveRowCount - 1] do                    
                            for s=1,#colorConsecutivePanels[colorConsecutiveRowCount] do
                                local panels = {}
                                table.insert(panels, colorConsecutivePanels[colorConsecutiveRowCount - 2][q])
                                table.insert(panels, colorConsecutivePanels[colorConsecutiveRowCount - 1][r])
                                table.insert(panels, colorConsecutivePanels[colorConsecutiveRowCount][s])
                                table.insert(self.actions, V3Match(panels))
                            end
                        end
                    end
                end
                -- if colorConsecutiveRowCount >= 4 then
                --     print("found vertical 4 combo in row " .. i-3 .. " to " .. i .. " for color " .. j)
                --     table.insert(self.actions, V4Combo(colorConsecutivePanels))
                -- end
                -- if colorConsecutiveRowCount >= 5 then
                --     print("found vertical 5 combo in row " .. i-4 .. " to " .. i .. " for color " .. j)
                --     table.insert(self.actions, V5Combo(colorConsecutivePanels))
                -- end
             else
                colorConsecutiveRowCount = 0
                consecutivePanels = {}
             end      
             
             
         end
     end
end

function CPU1.calculateCosts(self)
    for i=1,#self.actions do
        self.actions[i]:calculateCost()
    end
end

function CPU1.estimateCost(self, action)
    --dummy value for testing purposes
    --self.stack.cursor_pos
    action.estimatedCost = 1
end

function CPU1.chooseAction(self)
    for i=1,#self.actions do
        print("Action at index" .. i .. ": " ..self.actions[i].name .." with cost of " ..self.actions[i].estimatedCost)
    end

    if #self.actions > 0 and self.currentAction == nil then
        print("current action is nil and there are actions")
        --take the first action for testing purposes
        self.currentAction = self:getCheapestAction()
        print("current action is " ..self.currentAction.name)
        --print("first element of executionpath is " ..self.currentAction.executionPath[1])
        for i = 1, #self.currentAction.executionPath do
            print("next element of executionpath is " ..self.currentAction.executionPath[i])
        end
        self.inputQueue = self.currentAction.executionPath
    else
        table.insert(self.inputQueue, raise)
    end 
end

function CPU1.getCheapestAction(self)
    local actions = {}

    if #self.actions > 0 then
        table.sort(self.actions, function(a,b) 
            return a.estimatedCost < b.estimatedCost
        end)

        for i=1,#self.actions do
            self.actions[i]:print()
        end

        local i = 1
        while i <= #self.actions and self.actions[i].estimatedCost == self.actions[1].estimatedCost do
            self.actions[i]:calculateExecution(self.stack.cur_row, self.stack.cur_col + 0.5)
            print(i)
            table.insert(actions, self.actions[i])
            i = i+1
        end

        table.sort(actions, function(a,b)
            return #a.executionPath < #b.executionPath
        end)

        return actions[1]
    else
        return Raise()
    end
    
end

-- returns a 2 dimensional array where i is rownumber (bottom to top), index of j is panel color and value is the amount of panels of that color in the row
function CPU1.panelsToRowGrid(self)
    local panels = self.stack.panels
    self:printAsAprilStack()
    local grid = {}
    for i=1,#panels do
        grid[i] = {}
        -- always use 8: shockpanels appear on every level and we want columnnumber=color number for readability
        for j=1,8 do
            local count = 0
            for k = 1,#panels[1] do
                if panels[i][k].color == j then
                    count = count + 1
                end
            end
            grid[i][j] = count
        end
    end
    return grid
end

-- exists to avoid the case where the cpu finds an action with panels that are falling down and thus no longer in the expected location when the cursor arrives
-- may still be faulty if the panels coincidently fall into a chain
-- should be dropped once the CPU is capable of properly tracking the panels for its current action.
-- function simulatePostFallingState(panels)
--     print("simulating post falling state")
--     -- go down from top to bottom and reinsert any 0s after finding a non 0 at the top
--     print("columns = " .. #panels[1])
--     print("rows = " .. #panels)
--     for i=1,#panels[1] do
--         local panelFound = false
--         for j=#panels,1,-1 do
--             print("panel at coordinate " .. j .. "|" .. i .. " has color " .. panels[j][i].color)
--             if panels[j][i].color == 0 then
--                 if panelFound then
--                     table.remove(panels[j], i)
--                     table.insert(panels[j], 0)
--                 end
--             else
--                 panelFound = true
--             end
--         end
--     end
--     return panels
-- end

function CPU1.printAsAprilStack(self)
    if self.stack then
        local panels = self.stack.panels
        local panelString = ""
        for i=#panels,1,-1 do
            for j=1,#panels[1] do
                panelString = panelString.. (tostring(panels[i][j].color))
            end
        end
        print("april panelstring is " .. panelString)

        panelString = ""
        for i=#panels,1,-1 do
            for j=1,#panels[1] do
                if not panels[i][j].state == "normal" then
                    panelString = panelString.. (tostring(panels[i][j].color))    
                end
            end
        end

        print("panels in non-normal state are " .. panelString)
    end  
end

Raise = class(function(action)
    Action.init()
    action.estimatedCost = 0
    action.executionPath = { raise, wait }
end, Action)

Action = class(function(action, panels)
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
    action.isClear = false
end)

function Action.addCursorMovementToExecution(self, gridVector)
    error("addCursorMovementToExecution was not implemented for action " ..self.name)

end

function Action.addPanelMovementToExecution(self, gridVector)
    error("addCursorMovementToExecution was not implemented for action " ..self.name)
end

function Action.calculateExecution(self, cursor_row, cursor_col)
    error("calculateExecution was not implemented for action " ..self.name)
end

function Action.calculateCost(self)
    error("calculateCost was not implemented for action " ..self.name)
end

ActionPanel = class(function(actionPanel, color, row, column)
    actionPanel.color = color
    actionPanel.row = row
    actionPanel.column = column
    actionPanel.vector = GridVector(row, column)
    actionPanel.cursorStartPos = nil
    actionPanel.isSetupPanel = false
    actionPanel.isExecutionPanel = false
end)

function ActionPanel.print(self)
    print("panel with color " .. self.color .. " at coordinate " .. self.row .. "|" .. self.column)
end


H3Match = class(function(action, panels)
    Action.init(action, panels)
    action.name = "Horizontal 3 Match"
    action.color = panels[1].color
end, Action)

function H3Match.calculateCost(self)
    self.estimatedCost = 1000
end

function H3Match.calculateExecution(self, cursor_row, cursor_col)
    
end

V3Match = class(function(action, panels)
    Action.init(action, panels)
    action.name = "Vertical 3 Match"
    action.color = panels[1].color
    action.targetColumn = 0    
end, Action)

function V3Match.print(self)
    print("printing " ..self.name .. " with estimated cost of " ..self.estimatedCost)
    for i=1,#self.panels do
        self.panels[i]:print()
    end
end

function V3Match.addCursorMovementToExecution(self, gridVector)
    print("adding cursor movement to the input queue with vector" ..gridVector.row .. "|" ..gridVector.column)
    --vertical movement
    if math.sign(gridVector.row) == 1 then
        for i=1,math.abs(gridVector.row) do
            table.insert(self.executionPath, down)
        end
    elseif math.sign(gridVector.row) == -1 then
        for i=1,math.abs(gridVector.row) do
            table.insert(self.executionPath, up)
        end
    else
        --no vertical movement required
    end

    --horizontal movement
    if math.sign(gridVector.column) == 1 then
        for i=1,math.abs(gridVector.column) do
            table.insert(self.executionPath, left)
        end
    elseif math.sign(gridVector.column) == -1 then
        for i=1,math.abs(gridVector.column) do
            table.insert(self.executionPath, right)
        end
    else
        --no vertical movement required
    end
end

function V3Match.addPanelMovementToExecution(self, gridVector)
    print("adding panel movement to the input queue with vector" ..gridVector.row .. "|" ..gridVector.column)

    -- always starting with a swap because it is assumed that we already moved into the correct location for the initial swap
    table.insert(self.executionPath, swap)
    --section needs a rework once moving panels between rows are considered
    --vertical movement
    if math.sign(gridVector.row) == 1 then
        for i=2,math.abs(gridVector.row) do
            table.insert(self.executionPath, up)
            table.insert(self.executionPath, swap)
        end
    elseif math.sign(gridVector.row) == -1 then
        for i=2,math.abs(gridVector.row) do
            table.insert(self.executionPath, down)
            table.insert(self.executionPath, swap)
        end
    else
        --no vertical movement required
    end

    --horizontal movement
    if math.sign(gridVector.column) == 1 then
        for i=2,math.abs(gridVector.column) do
            table.insert(self.executionPath, right)
            table.insert(self.executionPath, swap)
        end
    elseif math.sign(gridVector.column) == -1 then
        for i=2,math.abs(gridVector.column) do
            table.insert(self.executionPath, left)
            table.insert(self.executionPath, swap)
        end
    else
        --no vertical movement required
    end
end

function V3Match.calculateCost(self)
    self:chooseColumn()
end

function V3Match.calculateExecution(self, cursor_row, cursor_col)
    print("calculating execution path for action " .. self.name)
    print("action has " .. #self.panels .. " panels")
    print("with color " .. self.color .. " in column " .. self.targetColumn)
    print("panel 1 is at coordinates " .. self.panels[1].row .. "|" .. self.panels[1].column)
    print("panel 2 is at coordinates " .. self.panels[2].row .. "|" .. self.panels[2].column)
    print("panel 3 is at coordinates " .. self.panels[3].row .. "|" .. self.panels[3].column)

    self.executionPath = {}

    local panelsToMove = self:getPanelsToMove()
    print("found " ..#panelsToMove .. " panels to move")
    -- cursor_col is the column of the left part of the cursor
    local cursorVec = GridVector(cursor_row, cursor_col)
    print("cursor vec is " ..cursorVec.row .. "|" ..cursorVec.column)
    while (#panelsToMove > 0)
    do
        panelsToMove = self:sortByDistanceToCursor(panelsToMove, cursorVec)
        local nextPanel = panelsToMove[1]
        print("nextPanel cursorstartpos is " ..nextPanel.cursorStartPos.row .."|"..nextPanel.cursorStartPos.column)
        local moveToPanelVec = cursorVec:difference(nextPanel.cursorStartPos)
        print("difference vec is " ..moveToPanelVec.row .. "|" ..moveToPanelVec.column)
        self:addCursorMovementToExecution(moveToPanelVec)
        local movePanelVec = GridVector(0, self.targetColumn - nextPanel.column)
        print("panel movement vec is " ..movePanelVec.row .. "|" ..movePanelVec.column)
        self:addPanelMovementToExecution(movePanelVec)
        -- assuming we arrived with this panel
        nextPanel.column = self.targetColumn
        -- update the cursor position for the next round
        cursorVec = cursorVec:substract(moveToPanelVec):add(GridVector(0, movePanelVec.column + math.sign(movePanelVec.column)))
        print("next cursor vec is " ..cursorVec.row .. "|" ..cursorVec.column)
        --remove the panel we just moved so we don't try moving it again
        table.remove(panelsToMove, 1)
        print("found " ..#panelsToMove .. " panels to move")
    end

    -- wait at the end of each action to avoid scanning the board again while the last swap is still in progress
    table.insert(self.executionPath, wait)
    print("exiting calculateExecution")
end

function V3Match.getPanelsToMove(self)
    local panelsToMove = {}
    print("#self.panels has " ..#self.panels .. " panels")
    print("targetColumn is " ..self.targetColumn)
    for i=1,#self.panels do 
        print("panel at index " ..i .. " is in column" ..self.panels[i].column)
        if self.panels[i].column == self.targetColumn then
            print(" panel with index " ..i .. " is in the target column, skipping")
        else
            print("inserting panel with index " ..i .. " into the table")
            table.insert(panelsToMove, self.panels[i])
        end
    end

    return panelsToMove
end

function V3Match.sortByDistanceToCursor(self, panels, cursorVec)
    --setting the correct cursor position for starting to work on each panel here
    for i=1,#panels do
        local panel = panels[i]
        if panel.column > self.targetColumn then
            panel.cursorStartPos = GridVector(panel.row, panel.column - 0.5)
        else
            panel.cursorStartPos = GridVector(panel.row, panel.column + 0.5)
        end      
    end

    table.sort(panels, function(a, b)
        return cursorVec:distance(a.cursorStartPos) < cursorVec:distance(b.cursorStartPos)
    end)
    
    return panels
end

function V3Match.chooseColumn(self)
    self:print()
    local column
    local minCost = 1000
    for i=1,6 do
        local colCost = 0
        for j=1,#self.panels do
            --how many columns the panel is away from the column we're testing for
            local distance = math.abs(self.panels[j].column - i)
            if distance > 0 then
                --penalty for having to move to the panel to move it
                colCost = colCost + 2
                --cost for moving the panel
                colCost = colCost + distance
            end
        end
        if colCost < minCost then
            minCost = colCost
            column = i
        end
    end

    self.estimatedCost = minCost
    self.targetColumn = column
end

V4Combo = class(function(action, panels)
    action.name = "Vertical 4 Combo"
    action.color = panels[1].color
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)

function V4Combo.calculateCost(self)
    self.estimatedCost = 1000
end

V5Combo = class(function(action, panels)
    action.name = "Vertical 5 Combo"
    action.color = panels[1].color
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)

function V5Combo.calculateCost(self)
    self.estimatedCost = 1000
end

T5Combo = class(function(action, panels)
    action.name = "T-shaped 5 Combo"
    action.color = panels[1].color
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)

L5Combo = class(function(action, panels)
    action.name = "L-shaped 5 Combo"
    action.color = panels[1].color
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)

T6Combo = class(function(action, panels)
    action.name = "T-shaped 6 Combo"
    action.color = panels[1].color
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)

T7Combo = class(function(action, panels)
    action.name = "T-shaped 7 Combo"
    action.color = panels[1].color
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)


GridVector = class(function(vector, row, column)
    vector.row = row
    vector.column = column
end)

function GridVector.distance(self, otherVec)
    --since this is a grid where diagonal movement is not possible it's just the sum of both directions instead of a diagonal
    return math.abs(self.row - otherVec.row) + math.abs(self.column - otherVec.column)
end

function GridVector.difference(self, otherVec)
    return GridVector(self.row - otherVec.row, self.column - otherVec.column)
end

function GridVector.add(self, otherVec)
    return GridVector(self.row + otherVec.row, self.column + otherVec.column)
end

function GridVector.substract(self, otherVec)
    return GridVector(self.row - otherVec.row, self.column - otherVec.column)
end

function math.sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end