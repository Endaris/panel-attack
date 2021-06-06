CPU1 = class(function(cpu)
    cpu.panelsChanged = false
    cpu.cursorChanged = false
    cpu.actions = {}
    cpu.currentAction = nil
    cpu.actionQueue = {}
    cpu.inputQueue = {}
    cpu.moveRateLimit = 10
    cpu.swapRateLimit = 6
    cpu.idleFrames = 0
    cpu.stack = nil
    cpu.enable_stealth = true
    cpu.enable_inserts = true
    cpu.enable_slides = false
    cpu.enable_catches = false
    cpu.enable_doubleInsert = false
    end)

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
    if #self.inputQueue > 0 and self.idleFrames >= self.moveRateLimit then
        return self.inputQueue[1] + 1
    else
        return 1
    end
end

function CPU1.swap(stack)
    --return base64encode[down+swap+1]
    return base64encode[1]
end

function CPU1.updateStack(self, stack)
    self.panelsChanged = self.stack == nil or not (self.stack.panels == stack.panels)
    self.cursorChanged = self.stack == nil or not (self.stack.cursor_pos == stack.cursor_pos)
    
    self.stack = stack
    self:evaluate()
end

function CPU1.evaluate(self)
    if self.panelsChanged or self.cursorChanged then
        self.idleFrames = 0
        if #self.inputQueue > 0 then
            table.remove(self.inputQueue, 1)
        end
        
        if #self.inputQueue == 0 then
            if #self.actionQueue > 0 then
                self.currentAction = self.actionQueue[1]
            else
                self:findActions()
                for i=1,#self.actions do 
                    self:estimateCost(self.actions[i])
                end
                self:chooseAction()
            end
        end     
    else
        self.idleFrames = self.idleFrames + 1

    end
end

function CPU1.findActions(self)
    local grid = self:panelsToRowGrid()
    
    --find matches, i is row, j is panel color, grid[i][j] is the amount of panels of that color in the row, k is the column the panel is in
    for j=1,#grid[1] do
        local colorConsecutiveRowCount = 0
        local colorConsecutivePanels = {}
        for i=1,#grid do
            -- horizontal 3 matches
             if grid[i][j] >= 3 then
                --fetch the actual panels
                print("found horizontal 3 match in row " .. i .. " for color " .. j)
                local actionPanels = {}
                for k=1, #self.stack.panels[i] do
                    if self.stack.panels[i][k].color == j then
                        local actionPanel = ActionPanel(j, i, k)
                        table.insert(actionPanels, actionPanel)
                    end
                end
                --create the action and put it in our list
                table.insert(self.actions, H3Match(actionPanels))
             end
             -- vertical 3 matches
             if grid[i][j] > 0 then
                colorConsecutiveRowCount = colorConsecutiveRowCount + 1
                for k=1, #self.stack.panels[i] do
                    if self.stack.panels[i][k].color == j then
                        local actionPanel = ActionPanel(j, i, k)
                        table.insert(colorConsecutivePanels, actionPanel)
                    end
                end
                if colorConsecutiveRowCount >= 3 then
                    print("found vertical 3 match in row " .. i-2 .. " to " .. i .. " for color " .. j)
                    table.insert(self.actions, V3Match(colorConsecutivePanels))
                end
             else
                colorConsecutiveRowCount = 0
                consecutivePanels = {}
             end         
         end
     end
end

function CPU1.estimateCost(self, action)
    --dummy value for testing purposes
    --self.stack.cursor_pos
    action.estimatedCost = 1
end

function CPU1.chooseAction(self)
    for i=1,#self.actions do
        print("Action at index" .. i .. ": " ..self.actions[i].name)
    end

    if #self.actions > 0 and self.currentAction == nil then
        --take the first action for testing purposes
        self.currentAction = self.actions[1]
        self.inputQueue = self.currentAction.executionPath
    end 
end

-- returns a 2 dimensional array where i is rownumber (bottom to top), index of j is panel color and value is the amount of panels of that color in the row
function CPU1.panelsToRowGrid(self)
    local panels = self.stack.panels
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


Action = class(function(action, panels)
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)

ActionPanel = class(function(actionPanel, color, row, column)
    actionPanel.color = color
    actionPanel.row = row
    actionPanel.column = column
    actionPanel.isSetupPanel = false
    actionPanel.isExecutionPanel = false
end)


H3Match = class(function(action, panels)
    action.name = "Horizontal 3 Match"
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)

V3Match = class(function(action, panels)
    action.name = "Vertical 3 Match"
    action.panels = panels
    action.garbageValue = 0
    action.stackFreezeValue = 0
    action.estimatedCost = 0
    action.executionPath = nil
end)