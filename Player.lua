local class = require("class")

local Player = class(function(self, name, publicId, battleRoom, isLocal)
  self.name = name
  self.wins = 0
  self.modifiedWins = 0
  self.settings = {}
  self.publicId = publicId
  self.trainingModeSettings = nil
  self.rating = nil
  self.stack = nil
  self.battleRoom = battleRoom
  self.playerNumber = 1
  self.isLocal = isLocal or false
  self.inputConfiguration = nil
end)

function Player:getWinCount()
  return self.wins + self.modifiedWins
end

function Player:createStackFromSettings()
  local args = {}
  args.which = self.playerNumber
  args.player_number = self.playerNumber
  args.match = self.battleRoom.match
  args.is_local = self.isLocal
  args.panels_dir = self.settings.panelId
  args.character = self.settings.characterId
  if self.settings.level then
    args.level = self.settings.level
  else
    args.difficulty = self.settings.difficulty
    args.speed = self.settings.speed
  end

  self.stack = Stack(args)

  return self.stack
end