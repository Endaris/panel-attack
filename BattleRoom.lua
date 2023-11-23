
local logger = require("logger")
local Player = require("Player")

-- A Battle Room is a session of vs battles, keeping track of the room number, wins / losses etc
BattleRoom =
  class(
  function(self, mode, roomCreationData)
    assert(mode)
    self.mode = mode
    if roomCreationData then
      self.online = true
    end

    self.players = {}
    -- creating the local player
    self.players[1] = Player(config.name, 0, self, true)
    -- create the other players if there are any
    for i = 2, self.mode.playerCount do
      self.players[i] = Player(loc("player_n", tostring(i)))
    end

    self.spectators = {}
    self.spectating = false
    self.trainingModeSettings = nil
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
  self.match = Match(self.mode, self)

  for i = 1, #self.players do
    self.match:addPlayer(self.players[i])
  end

  return self.match
end