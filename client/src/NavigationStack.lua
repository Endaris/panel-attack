local DirectTransition = require("client.src.scenes.Transitions.DirectTransition")

local NavigationStack = {
  scenes = {},
  transition = nil,
  callback = nil,
}

function NavigationStack:push(newScene, transition)
  local activeScene = self.scenes[#self.scenes]

  if not transition then
    transition = DirectTransition()
  end
  transition.oldScene = activeScene
  transition.newScene = newScene

  self.transition = transition
  self.scenes[#self.scenes+1] = newScene
end

-- transitions to the previous scene optionally using a specified transition
-- an optional callback may be passed that is called when the transition completed
function NavigationStack:pop(transition, callback)
  if #self.scenes > 1 then
    local activeScene = self.scenes[#self.scenes]
    local previousScene = self.scenes[#self.scenes - 1]

    if not transition then
      transition = DirectTransition()
    end
    transition.oldScene = activeScene
    transition.newScene = previousScene

    self.transition = transition
    self.callback = callback
    table.remove(self.scenes)
  end
end

-- transitions to the bottom most scene in the stack optionally using a specified transition
-- usually this will be MainMenu
-- an optional callback may be passed that is called when the transition completed
function NavigationStack:popToTop(transition, callback)
  if #self.scenes > 1 then
    local activeScene = self.scenes[#self.scenes]
    local top = self.scenes[1]

    if not transition then
      transition = DirectTransition()
    end
    transition.oldScene = activeScene
    transition.newScene = top

    self.transition = transition
    self.callback = callback

    for i = #self.scenes, 2, -1 do
      self.scenes[i] = nil
    end
  end
end

-- transitions to the newScene, optionally using a specified transition while removing the current scene from the stack
-- an optional callback may be passed that is called when the transition completed
function NavigationStack:replace(newScene, transition, callback)
  local activeScene = self.scenes[#self.scenes]

  if not transition then
    transition = DirectTransition()
  end
  transition.oldScene = activeScene
  transition.newScene = newScene

  self.transition = transition
  self.callback = callback
  self.scenes[#self.scenes] = newScene
end

function NavigationStack:update(dt)
  if self.transition then
    self.transition:update(dt)

    if self.transition.progress >= 1 then
      self.transition = nil
      if self.callback then
        self.callback()
        self.callback = nil
      end
    end
  else
    if #self.scenes == 0 then
      error("There better be an active scene. We bricked.")
    end
    self.scenes[#self.scenes]:update(dt)
  end
end

function NavigationStack:draw()
  if self.transition then
    self.transition:draw()
  else
    if #self.scenes == 0 then
      error("There better be an active scene. We bricked.")
    end
    self.scenes[#self.scenes]:draw()
  end
end

return NavigationStack