local utf8 = require("utf8Additions")
local logger = require("logger")
local GameModes = require("GameModes")
local ReplayV1 = require("replayV1")
local ReplayV2 = require("replayV2")
local Player = require("Player")

local REPLAY_VERSION = 2
local tableUtils = require("tableUtils")

-- A replay is a particular recording of a play of the game. Temporarily this is just helper methods.
Replay =
class(
    function(self)
    end
  )

function Replay.createNewReplay(match)
  local battleRoom = match.battleRoom
  local result = {}
  result.engineVersion = VERSION
  result.replayVersion = REPLAY_VERSION
  result.seed = match.seed
  result.ranked = match_type == "Ranked"
  result.doCountdown = match.doCountdown or true
  result.stage = match.stage
  result.gameMode = {
    stackInteraction = battleRoom.mode.stackInteraction,
    winCondition = battleRoom.mode.winCondition
  }

  result.players = {}
  for i = 1, battleRoom.players do
    local player = battleRoom.players[i]
    result.players[i] = {
      name = player.name,
      wins = player.wins,
      publicId = player.publicId,
      settings = {
        characterId = player.settings.characterId,
        panelId = player.settings.panelId,
        levelData = player.settings.levelData,
        inputMethod = player.settings.inputMethod
      }
    }
    if player.settings.level then
      result.players[i].settings.level = player.settings.level
    else
      result.players[i].settings.difficulty = player.settings.difficulty
    end
  end

  return result
end

function Replay.replayCanBeViewed(replay)
  if replay.engineVersion >= VERSION_MIN_VIEW and replay.engineVersion <= VERSION then
    if not replay.puzzle then
      return true
    end
  end

  return false
end

function Replay.loadFromPath(path)
    local file, error_msg = love.filesystem.read(path)

    if file == nil then
        --print(loc("rp_browser_error_loading", error_msg))
        return false
    end

    replay = {}
    replay = json.decode(file)
    if not replay.engineVersion then
        replay.engineVersion = "046"
    end

    return true
end

local function createMatchFromReplay(replay, wantsCanvas)
  local battleRoom

  if replay.gameMode.stackInteraction == GameModes.StackInteraction.VERSUS then
    if #replay.players == 2 then
      battleRoom = BattleRoom(GameModes.TWO_PLAYER_VS)
    else
      error("There is no versus game mode for more or less than 2 players")
    end
  elseif replay.gameMode.stackInteraction == GameModes.StackInteraction.SELF then
    if #replay.players == 1 then
      battleRoom = BattleRoom(GameModes.ONE_PLAYER_VS_SELF)
    else
      error("There is no versus self game mode for more than 1 player")
    end
  elseif replay.gameMode.stackInteraction == GameModes.StackInteraction.ATTACK_ENGINE then
    if #replay.players == 1 then
      battleRoom = BattleRoom(GameModes.ONE_PLAYER_TRAINING)
    else
      error("There is no training game mode for more than 1 player")
    end
  elseif replay.gameMode.stackInteraction == GameModes.StackInteraction.HEALTH_ENGINE then
    if #replay.players == 1 then
      battleRoom = BattleRoom(GameModes.ONE_PLAYER_CHALLENGE)
    else
      error("There is no challenge game mode for more than 1 player")
    end
  else -- if replay.gameMode.stackInteraction == GameModes.StackInteraction.NONE
    if #replay.players == 1 then
      if replay.timeLimit then
        battleRoom = BattleRoom(GameModes.ONE_PLAYER_TIME_ATTACK)
      else
        battleRoom = BattleRoom(GameModes.ONE_PLAYER_ENDLESS)
      end
    else
      error("There is no time attack/endless game mode for more than 1 player")
    end
  end

  for i = 1, #replay.players do
    local rpp = replay.players[i]
    local player = Player(rpp.name, rpp.publicId, battleRoom)
    player.playerNumber = i
    player.wins = rpp.wins
    player.settings.panelId = rpp.settings.panelId
    player.settings.characterId = CharacterLoader.resolveCharacterSelection(rpp.settings.characterId)
    player.settings.inputMethod = rpp.settings.inputMethod
    player.settings.level = rpp.settings.level
    player.settings.difficulty = rpp.settings.difficulty
    --player.settings.levelData = rpp.settings.levelData
    battleRoom:addPlayer(player)
  end

  GAME.battleRoom = battleRoom
  local match = battleRoom:createMatch()

  match.isFromReplay = true
  match.doCountdown = replay.doCountdown
  match.seed = replay.seed
  match.stage = StageLoader.resolveStageSelection(replay.stage)

  return match
end

function Replay.loadFromFile(replay, wantsCanvas)
  assert(replay ~= nil)
  if not replay.replayVersion then
    replay = ReplayV1.loadFromFile(replay, wantsCanvas)
  else
    replay = ReplayV2.loadFromFile(replay, wantsCanvas)
  end
  return createMatchFromReplay(replay, wantsCanvas)
