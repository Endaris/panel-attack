local class = require("class")
local GameModes = require("GameModes")

local Player = class(function(self, name, publicId, isLocal)
  self.name = name
  self.wins = 0
  self.modifiedWins = 0
  self.settings = {}
  self.publicId = publicId
  self.trainingModeSettings = nil
  self.rating = nil
  self.stack = nil
  self.playerNumber = nil
  self.isLocal = isLocal or false
  self.inputConfiguration = nil
  self.subscriptionList = {}
end)

function Player:getWinCount()
  return self.wins + self.modifiedWins
end

function Player:createStackFromSettings(match, wantsCanvas)
  local args = {}
  args.which = self.playerNumber
  args.player_number = self.playerNumber
  args.match = match
  args.is_local = self.isLocal
  args.panels_dir = self.settings.panelId
  args.character = self.settings.characterId
  if self.settings.level then
    args.level = self.settings.level
  else
    args.difficulty = self.settings.difficulty
    args.speed = self.settings.speed
  end
  args.inputMethod = self.settings.inputMethod
  args.wantsCanvas = wantsCanvas or false

  self.stack = Stack(args)

  return self.stack
end

function Player:getRatingDiff()
  return self.rating.new - self.rating.old
end

-- Ui Elements can subscribe to properties by passing a callback 
function Player:subscribe(property, callback)
  if self[property] then
    if not self.subscriptionList[property] then
      self.subscriptionList[property] = {}
    end
    self.subscriptionList[property][#self.subscriptionList[property] + 1] = callback
    return true
  end

  return false
end

-- the callback is executed with the new property value as the argument whenever the property is modified for the player
function Player:onPropertyChanged(property)
  if self.subscriptionList[property] then
    for i = 1, #self.subscriptionList[property] do
      self.subscriptionList[property][i](self.settings[property])
    end
  end
end

function Player:setStage(stageId)
  if stageId ~= self.settings.stageId then
    stageId = StageLoader.resolveStageSelection(stageId)
    self.settings.stageId = stageId
    StageLoader.load(stageId)

    self:onPropertyChanged("stageId")
  end
end

function Player:setCharacter(characterId)
  if characterId ~= self.settings.characterId then
    characterId = CharacterLoader.resolveCharacterSelection(characterId)
    self.settings.characterId = characterId
    CharacterLoader.load(characterId)

    self:onPropertyChanged("characterId")
  end
end

function Player:setPanels(panelId)
  if panelId ~= self.settings.panelId then
    if panels[panelId] then
      self.settings.panelId = panelId
    else
      -- default back to config panels always
      self.settings.panelId = config.panels
    end
    -- panels are always loaded so no loading is necessary

    self:onPropertyChanged("panelId")
  end
end

function Player:setRanked(wantsRanked)
  if wantsRanked ~= self.settings.wantsRanked then
    self.settings.wantsRanked = wantsRanked
    self:onPropertyChanged("wantsRanked")
  end
end

function Player:setWantsReady(wantsReady)
  if wantsReady ~= self.settings.wantsReady then
    self.settings.wantsReady = wantsReady
    self:onPropertyChanged("wantsReady")
  end
end

function Player:setLoaded(hasLoaded)
  if hasLoaded ~= self.settings.hasLoaded then
    self.settings.hasLoaded = hasLoaded
    self:onPropertyChanged("hasLoaded")
  end
end

function Player:setDifficulty(difficulty)
  if difficulty ~= self.settings.difficulty then
    self.settings.difficulty = difficulty
    self:onPropertyChanged("difficulty")
  end
end

function Player:setSpeed(speed)
  if speed ~= self.settings.speed then
    self.settings.speed = speed
    self:onPropertyChanged("speed")
  end
end

function Player:setLevel(level)
  if level ~= self.settings.level then
    self.settings.level = level
    self:onPropertyChanged("level")
  end
end

function Player:setInputMethod(inputMethod)
  if inputMethod ~= self.settings.inputMethod then
    self.settings.inputMethod = inputMethod
    self:onPropertyChanged("inputMethod")
  end
end

function Player.getLocalPlayer()
  local player = Player(config.name)

  player:setDifficulty(config.endless_difficulty)
  player:setSpeed(config.endless_speed)
  player:setLevel(config.level)
  player:setCharacter(config.character)
  player:setStage(config.stage)
  player:setPanels(config.panels)
  player:setRanked(config.ranked)
  player:setInputMethod(config.inputMethod)

  player.isLocal = true

  return player
end

return Player