local logger = require("logger")
require("engine.telegraphGraphics")

Telegraph = class(function(self, sender, receiver)
  -- Stores the actual queue of garbages in the telegraph, including when each piece of garbage may get released
  self.garbageQueue = GarbageQueue()

  -- The stack that sent this garbage
  self.sender = sender
  -- The stack that is receiving the garbage; not directly referenced for functionality but used for determining the draw position
  self.receiver = receiver
  -- A copy of the chains and combos earned used to render the animation of going to the telegraph
  self.attacks = {}
  -- Set when we start a new chain, cleared when the sender is done chaining,
  -- used to know if we should grow a chain or start a new one
  -- (if we only wanted to know about chain state we could refer to sender.chain_counter instead)
  self.senderCurrentlyChaining = false
  self.clonePool = {}

  self.graphics = TelegraphGraphics(self)
end)

function Telegraph:saveClone(toSave)
  self.clonePool[#self.clonePool + 1] = toSave
end

function Telegraph:getRecycledInstance()
  local instance
  if #self.clonePool == 0 then
    instance = Telegraph(self.sender, self.receiver)
  else
    instance = self.clonePool[#self.clonePool]
    self.clonePool[#self.clonePool] = nil
  end
  return instance
end

function Telegraph.rollbackCopy(source, other)
  if other == nil then
    other = source:getRecycledInstance()
  end

  other.garbageQueue = source.garbageQueue:makeCopy()
  if config.renderAttacks then
    other.attacks = deepcpy(source.attacks)
  end
  other.senderCurrentlyChaining = source.senderCurrentlyChaining

  -- We don't want saved copies to hold on to stacks, up to the rollback restore to set these back up.
  other.sender = nil
  other.receiver = nil
  return other
end

-- Adds a piece of garbage to the queue
function Telegraph:push(garbage, attackOriginCol, attackOriginRow, frameEarned)
  assert(self.sender ~= nil and self.receiver ~= nil, "telegraph needs receiver and sender set")
  assert(frameEarned == self.sender.CLOCK, "expected sender clock to equal attack")

  -- the attack only starts interacting with the telegraph on the next frame, not the same it was earned
  self:privatePush(garbage, attackOriginCol, attackOriginRow, frameEarned + 1)
end

-- Adds a piece of garbage to the queue
function Telegraph:privatePush(garbage, attackOriginColumn, attackOriginRow, timeAttackInteracts)
  local garbageToSend
  if garbage.isChain then
    garbageToSend = self:growChain(timeAttackInteracts)
  else
    garbageToSend = self:addComboGarbage(garbage, timeAttackInteracts)
  end
  self:registerAttack(garbageToSend, attackOriginColumn, attackOriginRow, timeAttackInteracts)
end

function Telegraph:registerAttack(garbage, attackOriginColumn, attackOriginRow, timeAttackInteracts)
  if config.renderAttacks then
    if not self.attacks[timeAttackInteracts] then
      self.attacks[timeAttackInteracts] = {}
    end
    -- we don't want to use the same object as in the garbage queue so they don't change each other
    garbage = deepcpy(garbage)
    self.attacks[timeAttackInteracts][#self.attacks[timeAttackInteracts] + 1] = {
      timeAttackInteracts = timeAttackInteracts,
      originColumn = attackOriginColumn,
      originRow = attackOriginRow,
      garbageToSend = garbage
    }
  end
end

function Telegraph:addComboGarbage(garbage, timeAttackInteracts)
  logger.debug("Telegraph.add_combo_garbage " .. (garbage.width or "nil") .. " " .. (garbage.isMetal and "true" or "false"))
  local garbageToSend = {
    width = garbage.width,
    height = garbage.height,
    isMetal = garbage.isMetal,
    isChain = garbage.isChain,
    timeAttackInteracts = timeAttackInteracts,
    releaseTime = timeAttackInteracts + GARBAGE_TRANSIT_TIME + GARBAGE_TELEGRAPH_TIME
  }

  self.garbageQueue:push(garbageToSend)
  return {garbageToSend}
end

function Telegraph:chainingEnded(frameEnded)
  logger.debug("Player " .. self.sender.which .. " chain ended at " .. frameEnded)

  if not GAME.battleRoom.trainingModeSettings then
    assert(frameEnded == self.sender.CLOCK, "expected sender clock to equal attack")
  end

  self:privateChainingEnded(frameEnded)
end

function Telegraph:privateChainingEnded(chainEndTime)
  logger.debug("finalizing chain at " .. chainEndTime)

  self.senderCurrentlyChaining = false
  self.garbageQueue:finalizeCurrentChain()
end

function Telegraph.growChain(self, timeAttackInteracts)
  local newChain = false
  if not self.senderCurrentlyChaining then
    self.senderCurrentlyChaining = true
    newChain = true
  end
  local releaseTime = timeAttackInteracts + GARBAGE_TRANSIT_TIME + GARBAGE_TELEGRAPH_TIME
  return self.garbageQueue:growChain(timeAttackInteracts, newChain, releaseTime)
end

-- Returns all the garbage that is ready to be sent.
function Telegraph:popAllReadyGarbage(time)
  if self.garbageQueue:len() > 0 then
    local poppedGarbage = {}
    local garbage = self.garbageQueue:peek()

    while garbage and garbage.releaseTime <= time do
      poppedGarbage[#poppedGarbage+1] = self.garbageQueue:pop()
      garbage = self.garbageQueue:peek()
    end

    if poppedGarbage[1] then
      return poppedGarbage
    else
      return nil
    end
  end
end

