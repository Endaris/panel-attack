local Scene = require("scenes.Scene")
local Button = require("ui.Button")
local consts = require("consts")
local Menu = require("ui.Menu")
local sceneManager = require("scenes.sceneManager")
local replay_browser = require("replay_browser")
local options = require("options")
local GraphicsUtil = require("graphics_util")
local class = require("class")

-- need to load the existing global scene functions until they get ported to scenes
require("mainloop")

--@module MainMenu
-- Scene for the main menu
local MainMenu = class(
  function (self, sceneParams)
    self:init()
    self:load(sceneParams)
  end,
  Scene
)

MainMenu.name = "MainMenu"
sceneManager:addScene(MainMenu)

local showDebugServers = config.debugShowServers

local function genLegacyMainloopFn(myFunction, args)
  local onClick = function()
    func = myFunction
    arg = args
    Menu.playValidationSfx()
    sceneManager:switchToScene(nil)
  end
  return onClick
end

local function switchToScene(scene)
  Menu.playValidationSfx()
  sceneManager:switchToScene(scene)
end

local BUTTON_WIDTH = 140
local function createMainMenuButton(label, onClick, extra_labels, translate)
  if translate == nil then
    translate = true
  end
  return Button({label = label, extra_labels = extra_labels, translate = translate, onClick = onClick, width = BUTTON_WIDTH})
end

local menuItems = {
  {createMainMenuButton("mm_1_endless", function() switchToScene("EndlessMenu") end)},
  {createMainMenuButton("mm_1_puzzle", function() switchToScene("PuzzleMenu") end)},
  {createMainMenuButton("mm_1_time", function() switchToScene("TimeAttackMenu") end)},
  {createMainMenuButton("mm_1_vs", genLegacyMainloopFn(main_local_vs_yourself_setup))},
  {createMainMenuButton("mm_1_training", genLegacyMainloopFn(training_setup))},
  {createMainMenuButton("mm_2_vs_online", genLegacyMainloopFn(main_net_vs_setup, {"18.188.43.50"}),  {""})},
  {createMainMenuButton("mm_2_vs_local", genLegacyMainloopFn(main_local_vs_setup))},
  {createMainMenuButton("mm_replay_browser", function() switchToScene("ReplayBrowser") end)},
  {createMainMenuButton("mm_configure", function() switchToScene("InputConfigMenu") end)},
  {createMainMenuButton("mm_set_name", function() Menu.playValidationSfx() sceneManager:switchToScene("SetNameMenu", {prevScene = "MainMenu"}) end)},
  {createMainMenuButton("mm_options", function() switchToScene("OptionsMenu") end)},
  {createMainMenuButton("mm_fullscreen", function() Menu.playValidationSfx() fullscreen() end, {"\n(LAlt+Enter)"})},
  {createMainMenuButton("mm_quit", love.event.quit)}
}

local debugMenuItems = {
  {createMainMenuButton("Beta Server", genLegacyMainloopFn(main_net_vs_setup, {"betaserver.panelattack.com", 59569}),  {""}, false)},
  {createMainMenuButton("Localhost Server", genLegacyMainloopFn(main_net_vs_setup, {"localhost"}),  {""}, false)}
}

function MainMenu:addDebugMenuItems()
  for i, menuItem in ipairs(debugMenuItems) do
    self.menu:addMenuItem(i + 7, menuItem)
  end
end

function MainMenu:removeDebugMenuItems()
  for i, menuItem in ipairs(debugMenuItems) do
    self.menu:removeMenuItem(menuItem[1].id)
  end
end

function MainMenu:init()
  self.menu = Menu({menuItems = menuItems, maxHeight = themes[config.theme].main_menu_max_height})
  self.menu:setVisibility(false)
  
  if showDebugServers then
    self:addDebugMenuItems()
  end
end

function MainMenu:load(sceneParams)
  local x, y = unpack(themes[config.theme].main_menu_screen_pos)
  self.menu.x = (consts.CANVAS_WIDTH / 2) - BUTTON_WIDTH / 2
  self.menu.y = y
  
  self.backgroundImg = themes[config.theme].images.bg_main
  if themes[config.theme].musics["main"] then
    find_and_add_music(themes[config.theme].musics, "main")
  end
  character_loader_clear()
  stage_loader_clear()
  resetNetwork()
  GAME.battleRoom = nil
  GAME.input:clearInputConfigurationsForPlayers()
  GAME.input:requestPlayerInputConfigurationAssignments(1)
  reset_filters()
  match_type_message = ""
  
  if showDebugServers ~= config.debugShowServers then
    if config.debugShowServers then
      self:addDebugMenuItems()
    else
      self:removeDebugMenuItems()
    end
    showDebugServers = config.debugShowServers
  end
  
  self.menu:updateLabel()
  self.menu:setVisibility(true)
end

function MainMenu:drawBackground()
  self.backgroundImg:draw()
end

function MainMenu:update(dt)
  if wait_game_update ~= nil then
    has_game_update = wait_game_update:pop()
    if has_game_update ~= nil and has_game_update then
      wait_game_update = nil
      GAME_UPDATER_GAME_VERSION = "NEW VERSION FOUND! RESTART THE GAME!"
    end
  end

  self.backgroundImg:update(dt)
  local fontHeight = GraphicsUtil.getGlobalFont():getHeight()
  local infoYPosition = 705 - fontHeight/2

  local loveString = GAME:loveVersionString()
  if loveString == "11.3.0" then
    gprintf(loc("love_version_warning"), -5, infoYPosition, canvas_width, "right")
    infoYPosition = infoYPosition - fontHeight
  end

  if GAME_UPDATER_GAME_VERSION then
    gprintf("PA Version: " .. GAME_UPDATER_GAME_VERSION, -5, infoYPosition, canvas_width, "right")
    infoYPosition = infoYPosition - fontHeight
    if has_game_update then
      menu_draw(panels[config.panels].images.classic[1][1], 1262, 685)
    end
  end
  
  self.menu:update()
  self.menu:draw()
end

function MainMenu:unload()
  self.menu:setVisibility(false)
end

return MainMenu