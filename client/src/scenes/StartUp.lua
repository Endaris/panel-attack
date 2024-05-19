local class = require("common.lib.class")
local Scene = require("client.src.scenes.Scene")
local consts = require("common.engine.consts")
local GraphicsUtil = require("client.src.graphics.graphics_util")
local TitleScreen = require("client.src.scenes.TitleScreen")
local MainMenu = require("client.src.scenes.MainMenu")

local StartUp = class(function(scene, sceneParams)
  scene.run = coroutine.wrap(sceneParams.setupRoutine)
  -- the wrapping functions returns its coroutine on the first yield
  scene.setupRoutine = scene.run(GAME)
  scene.message = "Startup"
end, Scene)

StartUp.name = "StartUp"

function StartUp:update(dt)
  local status = self.run(GAME)

  if status then
    self.message = status
  end

  if coroutine.status(self.setupRoutine) == "dead" then
    if themes[config.theme].images.bg_title then
      GAME.navigationStack:replace(TitleScreen())
    else
      GAME.navigationStack:replace(MainMenu())
    end
  end
end

function StartUp:drawLoadingString(loadingString)
  local textHeight = 40
  local x = 0
  local y = consts.CANVAS_HEIGHT / 2 - textHeight / 2
  love.graphics.setFont(GraphicsUtil.getGlobalFontWithSize(GraphicsUtil.fontSize + 10))
  GraphicsUtil.setColor(1, 1, 1, 1)
  love.graphics.printf(loadingString, x, y, consts.CANVAS_WIDTH, "center", 0, 1)
  love.graphics.setFont(GraphicsUtil.getGlobalFont())
end

function StartUp:draw()
  self:drawLoadingString(self.message)
end

return StartUp
