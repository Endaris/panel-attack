local class = require("class")
local tableUtils = require("tableUtils")
local GameModes = require("GameModes")
local sceneManager = require("scenes.sceneManager")
local Replay = require("replay")
local Player = require("Player")

local MatchSetup = class(function(match, mode, online, localPlayerNumber)
  match.mode = mode
  match:initializeSubscriptionList()
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

function MatchSetup:setRating(rating, player)
  if not player and self.mode.playerCount == 1 then
    player = 1
  end

  if self.players[player].rating.new then
    self.players[player].rating.old = self.players[player].rating.new
  end
  self.players[player].rating.new = rating

  self:onPropertyChanged("rating", player)
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

function MatchSetup:setStyle(styleChoice)
  -- not sure if style should be configurable per player, doesn't seem to make sense
  if self.mode.style == GameModes.Styles.CHOOSE then
    self.style = styleChoice
    self.onStyleChanged(styleChoice)
  else
    error("Trying to set difficulty style in a game mode that doesn't support style selection")
  end
end

-- not player specific, so this gets a separate callback that can only be overwritten once
function MatchSetup.onStyleChanged(style, player)
end

function MatchSetup:setDifficulty(difficulty, player)
  if not player and self.mode.playerCount == 1 then
    player = 1
  end

  if self.style == GameModes.Styles.CLASSIC then
    self.players[player].difficulty = difficulty
    self:onPropertyChanged("difficulty", player)
  else
    error("Trying to set difficulty while a non-classic style was selected")
  end
end

function MatchSetup:setWinCount(winCount, player)
  if self.mode.playerCount > 1 then
    self.players[player].winCount = winCount
    self:onPropertyChanged("winCount", player)
  else
    error("Trying to set win count in one player modes")
  end
end

function MatchSetup:refreshReadyStates()
  for playerNumber = 1, #self.players do
    self.players[playerNumber].ready = tableUtils.trueForAll(self.players, function(pc)
      return pc.hasLoaded and pc.wantsReady
    end)
  end
end

function MatchSetup:allReady()
  for playerNumber = 1, #self.players do
    if not self.players[playerNumber].ready then
      return false
    end
  end

  return true
end

function MatchSetup:updateRankedStatus(rankedStatus, comments)
  if self.online and self.mode.selectRanked and rankedStatus ~= self.ranked then
    self.ranked = rankedStatus
    self.rankedComments = comments
    -- legacy crutches
    if self.ranked then
      match_type = "Ranked"
    else
      match_type = "Casual"
    end
  else
    error("Trying to apply ranked state to the match even though it is either not online or does not support ranked")
  end
end

function MatchSetup:abort()
  self.abort = true
end

function MatchSetup:startMatch(stageId, seed, replayOfMatch)
  -- lock down configuration to one per player to avoid macro like abuses via multiple configs
  -- if self.online and self.localPlayerNumber then
  --   GAME.input:requestSingleInputConfigurationForPlayerCount(1)
  -- elseif not self.online then
  --   GAME.input:requestSingleInputConfigurationForPlayerCount(#self.players)
  -- end

  if not GAME.battleRoom then
    GAME.battleRoom = BattleRoom(self.mode)
  end
  GAME.match = GAME.battleRoom:createMatch()

  GAME.match:setStage(stageId)
  GAME.match:setSeed(seed)

  if match_type == "Ranked" and not GAME.match.room_ratings then
    GAME.match.room_ratings = {}
  end

  GAME.match:start(replayOfMatch)

  replay = Replay.createNewReplay(GAME.match)
  -- game dies when using the fade transition for unclear reasons
  sceneManager:switchToScene(self.mode.scene, {}, "none")
end

function MatchSetup:updateLoadingState()
  local fullyLoaded = true
  for i = 1, #self.players do
    if not characters[self.players[i].characterId].fully_loaded or not stages[self.players[i].stageId].fully_loaded then
      fullyLoaded = false
    end
  end

  for i = 1, #self.players do
    -- only need to update for local players, network will update us for others
    if self.players[i].isLocal then
      self:setLoaded(fullyLoaded, i)
    end
  end
end

function MatchSetup:update()
  -- here we fetch network updates and update the match setup if applicable

  -- if there are still unloaded assets, we can load them 1 asset a frame in the background
  StageLoader.update()
  CharacterLoader.update()

  self:updateLoadingState()
  self:refreshReadyStates()
  if self:allReady() then
    self:startMatch()
  end
end

return MatchSetup
