-- a bulk processor for replays 
-- all  replays that do not finish correctly with the current engine are copied into a separate directory

local fileUtils = require("client.src.FileUtils")
local Replay = require("common.engine.Replay")
local Match = require("common.engine.Match")
local tableUtils = require("common.lib.tableUtils")

local verifier = { faulty = {} }

function verifier.bulkVerifyReplays(replayPath, outputPath)
  local items = love.filesystem.getDirectoryItems(replayPath)
  for i, item in ipairs(items) do
    local filePath = replayPath .. "/" .. item
    local fileInfo = love.filesystem.getInfo(filePath)
    if fileInfo.type == "directory" then
      verifier.bulkVerifyReplays(filePath, outputPath)
    elseif fileInfo.type == "file" then
      local json = fileUtils.readJsonFile(filePath)
      local success, replay = Replay.load(json)
      if not success then
        -- not sure, probably error or use a separate dir in the output path?
      else
        -- we can only really make statements about replays that finished running
        if not replay.incomplete then
          local verified, winnerIndex, clock = verifier.verifyReplay(replay)
          if not verified then
            verifier.faulty[#verifier.faulty+1] = {
              path = filePath,
              reason = "Replay stopped running at " .. clock .. " with winner " .. winnerIndex
                  ..   " but should have stopped at " .. replay.duration .. " with winner " .. (replay.winnerIndex or "unknown")
            }
          end
        end
      end
    end
  end
end

function verifier.verifyReplay(replay)
  local match = Match.createFromReplay(replay, false)

  while match.winners == nil and match.clock < replay.duration do
    match:run()
  end

  -- winners is always a table with at least 1 player (2 in case of a tie)
  -- it being empty signifies the match never finished
  if match.winners == nil then
    return false, 0, match.clock
  end

  if match.clock < replay.duration then
    return false, tableUtils.indexOf(match.players, match.winners[1]), match.clock
  end

  if replay.winnerIndex and replay.winnerIndex ~= tableUtils.indexOf(match.players, match.winners[1]) then
    return false, tableUtils.indexOf(match.players, match.winners[1]), match.clock
  end

  -- is there another check necessary?

  return true, tableUtils.indexOf(match.players, match.winners[1]), match.clock
end

return verifier