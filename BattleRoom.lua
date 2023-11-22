
local logger = require("logger")
local Player = require("Player")

-- A Battle Room is a session of vs battles, keeping track of the room number, wins / losses etc
BattleRoom =
  class(
  function(self, mode)
    assert(mode)

    self.players = {}
    -- todo: initialize players from game mode instead
    self.players[1] = Player(loc("player_n", "1"))
    self.players[2] = Player(loc("player_n", "2"))
    self.spectators = {}
    self.spectating = false
    self.mode = mode
    self.trainingModeSettings = nil
  end
)

function BattleRoom.updateWinCounts(self, winCounts)
  self.playerWinCounts = winCounts
end

function BattleRoom:totalGames()
  local totalGames = 0
  for _, winCount in ipairs(self.playerWinCounts) do
    totalGames = totalGames + winCount
  end
  return totalGames
end

-- Returns the player with more win count.
-- TODO handle ties?
function BattleRoom:winningPlayer()
  if not GAME.match.P2 then
    return GAME.match.P1
  end

  if self.playerWinCounts[GAME.match.P1.player_number] >= self.playerWinCounts[GAME.match.P2.player_number] then
    logger.trace("Player " .. GAME.match.P1.which .. " (" .. GAME.match.P1.player_number .. ") has more wins")
    return GAME.match.P1
  end

  logger.trace("Player " .. GAME.match.P2.which .. " (" .. GAME.match.P2.player_number .. ") has more wins")
  return GAME.match.P2
end

function BattleRoom:getPlayerWinCount(playerNumber)
 return self.playerWinCounts[playerNumber] + self.modifiedWinCounts[playerNumber]
end

function BattleRoom:createMatch()
  self.match = Match(self.mode, self)
  return self.match
end