end

local function addReplayStatisticsToReplay(match, replay)
  replay.duration = match:gameEndedClockTime()
  local winner = match:getWinner()
  if winner then
    replay.winner = winner.publicId or winner.playerNumber
  end
  
  for i = 1, #match.players do
    local stack = match.players[i].stack
    local playerTable = replay.players[i]
    playerTable.analytics = stack.analytic.data
    playerTable.analytics.score = stack.score
    playerTable.analytics.rating = match.room_ratings[i]
  end

  return replay
end

function Replay.finalizeAndWriteReplay(extraPath, extraFilename, match, replay)
  Replay.finalizeReplay(match, replay)
  local path, filename = Replay.finalReplayFilename(extraPath, extraFilename)
  local replayJSON = json.encode(replay)
  Replay.writeReplayFile(path, filename, replayJSON)
end

function Replay.finalReplayFilename(extraPath, extraFilename)
  local now = os.date("*t", to_UTC(os.time()))
  local sep = "/"
  local path = "replays" .. sep .. "v" .. VERSION .. sep .. string.format("%04d" .. sep .. "%02d" .. sep .. "%02d", now.year, now.month, now.day)
  if extraPath then
    path = path .. sep .. extraPath
  end
  local filename = "v" .. VERSION .. "-" .. string.format("%04d-%02d-%02d-%02d-%02d-%02d", now.year, now.month, now.day, now.hour, now.min, now.sec)
  if extraFilename then
    filename = filename .. "-" .. extraFilename
  end
  filename = filename .. ".json"
  logger.debug("saving replay as " .. path .. sep .. filename)
  return path, filename
end

function Replay.finalizeReplay(match, replay)
  replay = addReplayStatisticsToReplay(match, replay)
  replay[match.mode].in_buf = table.concat(match.P1.confirmedInput)
  replay[match.mode].stage = current_stage
  if match.P2 then
    replay[match.mode].I = table.concat(match.P2.confirmedInput)
  end
  Replay.compressReplay(replay)
end

function Replay.finalizeAndWriteVsReplay(battleRoom, outcome_claim, incompleteGame, match, replay)

  incompleteGame = incompleteGame or false
  
  local extraPath, extraFilename = "", ""

  if match:warningOccurred() then
    extraFilename = extraFilename .. "-WARNING-OCCURRED"
  end

  if GAME.match.P2 then
    local rep_a_name, rep_b_name = battleRoom.playerNames[1], battleRoom.playerNames[2]
    --sort player names alphabetically for folder name so we don't have a folder "a-vs-b" and also "b-vs-a"
    if rep_b_name < rep_a_name then
      extraPath = rep_b_name .. "-vs-" .. rep_a_name
    else
      extraPath = rep_a_name .. "-vs-" .. rep_b_name
    end
    extraFilename = extraFilename .. rep_a_name .. "-L" .. GAME.match.P1.level .. "-vs-" .. rep_b_name .. "-L" .. GAME.match.P2.level
    if match_type and match_type ~= "" then
      extraFilename = extraFilename .. "-" .. match_type
    end
    if incompleteGame then
      extraFilename = extraFilename .. "-INCOMPLETE"
    else
      if outcome_claim == 1 or outcome_claim == 2 then
        extraFilename = extraFilename .. "-P" .. outcome_claim .. "wins"
      elseif outcome_claim == 0 then
        extraFilename = extraFilename .. "-draw"
      end
    end
  else -- vs Self
    extraPath = "Vs Self"
    extraFilename = extraFilename .. "vsSelf-" .. "L" .. GAME.match.P1.level
  end

  Replay.finalizeAndWriteReplay(extraPath, extraFilename, match, replay)
end

function Replay.compressReplay(replay)
  if replay.puzzle then
    replay.puzzle.in_buf = compress_input_string(replay.puzzle.in_buf)
    logger.debug("Compressed puzzle in_buf")
    logger.debug(replay.puzzle.in_buf)
  end
  if replay.endless then
    replay.endless.in_buf = compress_input_string(replay.endless.in_buf)
    logger.debug("Compressed endless in_buf")
    logger.debug(replay.endless.in_buf)
  end
  if replay.vs then
    replay.vs.I = compress_input_string(replay.vs.I)
    replay.vs.in_buf = compress_input_string(replay.vs.in_buf)
    logger.debug("Compressed vs I/in_buf")
  end
end

-- writes a replay file of the given path and filename
function Replay.writeReplayFile(path, filename, replayJSON)
  assert(path ~= nil)
  assert(filename ~= nil)
  assert(replayJSON ~= nil)
  Replay.lastPath = path
  pcall(
    function()
      love.filesystem.createDirectory(path)
      local file = love.filesystem.newFile(path .. "/" .. filename)
      file:open("w")
      file:write(replayJSON)
      file:close()
    end
  )
end

return Replay