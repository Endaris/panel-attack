cpu_configs = {
    ['DevConfig'] = {
        ReadingBehaviour = 'WaitAll',
        Log = true,
        MoveRateLimit = 5,
        MoveSwapRateLimit = 10,
        DefragmentationPercentageThreshold = 0.3
    },
    ['DummyTestOption'] = {
        ReadingBehaviour = 'WaitAll',
        Log = false,
        MoveRateLimit = 40,
        MoveSwapRateLimit = 40,
        DefragmentationPercentageThreshold = 0.3
    }
}

active_cpuConfig = cpu_configs[1]

CPU1Config =
    class(
    function(cpuConfig, actualConfig)
        cpuConfig.ReadingBehaviour = actualConfig['ReadingBehaviour']
        cpuConfig.Log = actualConfig['Log']
        cpuConfig.MoveRateLimit = actualConfig['MoveRateLimit']
        cpuConfig.MoveSwapRateLimit = actualConfig['MoveSwapRateLimit']
        cpuConfig.DefragmentationPercentageThreshold = actualConfig['DefragmentationPercentageThreshold']
    end
)

CPU1 =
    class(
    function(cpu)
        cpu.panelsChanged = false
        cpu.cursorChanged = false
        cpu.actions = {}
        cpu.currentAction = nil
        cpu.strategy = nil
        cpu.actionQueue = {}
        cpu.inputQueue = {}
        cpu.idleFrames = 0
        cpu.waitFrames = 0
        cpu.stack = nil
        cpu.enable_stealth = true
        cpu.enable_inserts = true
        cpu.enable_slides = false
        cpu.enable_catches = false
        cpu.enable_doubleInsert = false
        cpu.lastInput = nil
        if active_cpuConfig then
            print('cpu config successfully loaded')
            cpu.config = CPU1Config(active_cpuConfig)
            print_config(active_cpuConfig)
        else
            error('cpu config is nil')
        end
    end
)

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

function isMovement(input)
    --innocently assuming we never input a direction together with something else unless it's a special that includes a timed swap anyway (doubleInsert,stealth)
    if input then
        return input > 0 and input < 16
    else --only relevant for the very first input
        return true
    end
end

function CPU1.send_controls(self)
    --the conditions are intentional so that the control flow (specifically the exits) is more obvious rather than having a tail of "else return" where you can't tell where it's coming from
    if not self.stack then
        return self:idle()
    else --there is a stack, most basic requirement
        if not self.inputQueue or #self.inputQueue == 0 then
            return self:idle()
        else --there is actually something to execute
            if self.stack.countdown_timer and self.stack.countdown_timer > 0 and not isMovement(self.inputQueue[1]) then
                return self:idle()
            else --either we're just moving or countdown is already over so we can actually do the thing
                if isMovement(self.lastInput) and isMovement(self.inputQueue[1]) then
                    if self.idleFrames < self.config.MoveRateLimit then
                        return self:idle()
                    else
                        return self:input()
                    end
                else
                    if self.idleFrames < self.config.MoveSwapRateLimit then
                        return self:idle()
                    else
                        return self:input()
                    end
                end
            end
        end
    end
end

