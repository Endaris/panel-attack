local Scene = require("scenes.Scene")
local TextButton = require("ui.TextButton")
local Label = require("ui.Label")
local consts = require("consts")
local Menu = require("ui.Menu")
local MenuItem = require("ui.MenuItem")
local sceneManager = require("scenes.sceneManager")
local GraphicsUtil = require("graphics_util")
local class = require("class")
local GameModes = require("GameModes")
local EndlessMenu = require("scenes.EndlessMenu")
local PuzzleMenu = require("scenes.PuzzleMenu")
local TimeAttackMenu = require("scenes.TimeAttackMenu")
local CharacterSelectVsSelf = require("scenes.CharacterSelectVsSelf")
local TrainingMenu = require("scenes.TrainingMenu")
local ChallengeModeMenu = require("scenes.ChallengeModeMenu")
local Lobby = require("scenes.Lobby")
local CharacterSelect2p = require("scenes.CharacterSelect2p")
local ReplayBrowser = require("scenes.ReplayBrowser")
local InputConfigMenu = require("scenes.InputConfigMenu")
local SetNameMenu = require("scenes.SetNameMenu")
local OptionsMenu = require("scenes.OptionsMenu")
local DesignHelper = require("scenes.DesignHelper")


-- @module MainMenu
-- Scene for the main menu
local MainMenu = class(function(self, sceneParams)
  self.menu = nil -- set in load
  self.backgroundImg = themes[config.theme].images.bg_main
  self:load(sceneParams)
end, Scene)

MainMenu.name = "MainMenu"
sceneManager:addScene(MainMenu)

local function switchToScene(sceneName, transition)
  Menu.playValidationSfx()
  sceneManager:switchToScene(sceneName, transition)
end

function MainMenu:createMainMenu()

  local menuItems = {MenuItem.createButtonMenuItem("mm_1_endless", nil, nil, function()
      GAME.battleRoom = BattleRoom.createLocalFromGameMode(GameModes.getPreset("ONE_PLAYER_ENDLESS"))
      switchToScene(EndlessMenu())
    end), 
    MenuItem.createButtonMenuItem("mm_1_puzzle", nil, nil, function()
      GAME.battleRoom = BattleRoom.createLocalFromGameMode(GameModes.getPreset("ONE_PLAYER_PUZZLE"))
      switchToScene(PuzzleMenu())
    end),
    MenuItem.createButtonMenuItem("mm_1_time", nil, nil, function()
      GAME.battleRoom = BattleRoom.createLocalFromGameMode(GameModes.getPreset("ONE_PLAYER_TIME_ATTACK"))
      switchToScene(TimeAttackMenu())
    end),
    MenuItem.createButtonMenuItem("mm_1_vs", nil, nil, function()
      GAME.battleRoom = BattleRoom.createLocalFromGameMode(GameModes.getPreset("ONE_PLAYER_VS_SELF"))
      switchToScene(CharacterSelectVsSelf())
    end),
    MenuItem.createButtonMenuItem("mm_1_training", nil, nil, function()
      GAME.battleRoom = BattleRoom.createLocalFromGameMode(GameModes.getPreset("ONE_PLAYER_TRAINING"))
      switchToScene(TrainingMenu())
    end),
    MenuItem.createButtonMenuItem("mm_1_challenge_mode", nil, nil, function()
      switchToScene(ChallengeModeMenu())
    end),
    MenuItem.createButtonMenuItem("mm_2_vs_online", {""}, nil, function()
      switchToScene(Lobby({serverIp = "panelattack.com"}))
    end),
    MenuItem.createButtonMenuItem("mm_2_vs_local", nil, nil, function()
      local battleRoom = BattleRoom.createLocalFromGameMode(GameModes.getPreset("TWO_PLAYER_VS"))
      if not battleRoom.hasShutdown then
        GAME.battleRoom = battleRoom
        switchToScene(CharacterSelect2p())
      end
    end),
    MenuItem.createButtonMenuItem("mm_replay_browser", nil, nil, function()
      switchToScene(ReplayBrowser())
    end),
    MenuItem.createButtonMenuItem("mm_configure", nil, nil, function()
      switchToScene(InputConfigMenu())
    end),
    MenuItem.createButtonMenuItem("mm_set_name", nil, nil, function()
      switchToScene(SetNameMenu())
    end),
    MenuItem.createButtonMenuItem("mm_options", nil, nil, function()
      switchToScene(OptionsMenu())
    end),
    MenuItem.createButtonMenuItem("mm_fullscreen", {"\n(Alt+Enter)"}, nil, function()
      Menu.playValidationSfx()
      love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    end),
    MenuItem.createButtonMenuItem("mm_quit", nil, nil, function() love.event.quit() end )
  }

  local menu = Menu.createCenteredMenu(menuItems)

  local debugMenuItems = {MenuItem.createButtonMenuItem("Beta Server", nil, nil, function() switchToScene(Lobby({serverIp = "betaserver.panelattack.com", serverPort = 59569})) end),
                          MenuItem.createButtonMenuItem("Localhost Server", nil, nil, function() switchToScene(Lobby({serverIp = "Localhost"})) end)
                        }

  local function addDebugMenuItems()
    if config.debugShowServers then
      for i, menuItem in ipairs(debugMenuItems) do
        menu:addMenuItem(i + 7, menuItem)
      end
    end
    if config.debugShowDesignHelper then
      menu:addMenuItem(#menu.menuItems, MenuItem.createButtonMenuItem("Design Helper", nil, nil, function()
          switchToScene(DesignHelper())
        end))
    end
  end

  local function removeDebugMenuItems()
    for i, menuItem in ipairs(debugMenuItems) do
      menu:removeMenuItem(menuItem[1].id)
    end
  end

  addDebugMenuItems()
  return menu
end

function MainMenu:load(sceneParams)
  self.menu = self:createMainMenu()
  self.uiRoot:addChild(self.menu)

  SoundController:playMusic(themes[config.theme].stageTracks.main)
  GAME.tcpClient:resetNetwork()
  GAME.battleRoom = nil
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
  self.menu:update(dt)
end

function MainMenu:draw()
  self.backgroundImg:draw()
  self.uiRoot:draw()
  local fontHeight = GraphicsUtil.getGlobalFont():getHeight()
  local infoYPosition = 705 - fontHeight / 2

  local loveString = GAME:loveVersionString()
  if loveString == "11.3.0" then
    GraphicsUtil.printf(loc("love_version_warning"), -5, infoYPosition, consts.CANVAS_WIDTH, "right")
    infoYPosition = infoYPosition - fontHeight
  end

  if GAME_UPDATER_GAME_VERSION then
    GraphicsUtil.printf("PA Version: " .. GAME_UPDATER_GAME_VERSION, -5, infoYPosition, consts.CANVAS_WIDTH, "right")
    infoYPosition = infoYPosition - fontHeight
    if has_game_update then
      GraphicsUtil.draw(panels[config.panels].images.classic[1][1], 1262, 685)
    end
  end
end

return MainMenu
