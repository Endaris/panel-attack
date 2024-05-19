local DirectTransition = require("client.src.scenes.Transitions.DirectTransition")

local NavigationStack = {
  scenes = {},
  transition = nil,
}

function NavigationStack:push(newScene, transition)
  local activeScene = self.scenes[#self.scenes]
  if not transition then
    transition = DirectTransition(activeScene, newScene)
  end
  self.transition = transition
  self.scenes[#self.scenes+1] = newScene
end

function NavigationStack:pop(transition)
  local activeScene = self.scenes[#self.scenes]
  local previousScene = self.scenes[#self.scenes - 1]

  if not transition then
    transition = DirectTransition(activeScene, previousScene)
  end

  self.transition = transition
  table.remove(self.scenes)
end

function NavigationStack:popToTop(transition)
  local activeScene = self.scenes[#self.scenes]
  local top = self.scenes[1]
  
  if not transition then
    transition = DirectTransition(activeScene, top)
  end

  self.transition = transition
  for i = #self.scenes, 2, -1 do
    self.scenes[i] = nil
  end
end

function NavigationStack:replace(newScene, transition)
  local activeScene = self.scenes[#self.scenes]
  if not transition then
    transition = DirectTransition(activeScene, newScene)
  end
  self.transition = transition
  self.scenes[#self.scenes] = newScene
end

function NavigationStack:update(dt)
  if self.transition then
    self.transition:update(dt)

    if self.transition.progress >= 1 then
      self.transition = nil
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