function CPU1.idle(self)
    if not self.idleFrames then
        self.idleFrames = 0
    else
        self.idleFrames = self.idleFrames + 1
    end
    --cpuLog("#self.inputQueue is " .. #self.inputQueue)
    --cpuLog("self.idleFrames is " .. self.idleFrames)
    -- cpuLog("self.moveRateLimit is " .. self.moveRateLimit)

    return base64encode[1]
end

function CPU1.input(self)
    self.lastInput = table.remove(self.inputQueue, 1)
    cpuLog('executing input ' .. self.lastInput)
    self.idleFrames = 0
    return base64encode[self.lastInput + 1]
end

function CPU1.updateStack(self, stack)
    self.stack = stack
    self:evaluate()
end

function CPU1.evaluate(self)
    if self.stack and #self.inputQueue == 0 then
        if self.currentAction then
            self:finalizeCurrentAction()
        end

        if self.waitFrames <= 0 then
            if #self.actionQueue == 0 then
                -- this part should go into a subroutine later so that calculations can be done over multiple frames
                self.strategy = self:chooseStrategy()
                self:findActions()
                self:calculateCosts()
            end
            self:chooseAction()
        else
            self.waitFrames = self.waitFrames - 1
        end
    end
end

function CPU1.finalizeCurrentAction(self)
    local waitFrames = 0
    cpuLog('finalizing action ' .. self.currentAction.name)
    cpuLog('ReadingBehaviour config value is ' .. self.config.ReadingBehaviour)

    if self.currentAction.panels then
        if self.config.ReadingBehaviour == 'WaitAll' then
            -- constant for completing a swap, see Panel.clear() for reference
            waitFrames = waitFrames + 4
            -- wait for all panels to pop
            waitFrames = waitFrames + level_to_flash[self.stack.level]
            waitFrames = waitFrames + level_to_face[self.stack.level]
            --the first panel is popped at the end of the face part so there's only additional waiting time for each panel beyond the first
            for i = 1, #self.currentAction.panels do
                waitFrames = waitFrames + level_to_pop[self.stack.level]
            end

            -- wait for other panels to fall
            waitFrames = waitFrames + level_to_hover[self.stack.level]
            -- this is overly simplified, assuming that all the panels in the action are vertically stacked, meaning this might overshoot the waiting time
            waitFrames = waitFrames + #self.currentAction.panels

            -- 2 frames safety margin cause i'm still finding completed matches
            waitFrames = waitFrames + 2
        elseif self.config.ReadingBehaviour == 'WaitMatch' then
            -- constant for completing a swap, see Panel.clear() for reference
            waitFrames = 4
        --else  cpu.config["ReadingBehaviour"] == "Instantly", default behaviour
        --  waitFrames = 0
        end
    else
        -- no panels -> must be a raise, 10 is a number found through experimentation when the raise is reliably completed
        -- otherwise the cpu won't detect the rais in time and try to raise again so you get a double raise
        waitFrames = 10
    end

    cpuLog('setting waitframes to ' .. waitFrames)
    self.waitFrames = waitFrames

    -- action is now fully wrapped up
    self.currentAction = nil
end

function CPU1.chooseStrategy(self)
    if not self.stack or not self.stack.panels then
        return Attack(self)
    else
        self:printAsAprilStack()
    end

    if self.stack.danger_music then
        --return Defend(self) 
        --for testing
        return Defragment(self)
    end

    local fragmentationPercentage = self.stack:getFragmentationPercentage()
    cpuLog('Fragmentation % is ' .. fragmentationPercentage)
    if fragmentationPercentage > self.config.DefragmentationPercentageThreshold then
        cpuLog("Chose Defragment as strategy!")
        return Defragment(self)
    end

    return Attack(self)
end

function CPU1.findActions(self)
    self.actions = {}
    local grid = self:panelsToRowGrid()

    --find matches, i is row, j is panel color, grid[i][j] is the amount of panels of that color in the row, k is the column the panel is in
    for j = 1, #grid[1] do
        local colorConsecutiveRowCount = 0
        local colorConsecutivePanels = {}
        for i = 1, #grid do
            -- horizontal 3 matches
            if grid[i][j] >= 3 then
                --fetch the actual panels
                cpuLog('found horizontal 3 match in row ' .. i .. ' for color ' .. j)
                local panels = {}
                for k = 1, #self.stack.panels[i] do
                    if self.stack.panels[i][k].color == j then
                        local actionPanel = ActionPanel(self.stack.panels[i][k].id, j, i, k)
                        table.insert(panels, actionPanel)
                    end
                end

                -- if there are 4 in the row, add 2 actions
                for n = 1, #panels - 2 do
                    local actionPanels = {}

                    table.insert(actionPanels, panels[n]:copy())
                    table.insert(actionPanels, panels[n + 1]:copy())
                    table.insert(actionPanels, panels[n + 2]:copy())

                    --create the action and put it in our list
                    table.insert(self.actions, H3Match(actionPanels))
                end
            end
            -- vertical 3 matches
            if grid[i][j] > 0 then
                -- if colorConsecutiveRowCount >= 4 then
                --     cpuLog("found vertical 4 combo in row " .. i-3 .. " to " .. i .. " for color " .. j)
                --     table.insert(self.actions, V4Combo(colorConsecutivePanels))
                -- end
                -- if colorConsecutiveRowCount >= 5 then
                --     cpuLog("found vertical 5 combo in row " .. i-4 .. " to " .. i .. " for color " .. j)
                --     table.insert(self.actions, V5Combo(colorConsecutivePanels))
                -- end
                colorConsecutiveRowCount = colorConsecutiveRowCount + 1
                colorConsecutivePanels[colorConsecutiveRowCount] = {}
                for k = 1, #self.stack.panels[i] do
                    if self.stack.panels[i][k].color == j then
                        local actionPanel = ActionPanel(self.stack.panels[i][k].id, j, i, k)
                        table.insert(colorConsecutivePanels[colorConsecutiveRowCount], actionPanel)
                    end
                end
                if colorConsecutiveRowCount >= 3 then
                    -- technically we need action for each unique combination of panels to find the best option
                    local combinations =
                        #colorConsecutivePanels[colorConsecutiveRowCount - 2] *
                        #colorConsecutivePanels[colorConsecutiveRowCount - 1] *
                        #colorConsecutivePanels[colorConsecutiveRowCount]
                    cpuLog(
                        'found ' ..
                            combinations ..
                                ' combination(s) for a vertical 3 match in row ' ..
                                    i - 2 .. ' to ' .. i .. ' for color ' .. j
                    )

                    for q = 1, #colorConsecutivePanels[colorConsecutiveRowCount - 2] do
                        for r = 1, #colorConsecutivePanels[colorConsecutiveRowCount - 1] do
                            for s = 1, #colorConsecutivePanels[colorConsecutiveRowCount] do
                                local panels = {}
                                table.insert(panels, colorConsecutivePanels[colorConsecutiveRowCount - 2][q]:copy())
                                table.insert(panels, colorConsecutivePanels[colorConsecutiveRowCount - 1][r]:copy())
                                table.insert(panels, colorConsecutivePanels[colorConsecutiveRowCount][s]:copy())
                                table.insert(self.actions, V3Match(panels))
                            end
                        end
                    end
                end
            else
                colorConsecutiveRowCount = 0
                colorConsecutivePanels = {}
            end
        end
    end
end

function CPU1.calculateCosts(self)
    for i = 1, #self.actions do
        self.actions[i]:calculateCost()
    end
end

function CPU1.estimateCost(self, action)
    --dummy value for testing purposes
    --self.stack.cursor_pos
    action.estimatedCost = 1
end

function CPU1.chooseAction(self)
    if #self.actionQueue > 0 then
        local action = table.remove(self.actionQueue, 1)
        cpuLog("Taking action out of the actionQueue")
        action:print()
        self.currentAction = action
        if not self.currentAction.executionPath or #self.currentAction.executionPath == 0 then
            self.currentAction:calculateExecution(self.stack.cur_row, self.stack.cur_col)
        end
        self.inputQueue = self.currentAction.executionPath
    else
        self.strategy:chooseAction()
    end

    if self.currentAction then
        cpuLog('chose following action')
        self.currentAction:print()
        self.inputQueue = self.currentAction.executionPath
    else
        cpuLog('chosen action is nil')
    end
end

-- returns a 2 dimensional array where i is rownumber (bottom to top), index of j is panel color and value is the amount of panels of that color in the row
function CPU1.panelsToRowGrid(self)
    local panels = self.stack.panels
    self:printAsAprilStack()
    local grid = {}
    for i = 1, #panels do
        grid[i] = {}
        -- always use 8: shockpanels appear on every level and we want columnnumber=color number for readability
        for j = 1, 8 do
            local count = 0
            for k = 1, #panels[1] do
                if panels[i][k].color == j then
                    count = count + 1
                end
            end
            grid[i][j] = count
        end
    end
    return grid
end

function CPU1.printAsAprilStack(self)
    if self.stack then
        local panels = self.stack.panels
        local panelString = ''
        for i = #panels, 1, -1 do
            for j = 1, #panels[1] do
                panelString = panelString .. (tostring(panels[i][j].color))
            end
        end
        cpuLog('april panelstring is ' .. panelString)

        panelString = ''
        for i = #panels, 1, -1 do
            for j = 1, #panels[1] do
                if not panels[i][j].state == 'normal' then
                    panelString = panelString .. (tostring(panels[i][j].color))
                end
            end
        end

        cpuLog('panels in non-normal state are ' .. panelString)
    end
end


Strategy = class(function(strategy, name, cpu)
    strategy.name = name
    strategy.cpu = cpu
end)

function Strategy.chooseAction(self)
    error("Method chooseAction of strategy " .. self.name .. " has not been implemented.")
end

Defend = class(
        function(strategy, cpu)
            Strategy.init(strategy, "Defend", cpu)
        end,
        Strategy
)

function Defend.chooseAction(self)

end

Defragment = class(
        function(strategy, cpu)
            Strategy.init(strategy, "Defragment", cpu)
        end,
        Strategy
)

function Defragment.chooseAction(self)
    local columns = self.cpu.stack:getTier1PanelsAsColumns()
    local connectedPanelSections = self.cpu.stack:getTier1ConnectedPanelSections()
    local panels = {}
    local emptySpaces = {}

    for i=1,#columns do
        for j=1,#columns[i] do
            table.insert(panels, {columns[i][j], 0})
        end
    end

    --setting up a table for the empty spaces
    local maxColHeight = 0
    for i=1,#columns do
        maxColHeight = math.max(maxColHeight, #columns[i])
    end

    for i=1,maxColHeight + 1 do
        for j=1,#columns do
            if self.cpu.stack.panels[i][j].color == 0 then
                local emptySpace = ActionPanel(self.cpu.stack.panels[i][j].id, 0, i, j)
                table.insert(emptySpaces, {emptySpace, 0})
            end
        end
    end

    for i=1,#connectedPanelSections do
        connectedPanelSections[i]:print()

        -- setting scores for panels
        for j=1,#panels do
            if panels[j][1].vector:inRectangle(connectedPanelSections[i].bottomLeftVector, connectedPanelSections[i].topRightVector) then
                panels[j][2] = panels[j][2] + connectedPanelSections[i].numberOfPanels
            end
        end
        -- setting scores for adjacent empty space
        for j=1,#emptySpaces do
            if emptySpaces[j][1].vector:adjacentToRectangle(connectedPanelSections[i].bottomLeftVector, connectedPanelSections[i].topRightVector) then
                emptySpaces[j][2] = emptySpaces[j][2] + 1
            end
        end
    end

    --debugging
    for i=1,#panels do
        cpuLog("panel " .. panels[i][1].id .. " at coord " .. panels[i][1].vector:toString() .. " with value of " .. panels[i][2])
    end
    --debugging
    for i=1,#emptySpaces do
        cpuLog("empty space " .. i .. " at coord " .. emptySpaces[i][1].vector:toString() .. " with value of " .. emptySpaces[i][2])
    end

    table.sort(emptySpaces, function(a, b)
        return a[2]>b[2]
    end)

    local emptySpacesToFill = { emptySpaces[1][1] }
    for i=2,#emptySpaces do
        if emptySpaces[i][2] == emptySpaces[1][2] then
            table.insert(emptySpacesToFill, emptySpaces[i][1])
        else
            break
        end
    end

    local cursorVec = GridVector(self.cpu.stack.cur_row, self.cpu.stack.cur_col)
    
    table.sort(emptySpacesToFill, function(a, b)
        return a.vector:distance(cursorVec) < b.vector:distance(cursorVec)
    end)

    local panelsToMove
    for i=1,#emptySpacesToFill do
        if (not panelsToMove or #panelsToMove == 0) then
            if #panels > 0 then
                panelsToMove = self:GetFreshPanelsToMove(panels)
            else
                -- can't continue without panels, rerun defragmentation to source new panels
                break
            end
        end

        table.sort(panelsToMove, function(a, b)
            return math.abs(a.column - emptySpacesToFill[i].column) <
                                math.abs(b.column - emptySpacesToFill[i].column) and
                                a.row >= emptySpacesToFill[i].row
        end)

        cpuLog("Trying to fill " .. #emptySpacesToFill .. " emptySpaces with " .. #panelsToMove .. " panels")

        local panel = table.remove(panelsToMove, 1)
        panel:print()
        local action = Move(self.cpu.stack, panel, emptySpacesToFill[i].vector)
        action:calculateExecution(self.cpu.stack.cur_row, self.cpu.stack.cur_col)
        action:print()

        if self.cpu.currentAction == nil then
            self.cpu.currentAction = action
        else
            table.insert(self.cpu.actionQueue, action)
        end
    end

    -- open issues with defragmenting:
    -- tries to "upstack" (bottom row) panels
    -- takes the panel instead of the closest panel from the column to downstack
    -- needs to weigh distance on top of solely panel score for the panel selection
    -- sometimes the first line of garbage panels is included in the connectedPanelSections somehow
end

function Defragment.GetFreshPanelsToMove(self, panels)
    table.sort(panels, function(a, b)
        return a[2]<b[2]
    end)

    -- need to rework this somehow to weigh distance against score
    local panelScore = panels[1][2]
    local firstPanel = table.remove(panels, 1)[1]
    local panelsToMove = { firstPanel }
    while #panels > 0 and panels[1][2] == panelScore do
        local panel = table.remove(panels, 1)[1]
        table.insert(panelsToMove, panel)
    end

    return panelsToMove
end

Attack = class(
        function(strategy, cpu)
            Strategy.init(strategy, "Attack", cpu)
        end,
        Strategy
)

function Attack.chooseAction(self)
    for i = 1, #self.cpu.actions do
        cpuLog(
            'Action at index' ..
                i .. ': ' .. self.cpu.actions[i].name .. ' with cost of ' .. self.cpu.actions[i].estimatedCost
        )
    end

    if #self.cpu.actions > 0 then
        self.cpu.currentAction = self:getCheapestAction()
    else
        self.cpu.currentAction = Raise()
    end
end

function Attack.getCheapestAction(self)
    local actions = {}

    if #self.cpu.actions > 0 then
        table.sort(
            self.cpu.actions,
            function(a, b)
                return a.estimatedCost < b.estimatedCost
            end
        )

        for i = #self.cpu.actions, 1, -1 do
            self.cpu.actions[i]:print()
            -- this is a crutch cause sometimes we can find actions that are already completed and then we choose them cause they're already...complete
            if self.cpu.actions[i].estimatedCost == 0 then
                cpuLog('actions is already completed, removing...')
                table.remove(self.cpu.actions, i)
            end
        end

        local i = 1
        while i <= #self.cpu.actions and self.cpu.actions[i].estimatedCost == self.cpu.actions[1].estimatedCost do
            self.cpu.actions[i]:calculateExecution(self.cpu.stack.cur_row, self.cpu.stack.cur_col + 0.5)
            table.insert(actions, self.cpu.actions[i])
            i = i + 1
        end

        table.sort(
            actions,
            function(a, b)
                return #a.executionPath < #b.executionPath
            end
        )

        return actions[1]
    else
        return Raise()
    end
end

ActionPanel =
    class(
    function(actionPanel, id, color, row, column)
        actionPanel.id = id
        actionPanel.color = color
        actionPanel.row = row
        actionPanel.column = column
        actionPanel.vector = GridVector(row, column)
        actionPanel.targetVector = nil
        actionPanel.cursorStartPos = nil
        actionPanel.isSetupPanel = false
        actionPanel.isExecutionPanel = false
        -- add a reference to the original panel to track state etc.
    end
)

function ActionPanel.print(self)
    local message = 'panel with color ' .. self.color 
    if self.vector then
        message = message .. ' at coordinate ' .. self.vector:toString()
    end
    
    if self.targetVector then
        message = message .. ' with targetVector ' .. self.targetVector:toString()
    end
    cpuLog(message)
end

function ActionPanel.copy(self)
    local panel = ActionPanel(self.id, self.color, self.row, self.column)
    if self.cursorStartPos then
        panel.cursorStartPos = GridVector(self.cursorStartPos.row, self.cursorStartPos.column)
    end
    if self.targetVector then
        panel.targetVector = GridVector(self.targetVector.row, self.targetVector.column)
    end
    return panel
end

function ActionPanel.needsToMove(self)
    return not self.vector:equals(self.targetVector)
end

Action =
    class(
    function(action, panels)
        action.panels = panels
        action.garbageValue = 0
        action.stackFreezeValue = 0
        action.estimatedCost = 0
        action.executionPath = nil
        action.isClear = false
        action.name = 'unknown action'
    end
)

function Action.print(self)
    cpuLog('printing ' .. self.name .. ' with estimated cost of ' .. self.estimatedCost)
    if self.panels then
        for i = 1, #self.panels do
            self.panels[i]:print()
        end
    end

    if self.executionPath then
        for i = 1, #self.executionPath do
            cpuLog('element ' .. i .. ' of executionpath is ' .. self.executionPath[i])
        end
    end
end

function Action.getPanelsToMove(self)
    local panelsToMove = {}
    cpuLog('#self.panels has ' .. #self.panels .. ' panels')
    for i = 1, #self.panels do
        cpuLog('printing panel with index ' .. i)
        self.panels[i]:print()

        if self.panels[i]:needsToMove() then
            cpuLog('inserting panel with index ' .. i .. ' into the table')
            table.insert(panelsToMove, self.panels[i])
        else
            cpuLog(' panel with index ' .. i .. ' is already at the desired coordinate, skipping')
        end
    end

    return panelsToMove
end

function Action.sortByDistanceToCursor(self, panels, cursorVec)
    --setting the correct cursor position for starting to work on each panel here
    for i = 1, #panels do
        local panel = panels[i]
        self.setCursorStartPos(panel)
    end

    table.sort(
        panels,
        function(a, b)
            return cursorVec:distance(a.cursorStartPos) < cursorVec:distance(b.cursorStartPos)
        end
    )

    return panels
end

function Action.setCursorStartPos(panel, projectedCoordinate)
    local coordinate = panel.vector

    if projectedCoordinate then
        coordinate = projectedCoordinate
    end

    if coordinate.column > panel.targetVector.column then
        panel.cursorStartPos = GridVector(coordinate.row, coordinate.column - 0.5)
    else
        panel.cursorStartPos = GridVector(coordinate.row, coordinate.column + 0.5)
    end
    cpuLog("Set cursorStartPos for panel " .. panel.id .. " to " .. panel.cursorStartPos:toString())
end

function Action.addCursorMovementToExecution(self, gridVector)
    cpuLog('adding cursor movement to the input queue with vector' .. gridVector:toString())
    --vertical movement
    if math.sign(gridVector.row) == 1 then
        for i = 1, math.abs(gridVector.row) do
            table.insert(self.executionPath, down)
        end
    elseif math.sign(gridVector.row) == -1 then
        for i = 1, math.abs(gridVector.row) do
            table.insert(self.executionPath, up)
        end
    else
        --no vertical movement required
    end

    --horizontal movement
    if math.sign(gridVector.column) == 1 then
        for i = 1, math.abs(gridVector.column) do
            table.insert(self.executionPath, left)
        end
    elseif math.sign(gridVector.column) == -1 then
        for i = 1, math.abs(gridVector.column) do
            table.insert(self.executionPath, right)
        end
    else
        --no vertical movement required
    end
end

function Action.addPanelMovementToExecution(self, gridVector)
    cpuLog('adding panel movement to the input queue with vector' .. gridVector:toString())

    -- always starting with a swap because it is assumed that we already moved into the correct location for the initial swap
    table.insert(self.executionPath, swap)
    --section needs a rework once moving panels between rows are considered
    --vertical movement
    if math.sign(gridVector.row) == 1 then
        for i = 2, math.abs(gridVector.row) do
            table.insert(self.executionPath, up)
            table.insert(self.executionPath, swap)
        end
    elseif math.sign(gridVector.row) == -1 then
        for i = 2, math.abs(gridVector.row) do
            table.insert(self.executionPath, down)
            table.insert(self.executionPath, swap)
        end
    else
        --no vertical movement required
    end

    --horizontal movement
    if math.sign(gridVector.column) == 1 then
        for i = 2, math.abs(gridVector.column) do
            table.insert(self.executionPath, right)
            table.insert(self.executionPath, swap)
        end
    elseif math.sign(gridVector.column) == -1 then
        for i = 2, math.abs(gridVector.column) do
            table.insert(self.executionPath, left)
            table.insert(self.executionPath, swap)
        end
    else
        --no vertical movement required
    end
end

function Action.calculateCost(self)
    error('calculateCost was not implemented for action ' .. self.name)
end

function Action.calculateExecution(self, cursor_row, cursor_col)
    error('calculateExecution was not implemented for action ' .. self.name)
end

--#region Action implementations go here

Raise =
    class(
    function(action)
        Action.init(action)
        action.name = 'Raise'
        action.estimatedCost = 0
        action.executionPath = {raise, wait}
    end,
    Action
)

Move =
    class(
        function(action, stack, panel, targetVector)
            Action.init(action)
            action.name = 'Move'
            action.stack = stack
            action.panel = panel
            action.targetVector = targetVector
            action.panel.targetVector = targetVector
        end,
        Action
    )

    function Move.calculateExecution(self, cursor_row, cursor_col)
        self.executionPath = {}
        cpuLog("cursor_row is " .. cursor_row .. ", cursor_col is " .. cursor_col)
        local cursorVec = GridVector(cursor_row, cursor_col)
        cpuLog("cursorVec is " .. cursorVec:toString())
        
        local generalDirection = self.panel.targetVector.column - self.panel.vector.column
        local movementVec = GridVector(0, (generalDirection / math.abs(generalDirection)) * -1)
        local projectedPos = self.panel.vector

        cpuLog("targetVec is " .. self.panel.targetVector:toString())

        while projectedPos.column ~= self.panel.targetVector.column do
            local moveToPanelVec = cursorVec:difference(projectedPos)
            self:addCursorMovementToExecution(moveToPanelVec)
            self:addPanelMovementToExecution(movementVec)

            -- find out where the panel ended up now
            -- the result of the swap
            projectedPos = projectedPos:substract(movementVec)
            cpuLog("ProjectedPos after swap is " .. projectedPos:toString())
            -- panel is falling down
            for r=projectedPos.row - 1,1,-1 do
                if self.stack.panels[r][projectedPos.column].color == 0 then
                    projectedPos = projectedPos:substract(GridVector(1, 0))
                else
                    break
                end
            end
            cpuLog("ProjectedPos after falling is " .. projectedPos:toString())

            -- update the cursor position for the next round
            cursorVec =
            cursorVec:substract(moveToPanelVec):add(GridVector(0, movementVec.column - math.sign(movementVec.column)))
            cpuLog('next cursor vec is ' .. cursorVec:toString())
        end
    end

Match3 =
    class(
    function(action, panels)
        Action.init(action, panels)
        action.color = panels[1].color
    end,
    Action
)

function Match3.calculateExecution(self, cursor_row, cursor_col)
    cpuLog('calculating execution path for action ' .. self.name)
    self:print()

    self.executionPath = {}

    local panelsToMove = self:getPanelsToMove()
    cpuLog('found ' .. #panelsToMove .. ' panels to move')
    -- cursor_col is the column of the left part of the cursor
    local cursorVec = GridVector(cursor_row, cursor_col)
    cpuLog('cursor vec is ' .. cursorVec:toString())
    while (#panelsToMove > 0) do
        panelsToMove = self:sortByDistanceToCursor(panelsToMove, cursorVec)
        local nextPanel = panelsToMove[1]:copy()
        cpuLog('nextPanel cursorstartpos is ' .. nextPanel.cursorStartPos:toString())
        local moveToPanelVec = cursorVec:difference(nextPanel.cursorStartPos)
        cpuLog('difference vec is ' .. moveToPanelVec:toString())
        self:addCursorMovementToExecution(moveToPanelVec)
        local movePanelVec = GridVector(0, nextPanel.targetVector.column - nextPanel.vector.column)
        cpuLog('panel movement vec is ' .. movePanelVec:toString())
        self:addPanelMovementToExecution(movePanelVec)
        -- update the cursor position for the next round
        cursorVec =
            cursorVec:substract(moveToPanelVec):add(GridVector(0, movePanelVec.column - math.sign(movePanelVec.column)))
        cpuLog('next cursor vec is ' .. cursorVec:toString())
        --remove the panel we just moved so we don't try moving it again
        table.remove(panelsToMove, 1)
        cpuLog(#panelsToMove .. ' panels left to move')
    end

    -- wait at the end of each action to avoid scanning the board again while the last swap is still in progress
    -- or don't cause we have waitFrames now
    --table.insert(self.executionPath, wait)
    cpuLog('exiting calculateExecution')
end

H3Match =
    class(
    function(action, panels)
        Match3.init(action, panels)
        action.name = 'Horizontal 3 Match'
        action.targetRow = 0
    end,
    Match3
)

function H3Match.calculateCost(self)
    cpuLog("calculating cost for action")
    self:print()

    -- always pick the panel in the middle as the one that doesn't need to get moved
    local middlePanelColumn = self.panels[2].vector.column
    self.panels[1].targetVector = GridVector(self.panels[1].vector.row, middlePanelColumn - 1)
    self.panels[2].targetVector = GridVector(self.panels[2].vector.row, middlePanelColumn)
    self.panels[3].targetVector = GridVector(self.panels[3].vector.row, middlePanelColumn + 1)

    self.estimatedCost = 0
    for i = 1, #self.panels do
        local distance = math.abs(self.panels[i].targetVector.column - self.panels[i].vector.column)
        if distance > 0 then
            self.estimatedCost = self.estimatedCost + 2
            self.estimatedCost = self.estimatedCost + distance
        end
    end
end

V3Match =
    class(
    function(action, panels)
        Match3.init(action, panels)
        action.name = 'Vertical 3 Match'
        action.targetColumn = 0
    end,
    Match3
)

function V3Match.calculateCost(self)
    cpuLog("calculating cost for action")
    self:print()
    self:chooseColumn()
end

function V3Match.chooseColumn(self)
    local column
    local minCost = 1000
    for i = 1, 6 do
        local colCost = 0
        for j = 1, #self.panels do
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
    cpuLog('chose targetColumn ' .. self.targetColumn)
    cpuLog('setting target vectors for V3Match ' .. self.targetColumn)
    for i = 1, #self.panels do
        self.panels[i].targetVector = GridVector(self.panels[i].row, self.targetColumn)
        self.panels[i]:print()
    end
end

V4Combo =
    class(
    function(action, panels)
        action.name = 'Vertical 4 Combo'
        action.color = panels[1].color
        action.panels = panels
        action.garbageValue = 0
        action.stackFreezeValue = 0
        action.estimatedCost = 0
        action.executionPath = nil
    end
)

V5Combo =
    class(
    function(action, panels)
        action.name = 'Vertical 5 Combo'
        action.color = panels[1].color
        action.panels = panels
        action.garbageValue = 0
        action.stackFreezeValue = 0
        action.estimatedCost = 0
        action.executionPath = nil
    end
)

T5Combo =
    class(
    function(action, panels)
        action.name = 'T-shaped 5 Combo'
        action.color = panels[1].color
        action.panels = panels
        action.garbageValue = 0
        action.stackFreezeValue = 0
        action.estimatedCost = 0
        action.executionPath = nil
    end
)

L5Combo =
    class(
    function(action, panels)
        action.name = 'L-shaped 5 Combo'
        action.color = panels[1].color
        action.panels = panels
        action.garbageValue = 0
        action.stackFreezeValue = 0
        action.estimatedCost = 0
        action.executionPath = nil
    end
)

T6Combo =
    class(
    function(action, panels)
        action.name = 'T-shaped 6 Combo'
        action.color = panels[1].color
        action.panels = panels
        action.garbageValue = 0
        action.stackFreezeValue = 0
        action.estimatedCost = 0
        action.executionPath = nil
    end
)

T7Combo =
    class(
    function(action, panels)
        action.name = 'T-shaped 7 Combo'
        action.color = panels[1].color
        action.panels = panels
        action.garbageValue = 0
        action.stackFreezeValue = 0
        action.estimatedCost = 0
        action.executionPath = nil
    end
)

--#endregion

--#region Helper classes and functions go here

GridVector =
    class(
    function(vector, row, column)
        vector.row = row
        vector.column = column
    end
)

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

function GridVector.equals(self, otherVec)
    return self.row == otherVec.row and self.column == otherVec.column
end

function GridVector.toString(self)
    return self.row .. '|' .. self.column
end

function GridVector.inRectangle(self, bottomLeft, topRight)
    return self.row >= bottomLeft.row and self.column >= bottomLeft.column and self.row <= topRight.row 
            and self.column <= topRight.column
end

--special meaning of adjacent:
--  -----------
-- x|x x x x x|x
-- x|x       x|x
-- x|x       x|x
--  -----------
-- both inside and outside but not on top
-- technically catches things inside the box too but is not realistic for the usecase
-- maybe a better name would be "safe from rain" as it characterises better which spots are meant
function GridVector.adjacentToRectangle(self, bottomLeft, topRight)
    return self.row <= topRight.row and self.column - 1 <= topRight.column and self.column + 1 >= bottomLeft.column
end

function GridVector.scalarMultiply(self, scalar)
    return GridVector(self.row * scalar, self.column * scalar)
end

function math.sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end

-- a glorified print that can be turned on/off via the cpu configuration
function cpuLog(...)
    if not active_cpuConfig or active_cpuConfig['Log'] then
        print(...)
    end
end

function print_config(someConfig)
    print('print config')
    for key, value in pairs(someConfig) do
        print('\t', key, value)
    end
end

--#endregion

--#region Stackextensions

-- returns the maximum number of panels connected in a MxN rectangle shape
-- where M >= 2 and N >= 3 divided through the total number of panels on the board
-- a panel counts as connected if you can move it along that block without it dropping rows
-- 1 - N_connectedpanels / N_totalpanels
function Stack.getFragmentationPercentage(self)
    local connectedPanels = self:getMaxConnectedTier1PanelsCount()
    local totalPanels = self:getTotalTier1PanelsCount()

    print('total panel count is ' .. totalPanels)
    print('connected panel count is ' .. connectedPanels)

    return 1 - (connectedPanels / totalPanels)
end

--gets all panels in the stack that are in the first tier of the stack
function Stack.getTotalTier1PanelsCount(self)
    local panelCount = 0
    local columns = self:getTier1PanelsAsColumns()

    for i = 1, #columns do
        for j = 1, #columns[i] do
            panelCount = panelCount + 1
        end
    end

    return panelCount
end

-- returns the stack in 6 columns that hold the panels from bottom up
function Stack.getPanelsAsColumns(self)
    local columns = {}
    -- first transforming into a column representation
    if self.panels and self.panels[1] then
        for i = 1, #self.panels[1] do
            columns[i] = {}
            for j = 1, #self.panels do
                local panel = self.panels[j][i]
                columns[i][j] = ActionPanel(panel.id, panel.color, j, i)
            end
        end
    end
    return columns
end

-- returns the stack in 6 columns that hold the panels from bottom up until reaching the first garbage panel
-- for that reason at times it may not actually be the entire first tier if a low combo garbage blocks early and has panels on top
function Stack.getTier1PanelsAsColumns(self)
    -- first transforming into a column representation
    local columns = self:getPanelsAsColumns()

    -- cut out everything 0 and everything that is behind a 9
    for i =1, #columns do
        for j = #columns[i], 1,-1 do
            if columns[i][j].color == 0 then
                table.remove(columns[i], j)
            elseif columns[i][j].color == 9 then
                for k = #columns[i],j,-1 do
                    table.remove(columns[i], k)
                end
            end
        end
    end

    return columns
end

-- returns the maximum number of panels connected in a MxN rectangle shape in the first tier of the stack
-- where M >= 2 and N >= 3
-- a panel counts as connected if you can move it along that block without it dropping rows
function Stack.getMaxConnectedTier1PanelsCount(self)
    local maximumConnectedPanelCount = 0

    local panelSections = self:getTier1ConnectedPanelSections()

    for i=1,#panelSections do
        maximumConnectedPanelCount = math.max(maximumConnectedPanelCount, panelSections[i].numberOfPanels)
    end

    return maximumConnectedPanelCount
end

-- returns all sections of connected panels that are at least 2x3 in size
-- a panel counts as connected if you can move it along that section without it dropping rows
-- includes sections that are fully part of other sections, no duplicates
function Stack.getTier1ConnectedPanelSections(self)
    local columns = self:getTier1PanelsAsColumns()
    local connectedPanelSections = {}

    for i = 1, #columns - 1 do
        local baseHeight = #columns[i]
        cpuLog('column ' .. i .. ' with a height of ' .. baseHeight)

        --match with height = baseHeight - 1 and heigh = baseHeight
        for height = baseHeight - 1, baseHeight do
            if alreadyExists ~= true then
                local connectedPanelCount = baseHeight
                local colsToTheLeft = 0
                local colsToTheRight = 0
                for k = i - 1, 1, -1 do
                    -- from column i to the left side of the board
                    if columns[k] and #columns[k] >= height then
                        connectedPanelCount = connectedPanelCount + math.min(height + 1, #columns[k])
                        colsToTheLeft = colsToTheLeft + 1
                    else
                        break
                    end
                end

                -- from column i to the right side of the board
                for k = i + 1, #columns do
                    if columns[k] and #columns[k] >= height then
                        connectedPanelCount = connectedPanelCount + math.min(height + 1, #columns[k])
                        colsToTheRight = colsToTheRight + 1
                    else
                        break
                    end
                end

                local cols = 1 + colsToTheLeft + colsToTheRight
                cpuLog("Found " .. cols .. " columns around column " .. i .. " with a height of >= " .. height)

                if cols >= 2 and (connectedPanelCount / cols) > 2 then
                    --suffices the 2x3 criteria

                    --add all valid subsections in the section
                    for c=cols,2,-1 do
                        for rows=height+1,3,-1 do
                            for col_offset=i - colsToTheLeft,i - colsToTheLeft + (cols - c) do
                                
                                local startCol = col_offset
                                local endCol = col_offset + c - 1 -- -1 because the col range is [], not [)
                                local bottomLeft = GridVector(1, startCol)
                                local topRight = GridVector(rows, endCol)

                                local alreadyExists = false
                                -- but only those that don't exist yet
                                for n=1,#connectedPanelSections do
                                    if connectedPanelSections[n].bottomLeftVector:equals(bottomLeft) and connectedPanelSections[n].topRightVector:equals(topRight) then
                                        alreadyExists = true
                                        break
                                    end
                                end

                                if alreadyExists == false then
                                    -- count the panels
                                    cpuLog("Counting panels for subsection " .. bottomLeft:toString() .. "," .. topRight:toString())
                                    cpuLog("c: " .. c .. ",rows: " .. rows .. ",startCol: " .. startCol .. ",endCol: " .. endCol .. ",col_offset: " .. col_offset)
                                    local panelCount = 0
                                    for l=startCol,endCol do
                                        panelCount = panelCount + math.min(rows, #columns[l])
                                    end
                
                                    table.insert(connectedPanelSections,
                                    ConnectedPanelSection(bottomLeft, topRight,
                                                          panelCount, self.panels))
                                end

                            end
                        end
                    end
                end
            end      
        end
    end

    return connectedPanelSections
end

ConnectedPanelSection = class(function(panelSection, bottomLeftVector, topRightVector, numberOfPanels, panels)
    panelSection.bottomLeftVector = bottomLeftVector
    panelSection.topRightVector = topRightVector
    panelSection.numberOfPanels = numberOfPanels
    panelSection.panels = {}

    for i=bottomLeftVector.row,topRightVector.row do
        for j=bottomLeftVector.column,topRightVector.column do
            table.insert(panelSection.panels, panels[j][i])
        end
    end
end)

function ConnectedPanelSection.print(self)
    cpuLog("ConnectedPanelSection with anchors " .. self.bottomLeftVector:toString() .. ", " .. self.topRightVector:toString() 
            .. " containing a total of " .. self.numberOfPanels .. " panels")
end

--#endregion
