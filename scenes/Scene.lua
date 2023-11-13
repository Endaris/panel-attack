local class = require("class")

--@module Scene
-- Base class for a container representing a single screen of PanelAttack.
-- Each scene needs to be registered in Game.lua 
-- Each scene also needs to add a field called <Scene>.name = <Scene>
-- and call sceneManager.addScene(<Scene>)
local Scene = class(
  function (self, sceneParams)
  end
)

-- abstract functions to be implemented per scene

-- Ran every time the scene is started
-- used to setup the state of the scene before running
function Scene:load(sceneParams) end

-- Ran every frame while the scene is active
function Scene:update() end

-- Ran every frame before anything is drawn
function Scene:drawBackground() end

-- Ran every frame after everything is drawn
function Scene:drawForeground() end

-- Ran every time the scene is ending
-- used to clean up resources/global state used within the scene (stopping audio, hiding menus, etc.)
function Scene:unload() end

return Scene