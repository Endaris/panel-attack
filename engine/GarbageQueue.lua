local logger = require("logger")


local function orderChainGarbage(a, b)
  if a.finalized == b.finalized then
    return a.timeAttackInteracts > b.timeAttackInteracts
  else
    return not a.finalized
  end
end

-- specifies order in the garbage queue if two elements are both combos
local function orderComboGarbage(a, b)
  -- both are combos
  if a.width ~= b.width then
    -- combos are ordered by width
    return a.width > b.width
  else
    -- same width ordered by time
    -- deviation here, new garbage goes before old garbage so it refreshes their releaseTime
    return a.timeAttackInteracts < b.timeAttackInteracts
  end
end

--  width
--  height
--  isMetal
--  isChain
--  timeAttackInteracts
--  finalized (optional)
-- orders garbage so that priority increases with index
local function orderGarbage(garbageQueue)
  table.sort(garbageQueue, function(a, b)
    if a.isChain == b.isChain then
      if a.isChain then
        return orderChainGarbage(a, b)
      else
        -- we handle exclusively non-chain garbage!
        if a.isMetal == b.isMetal then
          -- both pieces are of the same type
          return orderComboGarbage(a, b)
        else
          -- it's a combo and a shock!
          -- some special case to enable armageddon shenanigans here
          if GAME.battleRoom.trainingModeSettings and GAME.battleRoom.trainingModeSettings.mergeComboMetalQueue then
            -- under this setting, shock and combos are treated as if they were the same!
            return orderComboGarbage(a, b)
          else
            -- otherwise, combo always queues before shock
            return a.isMetal
          end
        end
      end
    else
      -- one is a chain, the other not
      -- chain should get sorted in after the combo
      return not a.isChain
    end
  end)

  return garbageQueue
end

-- -- updates the releaseTime of the piece of garbage and all garbage after it
-- -- the idea is that no garbage can have a releaseTime smaller than garbage with higher priority
-- -- priority increases with index
-- local function updateReleaseTimes(garbageQueue)
--   local releaseTime = 0
--   for i = #garbageQueue, 1, -1 do
--     if garbageQueue[i].releaseTime == releaseTime then
--     elseif garbageQueue[i].releaseTime > releaseTime then
--       -- so if as expected, releaseTime is higher, refresh releaseTime to check for the next element
--       releaseTime = garbageQueue[i].releaseTime
--     else
--       -- if releaseTime is lower, the element inherits the releaseTime
--       garbageQueue[i].releaseTime = releaseTime
--     end
--   end
-- end

-- Holds garbage in a queue and follows a specific order for which types should be popped out first.
GarbageQueue = class(function(s)
  s.garbage = {}
  s.currentChain = nil
  -- a ghost chain keeps the smaller version of a chain thats growing showing in the telegraph while the new chain's attack animation is still animating to the telegraph.
  s.ghostChain = nil
end)

function GarbageQueue.makeCopy(self)
  local other = GarbageQueue()
  for i = 1, #self.garbage do
    if self.garbage[i] == self.currentChain then
      other.currentChain = deepcpy(self.currentChain)
      other.garbage[i] = other.currentChain
    else
      other.garbage[i] = self.garbage[i]
    end
  end

  other.ghostChain = self.ghostChain
  return other
end

-- garbage is expected to be a table with the values
--  width
--  height
--  isMetal
--  isChain
--  timeAttackInteracts
--  finalized (optional)
function GarbageQueue.push(self, garbage)
  if garbage.height > 1 and GAME.battleRoom.trainingModeSettings then
    -- even though it's combo garbage, pretend it's a chain
    garbage.isChain = true
    garbage.finalized = true
  end
  self.garbage[#self.garbage+1] = garbage

  orderGarbage(self.garbage)
  --updateReleaseTimes(self.garbage)
end

-- accepts multiple pieces of garbage in an array
-- garbage is expected to be a table with the values
--  width
--  height
--  isMetal
--  isChain
--  timeAttackInteracts
--  finalized (optional)
function GarbageQueue.pushTable(self, garbageArray)
  if garbageArray then
    for _, garbage in pairs(garbageArray) do
      if garbage.width and garbage.height then
        if garbage.height > 1 and GAME.battleRoom.trainingModeSettings then
          -- even though it's combo garbage, pretend it's a chain
          garbage.isChain = true
          garbage.finalized = true
        end
        self.garbage[#self.garbage+1] = garbage
      end
    end
    orderGarbage(self.garbage)
    --updateReleaseTimes(self.garbage)
  end
end

function GarbageQueue.peek(self)
  local garbage = self.garbage[#self.garbage]
  if garbage then
    return garbage
  else
    return nil
  end
end

-- Returns the first chain, then combo, then metal, in that order.
function GarbageQueue.pop(self)
  local garbage = table.remove(self.garbage)
  return garbage
end

function GarbageQueue:toString()
  local garbageQueueString = "Garbage Queue Content"
  local jsonEncodedGarbage = table.map(self.garbage, function(garbage) return json.encode(garbage) end)
  garbageQueueString = garbageQueueString .. table.concat(jsonEncodedGarbage, "\n")
  
  return garbageQueueString
end

function GarbageQueue.len(self)
  return #self.garbage
end

-- This is used by the telegraph to increase the size of the chain garbage being built
-- or add a 6-wide if there is not chain garbage yet in the queue
function GarbageQueue:growChain(timeAttackInteracts, newChain, releaseTime)
  if newChain or self.currentChain == nil then
    self.currentChain = {width = 6, height = 1, isMetal = false, isChain = true, timeAttackInteracts = timeAttackInteracts, finalized = false}
    self:push(self.currentChain)
  else
    self.ghostChain = self.currentChain.height
    -- currentChain is always part of the queue already (see push in branch above)
    self.currentChain.height = self.currentChain.height + 1
    self.currentChain.timeAttackInteracts = timeAttackInteracts
  end
  self.currentChain.releaseTime = releaseTime
  --updateReleaseTimes(self.garbage)

  return {self.currentChain}
end

-- returns the index of the first garbage block matching the requested type and size, or where it would go if it was in the Garbage_Queue.
-- note: the first index for our implemented Queue object is 0, not 1
-- this will return 0 for the first index.
function GarbageQueue.getGarbageIndex(self, garbage)
  local garbageCount = #self.garbage
  for i = 1, #self.garbage do
    if self.garbage[i] == garbage then
      -- the garbage table is ordered back to front for cheaper element removal
      -- but telegraph expects the next element to pop as the one with the lowest index
      return garbageCount - i
    end
  end

  -- if we ever arrive here, that means there is garbage in the queue that is not in the queue
  error("commence explosion")
end

function GarbageQueue.finalizeCurrentChain(self)
  self.currentChain.finalized = true
  self.currentChain = nil
end