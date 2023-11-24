
local logger = require("logger")
local Player = require("Player")

-- A Battle Room is a session of vs battles, keeping track of the room number, wins / losses etc
BattleRoom =
  class(
  function(self, mode, roomData)
    assert(mode)
    self.mode = mode
    self.players = {}
    self.spectators = {}
    self.spectating = false
    self.trainingModeSettings = nil
    if roomData then
      -- this could come from online or replay
      if roomData.replayVersion then
        -- coming from a replay
        for i = 1, #roomData.players do
          local rpp = roomData.players[i]
          local player = Player(rpp.name, rpp.publicId)
          player.playerNumber = i
          player.wins = rpp.wins
          player.settings.panelId = rpp.settings.panelId
          player.settings.characterId = CharacterLoader.resolveCharacterSelection(rpp.settings.characterId)
          player.settings.inputMethod = rpp.settings.inputMethod
          player.settings.level = rpp.settings.level
          player.settings.difficulty = rpp.settings.difficulty
          --player.settings.levelData = rpp.settings.levelData
          self:addPlayer(player)
        end
      elseif roomData.create_room then
        -- coming from online
      end
    else
      -- no room creation data means the local player is definitely involved
      self:addPlayer(Player.getLocalPlayer())
    end
  end
)

function BattleRoom.updateWinCounts(self, winCounts)
  for i = 1, winCounts do
    self.players[i].wins = winCounts[i]
  end
end

function BattleRoom:totalGames()
  local totalGames = 0
  for i = 1, #self.players do
    totalGames = totalGames + self.players[i].wins
  end
  return totalGames
end

-- Returns the player with more win count.
-- TODO handle ties?
function BattleRoom:winningPlayer()
  if #self.players == 1 then
    return self.players[1]
  else
    if self.players[1].wins >= self.players[2].wins then
      return self.players[1]
    else
      return self.players[2]
    end
  end
end

function BattleRoom:createMatch()
  self.match = Match(self)

  for i = 1, #self.players do
    self.match:addPlayer(self.players[i])
  end

  return self.match
end

function BattleRoom:addNewPlayer(name, publicId, isLocal)
  local player = Player(name, publicId, isLocal)
  player.playerNumber = #self.players+1
  self.players[#self.players+1] = player
  return player
end

function BattleRoom:addPlayer(player)
  player.playerNumber = #self.players+1
  self.players[#self.players+1] = player
end