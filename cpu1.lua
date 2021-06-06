CPU1 = class(function(cpu, stack)
    cpu.panelsChanged = false
    cpu.cursorChanged = false
    cpu.actions = {}
    cpu.currentAction = nil
    cpu.actionQueue = {}
    cpu.inputQueue = {}
    cpu.moveRateLimit = 10
    cpu.swapRateLimit = 6
    cpu.idleFrames = 0
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
local stealth = 1024

function CPU1.new(self)

end

function CPU1.send_controls(self)
    if #self.inputQueue > 0 and self.idleFrames >= self.moveRateLimit then
        return self.inputQueue[1] + 1
    else
        return 1
    end
end

function CPU1.swap(stack)
    return base64encode[down+swap+1]
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
        table.remove(self.inputQueue, 1)
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

end

function CPU1.estimateCost(self, action)

end

function CPU1.chooseAction(self)

end

function CPU1.panelsToRowGrid(self)
    local panels = self.stack.panels
    local grid = {}
    for i=0,#panels[1] do
        grid[i] = {}
        -- always use 8: shockpanels appear on every level and we want columnnumber=color number for readability
        for j=1,8 do
            local count = 0
            for k = 1,6 do
                if panels[i][k] == j then
                    count = count + 1
                end
            end
            grid[i][j] = count
        end
    end
    return grid
end
