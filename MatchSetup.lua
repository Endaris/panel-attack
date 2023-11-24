local class = require("class")
local tableUtils = require("tableUtils")
local GameModes = require("GameModes")
local sceneManager = require("scenes.sceneManager")
local Replay = require("replay")
local Player = require("Player")

local MatchSetup = class(function(match, mode, online, localPlayerNumber)
  match.mode = mode
  if mode.style == GameModes.Styles.CHOOSE then
    if config.endless_level then
      match.style = GameModes.Styles.MODERN
    else
      match.style = GameModes.Styles.CLASSIC
    end
  else
    match.style = match.mode.style
  end

  match.online = online
  match.localPlayerNumber = localPlayerNumber

  match.players = {}
end)

function MatchSetup:updateLocalConfig(playerNumber)
  -- update config, does not redefine it
  local player = self.players[playerNumber]
  config.character = player.characterId
  config.stage = player.stageId
  config.level = player.level
  config.inputMethod = player.inputMethod
  config.ranked = player.ranked
  config.panels = player.panelId
end

function MatchSetup:setPuzzleFile(puzzleFile, player)
  if not player and self.mode.playerCount == 1 then
    player = 1
  end

  if self.mode.selectFile == GameModes.FileSelection.Puzzle then
    self.players[player].puzzleFile = puzzleFile
    self:onPropertyChanged("puzzleFile", player)
  else
    error("Trying to set a puzzle file in a game mode that doesn't support puzzle file selection")
  end
end

function MatchSetup:setTrainingFile(player, trainingFile)
  if not player and self.mode.playerCount == 1 then
    player = 1
  end

  if self.mode.selectFile == GameModes.FileSelection.Training then
    self.players[player].trainingFile = trainingFile
    self:onPropertyChanged("trainingFile", player)
  else
    error("Trying to set a training file in a game mode that doesn't support training file selection")
  end
end

return MatchSetup
