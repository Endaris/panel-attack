local class = require("common.lib.class")
local Transition = require("client.src.scenes.Transitions.Transition")

local DirectTransition = class(function(transition, oldScene, newScene, startTime, duration)
end,
Transition)

function DirectTransition:draw()
  self.oldScene:draw()
end

return DirectTransition
