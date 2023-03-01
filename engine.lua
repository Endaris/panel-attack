require("analytics")
local logger = require("logger")
require("engine.panel")

-- Stuff defined in this file:
--  . the data structures that store the configuration of
--    the stack of panels
--  . the main game routine
--    (rising, timers, falling, cursor movement, swapping, landing)
--  . the matches-checking routine
local min, pairs, deepcpy = math.min, pairs, deepcpy
local max = math.max

local DT_SPEED_INCREASE = 15 * 60 -- frames it takes to increase the speed level by 1

-- Represents the full panel stack for one player
Stack = class(function(s, arguments)
  local which = arguments.which or 1
  assert(arguments.match ~= nil)
  local match = arguments.match
  assert(arguments.is_local ~= nil)
  local is_local = arguments.is_local
  local panels_dir = arguments.panels_dir or config.panels
  -- level or difficulty should be set
  assert(arguments.level ~= nil or arguments.difficulty ~= nil)
  local level = arguments.level
  local difficulty = arguments.difficulty
  local speed = arguments.speed
  local player_number = arguments.player_number or which
  local wantsCanvas = arguments.wantsCanvas or 1
  local character = arguments.character or config.character

  s.FRAMECOUNTS = {}

  s.match = match
  s.character = resolveCharacterSelection(character)
  s.max_health = 1
  s.panels_dir = panels_dir
  s.portraitFade = 0
  s.is_local = is_local

  s.drawsAnalytics = true

  if not panels[panels_dir] then
    s.panels_dir = config.panels
  end

  if s.match.mode == "puzzle" then
    s.drawsAnalytics = false
  else
    s.do_first_row = true
  end

  if difficulty then
    if s.match.mode == "endless" then
      s.NCOLORS = difficulty_to_ncolors_endless[difficulty]
    elseif s.match.mode == "time" then
      s.NCOLORS = difficulty_to_ncolors_1Ptime[difficulty]
    end
  end

  -- frame.png dimensions
  if wantsCanvas then
    s.canvas = love.graphics.newCanvas(104 * GFX_SCALE, 204 * GFX_SCALE, {dpiscale = GAME:newCanvasSnappedScale()})
  end

  -- The player's speed level decides the amount of time
  -- the stack takes to rise automatically
  if speed then
    s.speed = speed
  end

  if level then
    s:setLevel(level)
    -- mode 1: increase speed based on fixed intervals
    s.speedIncreaseMode = 1
    s.nextSpeedIncreaseClock = DT_SPEED_INCREASE
  else
    s.difficulty = difficulty or 2
    -- mode 2: increase speed based on how many panels were cleared
    s.speedIncreaseMode = 2
    if not speed then
      s.speed = 1
    end
    s.panels_to_speedup = panels_to_next_speed[s.speed]
  end

  s.health = s.max_health

  -- Which columns each size garbage is allowed to fall in.
  -- This is typically constant but maybe some day we would allow different ones 
  -- for different game modes or need to change it based on board width.
  s.garbageSizeDropColumnMaps = {{1, 2, 3, 4, 5, 6}, {1, 3, 5}, {1, 4}, {1, 2, 3}, {1, 2}, {1}}
  -- The current index of the above table we are currently using for the drop column.
  -- This increases by 1 wrapping every time garbage drops.
  s.currentGarbageDropColumnIndexes = {1, 1, 1, 1, 1, 1}

  s.later_garbage = {} -- Queue of garbage that is done waiting in telegraph, and been popped out, and will be sent to our stack next frame
  s.garbage_q = GarbageQueue(s) -- Queue of garbage that is about to be dropped

  s:moveForPlayerNumber(which)

  s.panel_buffer = ""
  s.gpanel_buffer = ""
  s.input_buffer = {} -- Inputs that haven't been processed yet
  s.confirmedInput = {} -- All inputs the player has input ever
  -- The number of individual garbage blocks created on this stack
  -- used for giving a unique identifier to each new garbage block
  s.garbageCreatedCount = 0
  s.garbageLandedThisFrame = {}
  -- The number of individual panels created on this stack
  -- used for giving new panels their own unique identifier
  s.panelsCreatedCount = 0
  -- 2 dimensional table for containing all panels
  -- panel[i] gets the row where i is the index of the row with 1 being the most bottom row that is in play (not dimmed)
  -- panel[i][j] gets the panel at row i where j is the column index counting from left to right starting from 1
  -- the update order for panels is bottom to top and left to right as well
  s.panels = {}
  s.width = 6
  s.height = 12
  for i = 0, s.height do
    s.panels[i] = {}
    for j = 1, s.width do
      s.panels[i][j] = s:createPanel(i, j)
    end
  end

  s.CLOCK = 0
  s.game_stopwatch = 0
  s.game_stopwatch_running = false
  s.do_countdown = true
  s.max_runs_per_frame = 3

  s.displacement = 16
  -- This variable indicates how far below the top of the play
  -- area the top row of panels actually is.
  -- This variable being decremented causes the stack to rise.
  -- During the automatic rising routine, if this variable is 0,
  -- it's reset to 15, all the panels are moved up one row,
  -- and a new row is generated at the bottom.
  -- Only when the displacement is 0 are all 12 rows "in play."

  s.danger_col = {false, false, false, false, false, false}
  -- set true if this column is near the top
  s.danger_timer = 0 -- decides bounce frame when in danger

  s.rise_timer = 1 -- When this value reaches 0, the stack will rise a pixel
  s.rise_lock = false -- If the stack is rise locked, it won't rise until it is
  -- unlocked.
  s.has_risen = false -- set once the stack rises once during the game

  s.stop_time = 0
  s.pre_stop_time = 0

  s.NCOLORS = s.NCOLORS or 5
  s.score = 0 -- der skore
  s.chain_counter = 0 -- how high is the current chain (starts at 2)

  s.panels_in_top_row = false -- boolean, for losing the game
  s.danger = s.danger or false -- boolean, panels in the top row (danger)
  s.danger_music = s.danger_music or false -- changes music state

  s.n_active_panels = 0
  s.n_prev_active_panels = 0

  -- These change depending on the difficulty and speed levels:
  s.FRAMECOUNTS.HOVER = s.FRAMECOUNTS.HOVER or FC_HOVER[s.difficulty]
  s.FRAMECOUNTS.FLASH = s.FRAMECOUNTS.FLASH or FC_FLASH[s.difficulty]
  s.FRAMECOUNTS.FACE = s.FRAMECOUNTS.FACE or FC_FACE[s.difficulty]
  s.FRAMECOUNTS.POP = s.FRAMECOUNTS.POP or FC_POP[s.difficulty]
  s.FRAMECOUNTS.MATCH = s.FRAMECOUNTS.FACE + s.FRAMECOUNTS.FLASH

  s.rise_timer = speed_to_rise_time[s.speed]

  -- Player input stuff:
  s.manual_raise = false -- set until raising is completed
  s.manual_raise_yet = false -- if not set, no actual raising's been done yet
  -- since manual raise button was pressed
  s.prevent_manual_raise = false
  s.swap_1 = false -- attempt to initiate a swap on this frame
  s.swap_2 = false

  s.taunt_up = nil -- will hold an index
  s.taunt_down = nil -- will hold an index
  s.taunt_queue = Queue()

  s.cur_wait_time = config.input_repeat_delay -- number of ticks to wait before the cursor begins
  -- to move quickly... it's based on P1CurSensitivity
  s.cur_timer = 0 -- number of ticks for which a new direction's been pressed
  s.cur_dir = nil -- the direction pressed
  s.cur_row = 7 -- the row the cursor's on
  s.cur_col = 3 -- the column the left half of the cursor's on
  s.top_cur_row = s.height + (s.match.mode == "puzzle" and 0 or -1)

  s.poppedPanelIndex = s.poppedPanelIndex or 1
  s.panels_cleared = s.panels_cleared or 0
  s.metal_panels_queued = s.metal_panels_queued or 0
  s.lastPopLevelPlayed = s.lastPopLevelPlayed or 1
  s.lastPopIndexPlayed = s.lastPopIndexPlayed or 1
  s.combo_chain_play = nil
  s.game_over = false -- only set if this player got a game over
  s.game_over_clock = 0 -- only set if game_over is true, the exact clock frame the player lost
  s.sfx_land = false
  s.sfx_garbage_thud = 0

  s.card_q = Queue()

  s.pop_q = Queue()

  s.which = which
  s.player_number = player_number -- player number according to the multiplayer server, for game outcome reporting

  s.shake_time = 0

  s.prev_states = {}

  s.analytic = AnalyticsInstance(s.is_local)

  if s.match.mode == "vs" then
    s.telegraph = Telegraph(s, s) -- Telegraph holds the garbage that hasn't been committed yet and also tracks the attack animations
    -- NOTE: this is the telegraph above this stack, so the opponents puts garbage in this stack.
  end

  s.combos = {} -- Tracks the combos made throughout the whole game. Key is the clock time, value is the combo size
  s.chains = {} -- Tracks the chains made throughout the whole game
  --[[
        Key - CLOCK time the chain started
        Value -
	        starts - array of CLOCK times for the start of each match in the chain
	        finish - CLOCK time the chain finished
	        size - the chain size 2, 3, etc
    ]]
  s.currentChainStartFrame = nil -- The start frame of the current active chain or nil if no chain is active

  s.panelGenCount = 0
  s.garbageGenCount = 0

  s.clonePool = {} -- pool of stale rollback copies, used to save memory on consecutive rollback
  s.rollbackCount = 0 -- the number of times total we have done rollback
  s.lastRollbackFrame = -1 -- the last frame we had to rollback from

  s.framesBehindArray = {}
  s.totalFramesBehind = 0
  s.warningsTriggered = {}

  s.time_quads = {}
  s.move_quads = {}
  s.score_quads = {}
  s.speed_quads = {}
  s.level_quad = GraphicsUtil:newRecycledQuad(0, 0, themes[config.theme].images["IMG_levelNumber_atlas" .. s.id]:getWidth() / 11,
                                              themes[config.theme].images["IMG_levelNumber_atlas" .. s.id]:getHeight(),
                                              themes[config.theme].images["IMG_levelNumber_atlas" .. s.id]:getDimensions())
  s.healthQuad = GraphicsUtil:newRecycledQuad(0, 0, themes[config.theme].images.IMG_healthbar:getWidth(),
                                              themes[config.theme].images.IMG_healthbar:getHeight(),
                                              themes[config.theme].images.IMG_healthbar:getWidth(),
                                              themes[config.theme].images.IMG_healthbar:getHeight())
  s.multi_prestopQuad = GraphicsUtil:newRecycledQuad(0, 0, themes[config.theme].images.IMG_multibar_prestop_bar:getWidth(),
                                                     themes[config.theme].images.IMG_multibar_prestop_bar:getHeight(),
                                                     themes[config.theme].images.IMG_multibar_prestop_bar:getWidth(),
                                                     themes[config.theme].images.IMG_multibar_prestop_bar:getHeight())
  s.multi_stopQuad = GraphicsUtil:newRecycledQuad(0, 0, themes[config.theme].images.IMG_multibar_stop_bar:getWidth(),
                                                  themes[config.theme].images.IMG_multibar_stop_bar:getHeight(),
                                                  themes[config.theme].images.IMG_multibar_stop_bar:getWidth(),
                                                  themes[config.theme].images.IMG_multibar_stop_bar:getHeight())
  s.multi_shakeQuad = GraphicsUtil:newRecycledQuad(0, 0, themes[config.theme].images.IMG_multibar_shake_bar:getWidth(),
                                                   themes[config.theme].images.IMG_multibar_shake_bar:getHeight(),
                                                   themes[config.theme].images.IMG_multibar_shake_bar:getWidth(),
                                                   themes[config.theme].images.IMG_multibar_shake_bar:getHeight())
end)

function Stack.setLevel(self, level)
  self.level = level
  if not self.speed then
    -- there is no UI for it yet but we may want to support using levels with a different starting speed at some point
    self.speed = level_to_starting_speed[level]
  end
  -- mode 1: increase speed per time interval?
  self.max_health = level_to_hang_time[level]
  self.FRAMECOUNTS.HOVER = level_to_hover[level]
  self.FRAMECOUNTS.GPHOVER = level_to_garbage_panel_hover[level]
  self.FRAMECOUNTS.FLASH = level_to_flash[level]
  self.FRAMECOUNTS.FACE = level_to_face[level]
  self.FRAMECOUNTS.POP = level_to_pop[level]
  self.combo_constant = level_to_combo_constant[level]
  self.combo_coefficient = level_to_combo_coefficient[level]
  self.chain_constant = level_to_chain_constant[level]
  self.chain_coefficient = level_to_chain_coefficient[level]
  if self.match.mode == "2ptime" then
    self.NCOLORS = level_to_ncolors_time[level]
  else
    self.NCOLORS = level_to_ncolors_vs[level]
  end
end

-- Should be called prior to clearing the stack.
-- Consider recycling any memory that might leave around a lot of garbage.
-- Note: You can just leave the variables to clear / garbage collect on their own if they aren't large.
function Stack:deinit()
  for _, quad in ipairs(self.time_quads) do
    GraphicsUtil:releaseQuad(quad)
  end
  for _, quad in ipairs(self.move_quads) do
    GraphicsUtil:releaseQuad(quad)
  end
  for _, quad in ipairs(self.score_quads) do
    GraphicsUtil:releaseQuad(quad)
  end
  for _, quad in ipairs(self.speed_quads) do
    GraphicsUtil:releaseQuad(quad)
  end
  GraphicsUtil:releaseQuad(self.level_quad)
  GraphicsUtil:releaseQuad(self.healthQuad)
  GraphicsUtil:releaseQuad(self.multi_prestopQuad)
  GraphicsUtil:releaseQuad(self.multi_stopQuad)
  GraphicsUtil:releaseQuad(self.multi_shakeQuad)
end

-- Positions the stack draw position for the given player
function Stack.moveForPlayerNumber(stack, player_num)
  -- Position of elements should ideally be on even coordinates to avoid non pixel alignment
  -- on 150% scale
  if player_num == 1 then
    stack.pos_x = 80
    stack.score_x = 546
    stack.mirror_x = 1
    stack.origin_x = stack.pos_x
    stack.multiplication = 0
    stack.id = "_1P"
    stack.VAR_numbers = ""
  elseif player_num == 2 then
    stack.pos_x = 248
    stack.score_x = 642
    stack.mirror_x = -1
    stack.origin_x = stack.pos_x + (stack.canvas:getWidth() / GFX_SCALE) - 8
    stack.multiplication = 1
    stack.id = "_2P"
  end
  stack.pos_y = 4 + (108) / GFX_SCALE
  stack.score_y = 208
end

function Stack.divergenceString(stackToTest)
  local result = ""

  local panels = stackToTest.panels

  if panels then
    for i = #panels, 1, -1 do
      for j = 1, #panels[i] do
        result = result .. (tostring(panels[i][j].color)) .. " "
        if panels[i][j].state ~= Panel.states.normal then
          result = result .. (panels[i][j].state) .. " "
        end
      end
      result = result .. "\n"
    end
  end

  if stackToTest.telegraph then
    result = result .. "telegraph.chain count " .. stackToTest.telegraph.garbageQueue.chainGarbage:len() .. "\n"
    result = result .. "telegraph.senderCurrentlyChaining " .. tostring(stackToTest.telegraph.senderCurrentlyChaining) .. "\n"
    result = result .. "telegraph.attacks " .. table.length(stackToTest.telegraph.attacks) .. "\n"
  end

  result = result .. "garbage_q " .. stackToTest.garbage_q:len() .. "\n"
  result = result .. "later_garbage " .. table.length(stackToTest.later_garbage) .. "\n"
  result = result .. "Stop " .. stackToTest.stop_time .. "\n"
  result = result .. "Pre Stop " .. stackToTest.pre_stop_time .. "\n"
  result = result .. "Shake " .. stackToTest.shake_time .. "\n"
  result = result .. "Displacement " .. stackToTest.displacement .. "\n"
  result = result .. "Clock " .. stackToTest.CLOCK .. "\n"
  result = result .. "Panel Buffer " .. stackToTest.panel_buffer .. "\n"

  return result
end

-- Backup important variables into the passed in variable to be restored in rollback. Note this doesn't do a full copy.
-- param source the stack to copy from
-- param other the variable to copy to
function Stack.rollbackCopy(source, other)
  if other == nil then
    if #source.clonePool == 0 then
      other = {}
    else
      other = source.clonePool[#source.clonePool]
      source.clonePool[#source.clonePool] = nil
    end
  end
  other.do_swap = source.do_swap
  other.speed = source.speed
  other.health = source.health

  if other.currentGarbageDropColumnIndexes == nil then
    other.currentGarbageDropColumnIndexes = {}
  end
  for garbageWidth = 1, #source.currentGarbageDropColumnIndexes do
    other.currentGarbageDropColumnIndexes[garbageWidth] = source.currentGarbageDropColumnIndexes[garbageWidth]
  end

  other.later_garbage = deepcpy(source.later_garbage)
  other.garbage_q = source.garbage_q:makeCopy()
  if source.telegraph then
    other.telegraph = Telegraph.rollbackCopy(source.telegraph, other.telegraph)
  end
  local width = source.width or other.width
  local height_to_cpy = #source.panels
  other.panels = other.panels or {}
  local startRow = 1
  if source.panels[0] then
    startRow = 0
  end
  other.panelsCreatedCount = source.panelsCreatedCount
  for i = startRow, height_to_cpy do
    if other.panels[i] == nil then
      other.panels[i] = {}
      for j = 1, width do
        -- other isn't a stack object and therefore doesn't know the method
        -- as all fields will get overwritten anyway further below, it doesn't matter that this is being overwritten
        other.panels[i][j] = Stack.createPanel(other, i, j)
      end
    end
    for j = 1, width do
      local opanel = other.panels[i][j]
      local spanel = source.panels[i][j]
      opanel:clear(true, true)
      for k, v in pairs(spanel) do
        opanel[k] = v
      end
    end
  end
  -- this is too eliminate offscreen rows of chain garbage higher up that the clone might have had
  for i = height_to_cpy + 1, #other.panels do
    other.panels[i] = nil
  end

  other.countdown_CLOCK = source.countdown_CLOCK
  other.starting_cur_row = source.starting_cur_row
  other.starting_cur_col = source.starting_cur_col
  other.countdown_cursor_state = source.countdown_cursor_state
  other.countdown_cur_speed = source.countdown_cur_speed
  other.countdown_timer = source.countdown_timer
  other.CLOCK = source.CLOCK
  other.game_stopwatch = source.game_stopwatch
  other.game_stopwatch_running = source.game_stopwatch_running
  other.prev_rise_lock = source.prev_rise_lock
  other.rise_lock = source.rise_lock
  other.top_cur_row = source.top_cur_row
  other.cursor_lock = source.cursor_lock
  other.displacement = source.displacement
  other.nextSpeedIncreaseClock = source.nextSpeedIncreaseClock
  other.panels_to_speedup = source.panels_to_speedup
  other.stop_time = source.stop_time
  other.pre_stop_time = source.pre_stop_time
  other.score = source.score
  other.chain_counter = source.chain_counter
  other.n_active_panels = source.n_active_panels
  other.n_prev_active_panels = source.n_prev_active_panels
  other.rise_timer = source.rise_timer
  other.manual_raise = source.manual_raise
  other.manual_raise_yet = source.manual_raise_yet
  other.prevent_manual_raise = source.prevent_manual_raise
  other.cur_timer = source.cur_timer
  other.cur_dir = source.cur_dir
  other.cur_row = source.cur_row
  other.cur_col = source.cur_col
  other.shake_time = source.shake_time
  other.peak_shake_time = source.peak_shake_time
  other.do_countdown = source.do_countdown
  other.ready_y = source.ready_y
  other.panel_buffer = source.panel_buffer
  other.gpanel_buffer = source.gpanel_buffer
  other.panelGenCount = source.panelGenCount
  other.garbageGenCount = source.garbageGenCount
  other.panels_in_top_row = source.panels_in_top_row
  other.has_risen = source.has_risen
  other.metal_panels_queued = source.metal_panels_queued
  other.panels_cleared = source.panels_cleared
  other.danger_timer = source.danger_timer
  other.analytic = deepcpy(source.analytic)
  other.game_over_clock = source.game_over_clock
  other.currentChainStartFrame = source.currentChainStartFrame

  return other
end

function Stack.restoreFromRollbackCopy(self, other)
  Stack.rollbackCopy(other, self)
  if self.telegraph then
    self.telegraph.receiver = self.garbage_target
    self.telegraph.sender = self
  end
  -- The remaining inputs is the confirmed inputs not processed yet for this clock time
  -- We have processed CLOCK time number of inputs when we are at CLOCK, so we only want to process the CLOCK+1 input on
  self.input_buffer = {}
  for i = self.CLOCK + 1, #self.confirmedInput do
    self.input_buffer[#self.input_buffer + 1] = self.confirmedInput[i]
  end
end

function Stack.rollbackToFrame(self, frame)
  local currentFrame = self.CLOCK
  local difference = currentFrame - frame
  local safeToRollback = difference <= MAX_LAG
  if not safeToRollback then
    if self.garbage_target then
      self.garbage_target.tooFarBehindError = true
    end
    return false -- EARLY RETURN
  end

  if frame < currentFrame then
    local prev_states = self.prev_states
    logger.debug("Rolling back " .. self.which .. " to " .. frame)
    assert(prev_states[frame])
    self:restoreFromRollbackCopy(prev_states[frame])

    for f = frame, currentFrame do
      self:deleteRollbackCopy(f)
    end

    if self.garbage_target and self.garbage_target.later_garbage then
      -- The garbage that we send this time might (rarely) not be the same
      -- as the garbage we sent before.  Wipe out the garbage we sent before...
      local targetFrame = frame + GARBAGE_DELAY_LAND_TIME
      for k, _ in pairs(self.garbage_target.later_garbage) do
        -- The time we actually affected the target was garbage delay away,
        -- so we only need to remove it if its at least that far away
        if k >= targetFrame then
          self.garbage_target.later_garbage[k] = nil
        end
      end
    end

    for chainFrame, _ in pairs(self.chains) do
      if chainFrame >= frame then
        self.chains[chainFrame] = nil
      end
    end

    -- This variable has already been restored above, if its set, that means a chain is in progress
    -- and we may not have removed the entries that happened before the rollback
    if self.currentChainStartFrame then
      local currentChain = self.chains[self.currentChainStartFrame]
      local size = 0
      for index, chainFrame in ipairs(currentChain.starts) do
        if chainFrame >= frame then
          currentChain.starts[index] = nil
        else
          size = size + 1
        end
      end
      currentChain.finish = nil
      currentChain.size = size + 1
    end

    for comboFrame, _ in pairs(self.combos) do
      if comboFrame >= frame then
        self.combos[comboFrame] = nil
      end
    end

    self.rollbackCount = self.rollbackCount + 1
    self.lastRollbackFrame = currentFrame
  end

  return true
end

function Stack:shouldSaveRollback()
  if not GAME.match then
    return false
  end

  if GAME.match.isFromReplay then
    return true
  end

  -- if we don't have a garbage target, its is assumed we aren't being attacked either, which means we don't need to rollback
  if not self.garbage_target then
    return false
    -- If we are behind the time that the opponent's new attacks would land, then we don't need to rollback
    -- don't save the rollback info for performance reasons
    -- this also includes local play and single player, since the clocks are <= 1 difference
  elseif self.garbage_target.CLOCK + GARBAGE_DELAY_LAND_TIME > self.CLOCK then
    return false
  end

  return true
end

-- Saves state in backups in case its needed for rollback
-- NOTE: the CLOCK time is the save state for simulating right BEFORE that clock time is simulated
function Stack.saveForRollback(self)

  if self:shouldSaveRollback() == false then
    return
  end

  local prev_states = self.prev_states
  local garbage_target = self.garbage_target
  self.garbage_target = nil
  self.prev_states = nil
  self:remove_extra_rows()
  prev_states[self.CLOCK] = Stack.rollbackCopy(self)
  self.prev_states = prev_states
  self.garbage_target = garbage_target
  local deleteFrame = self.CLOCK - MAX_LAG - 1
  self:deleteRollbackCopy(deleteFrame)
end

function Stack.deleteRollbackCopy(self, frame)
  if self.prev_states[frame] then
    if self.telegraph then
      self.telegraph:saveClone(self.prev_states[frame].telegraph)
    end

    -- Has a reference to stacks we don't want kept around
    self.prev_states[frame].telegraph = nil

    self.clonePool[#self.clonePool + 1] = self.prev_states[frame]
    self.prev_states[frame] = nil
  end
end

function Stack.set_garbage_target(self, new_target)
  self.garbage_target = new_target
  if self.telegraph then
    self.telegraph.receiver = new_target
    self.telegraph.graphics:updatePosition()
  end
end

local MAX_TAUNT_PER_10_SEC = 4

function Stack.can_taunt(self)
  return self.taunt_queue:len() < MAX_TAUNT_PER_10_SEC or self.taunt_queue:peek() + 10 < love.timer.getTime()
end

function Stack.taunt(self, taunt_type)
  while self.taunt_queue:len() >= MAX_TAUNT_PER_10_SEC do
    self.taunt_queue:pop()
  end
  self.taunt_queue:push(love.timer.getTime())
end

function Stack.set_puzzle_state(self, puzzle)
  -- Copy the puzzle into our state
  local boardSizeInPanels = self.width * self.height
  while string.len(puzzle.stack) < boardSizeInPanels do
    puzzle.stack = "0" .. puzzle.stack
  end

  local puzzleString = puzzle.stack

  self.puzzle = puzzle
  self.panels = self:puzzleStringToPanels(puzzleString)
  self.do_countdown = puzzle.doCountdown or false
  self.puzzle.remaining_moves = puzzle.moves

  -- transform any cleared garbage into colorless garbage panels
  self.gpanel_buffer = "9999999999999999999999999999999999999999999999999999999999999999999999999"
end

function Stack.puzzleStringToPanels(self, puzzleString)
  local panels = {}
  local garbageId = 0
  local garbageStartRow = nil
  local garbageStartColumn = nil
  local isMetal = false
  local connectedGarbagePanels = nil
  local rowCount = string.len(puzzleString) / 6
  -- chunk the aprilstack into rows
  -- it is necessary to go bottom up because garbage block panels contain the offset relative to their bottom left corner
  for row = 1, rowCount do
    local rowString = string.sub(puzzleString, #puzzleString - 5, #puzzleString)
    puzzleString = string.sub(puzzleString, 1, #puzzleString - 6)
    -- copy the panels into the row
    panels[row] = {}
    for column = 6, 1, -1 do
      local color = string.sub(rowString, column, column)
      if not garbageStartRow and tonumber(color) then
        local panel = self:createPanel(row, column)
        panel.color = tonumber(color)
        panels[row][column] = panel
      else
        -- start of a garbage block
        if color == "]" or color == "}" then
          garbageStartRow = row
          garbageStartColumn = column
          connectedGarbagePanels = {}
          if color == "}" then
            isMetal = true
          end
        end
        local panel = self:createPanel(row, column)
        panel.garbageId = garbageId
        garbageId = garbageId + 1
        panel.isGarbage = true
        panel.color = 9
        panel.y_offset = row - garbageStartRow
        -- iterating the row right to left to make sure we catch the start of each garbage block
        -- but the offset is expected left to right, therefore we can't know the x_offset before reaching the end of the garbage
        -- instead save the column index in that field to calculate it later
        panel.x_offset = column
        panel.metal = isMetal
        panels[row][column] = panel
        table.insert(connectedGarbagePanels, panel)
        -- garbage ends here
        if color == "[" or color == "{" then
          -- calculate dimensions of the garbage and add it to the relevant width/height properties
          local height = connectedGarbagePanels[#connectedGarbagePanels].y_offset + 1
          -- this is disregarding the possible existence of irregularly shaped garbage
          local width = garbageStartColumn - column + 1
          local shake_time = garbage_to_shake_time[width * height]
          for i = 1, #connectedGarbagePanels do
            connectedGarbagePanels[i].x_offset = connectedGarbagePanels[i].x_offset - column
            connectedGarbagePanels[i].height = height
            connectedGarbagePanels[i].width = width
            connectedGarbagePanels[i].shake_time = shake_time
            connectedGarbagePanels[i].garbageId = garbageId
            -- panels are already in the main table and they should already be updated by reference
          end
          garbageStartRow = nil
          garbageStartColumn = nil
          connectedGarbagePanels = nil
          isMetal = false
        end
      end
    end
  end

  -- add row 0 because it crashes if there is no row 0 for whatever reason
  panels[0] = {}
  for column = 6, 1, -1 do
    local panel = self:createPanel(0, column)
    panel.color = 9
    panels[0][column] = panel
  end

  return panels
end

function Stack.toPuzzleInfo(self)
  local puzzleInfo = {}
  if self.match.battleRoom then
    puzzleInfo["Player"] = self.match.battleRoom.playerNames[self.which]
  else
    puzzleInfo["Player"] = config.name
  end
  puzzleInfo["Stop"] = self.stop_time
  puzzleInfo["Shake"] = self.shake_time
  puzzleInfo["Pre-Stop"] = self.pre_stop_time
  puzzleInfo["Stack"] = Puzzle.toPuzzleString(self.panels)

  return puzzleInfo
end

function Stack.puzzle_done(self)
  if not self.do_countdown then
    -- For now don't require active panels to be 0, we will still animate in game over,
    -- and we need to win immediately to avoid the failure below in the chain case.
    -- if P1.n_active_panels == 0 then
    -- if self.puzzle.puzzleType == "chain" or P1.n_prev_active_panels == 0 then
    if self.puzzle.puzzleType == "clear" then
      return not self:hasGarbage()
    else
      local panels = self.panels
      for row = 1, self.height do
        for col = 1, self.width do
          local color = panels[row][col].color
          if color ~= 0 and color ~= 9 then
            return false
          end
        end
      end
    end

    return true
    -- end
    -- end
  end

  return false
end

function Stack.hasGarbage(self)
  -- garbage is more likely to be found at the top of the stack
  for row = #self.panels, 1, -1 do
    for column = 1, #self.panels[row] do
      if self.panels[row][column].isGarbage and self.panels[row][column].state ~= Panel.states.matched then
        return true
      end
    end
  end

  return false
end

function Stack.puzzle_failed(self)
  if not self.do_countdown and not self:hasActivePanels() then
    if self.puzzle.puzzleType == "moves" then
      return self.puzzle.remaining_moves == 0
    elseif self.puzzle.puzzleType == "chain" then
      if #self.analytic.data.reached_chains == 0 and self.analytic.data.destroyed_panels > 0 then
        -- We finished matching but never made a chain -> fail
        return true
      end
      if #self.analytic.data.reached_chains > 0 and not self:hasChainingPanels() then
        -- We achieved a chain, finished chaining, but haven't won yet -> fail
        return true
      end
    elseif self.puzzle.puzzleType == "clear" then
      if self:hasGarbage() then
        return (self.puzzle.moves > 0 and self.puzzle.remaining_moves <= 0) or self.health <= 0
      end
    end
  end

  return false
end

function Stack.hasActivePanels(self)
  return self.n_active_panels > 0 or self.n_prev_active_panels > 0
end

function Stack.has_falling_garbage(self)
  for i = 1, self.height + 3 do -- we shouldn't have to check quite 3 rows above height, but just to make sure...
    local panelRow = self.panels[i]
    for j = 1, self.width do
      if panelRow and panelRow[j].isGarbage and panelRow[j].state == Panel.states.falling then
        return true
      end
    end
  end
  return false
end

-- Setup the stack at a new starting state
function Stack.starting_state(self, n)
  if self.do_first_row then
    self.do_first_row = nil
    for i = 1, (n or 8) do
      self:new_row()
      self.cur_row = self.cur_row - 1
    end
  end
end

function Stack.prep_first_row(self)
  if self.do_first_row then
    self.do_first_row = nil
    self:new_row()
    self.cur_row = self.cur_row - 1
  end
end

-- Takes the control input from input_state and sets up the engine to start using it.
function Stack.controls(self)
  local new_dir = nil
  local sdata = self.input_state
  local raise, swap, up, down, left, right = unpack(base64decode[sdata])
  if (raise) and (not self.prevent_manual_raise) then
    self.manual_raise = true
    self.manual_raise_yet = false
  end

  self.swap_1 = swap
  self.swap_2 = swap

  if up then
    new_dir = "up"
  elseif down then
    new_dir = "down"
  elseif left then
    new_dir = "left"
  elseif right then
    new_dir = "right"
  end

  if new_dir == self.cur_dir then
    if self.cur_timer ~= self.cur_wait_time then
      self.cur_timer = self.cur_timer + 1
    end
  else
    self.cur_dir = new_dir
    self.cur_timer = 0
  end
end

function Stack.shouldRun(self, runsSoFar)

  -- We want to run after game over to show game over effects.
  if self:game_ended() then
    return runsSoFar == 0
  end

  -- Decide how many frames of input we should run.
  local buffer_len = #self.input_buffer

  -- If we are local we always want to catch up and run the new input which is already appended
  if self.is_local then
    return buffer_len > 0
  end

  if self:behindRollback() then
    return true
  end

  -- In debug mode allow forcing a certain number of frames behind
  if config.debug_mode and config.debug_vsFramesBehind and config.debug_vsFramesBehind ~= 0 then
    if (config.debug_vsFramesBehind > 0) == (self.which == 2) then
      -- Don't fall behind if the game is over for the other player
      if self.garbage_target and self.garbage_target:game_ended() == false then
        -- If we are at the end of the replay we want to catch up
        if network_connected() or #self.garbage_target.input_buffer > 0 then
          local framesBehind = math.abs(config.debug_vsFramesBehind)
          if self.CLOCK >= self.garbage_target.CLOCK - framesBehind then
            return false
          end
        end
      end
    end
  end

  -- If we are not local, we want to run faster to catch up.
  if buffer_len >= 15 - runsSoFar then
    -- way behind, run at max speed.
    return runsSoFar < self.max_runs_per_frame
  elseif buffer_len >= 10 - runsSoFar then
    -- When we're closer, run fewer times per frame, so things are less choppy.
    -- This might have a side effect of taking a little longer to catch up
    -- since we don't always run at top speed.
    local maxRuns = math.min(2, self.max_runs_per_frame)
    return runsSoFar < maxRuns
  elseif buffer_len >= 1 then
    return runsSoFar == 0
  end

  return false
end

-- Runs one step of the stack.
function Stack.run(self)
  if GAME.gameIsPaused then
    return
  end

  if self.is_local == false then
    if self.play_to_end then
      GAME.preventSounds = true
      if #self.input_buffer < 4 then
        self.play_to_end = nil
        GAME.preventSounds = false
      end
    end
  end

  self:setupInput()
  self:simulate()
end

-- Grabs input from the buffer of inputs or from the controller and sends out to the network if needed.
function Stack.setupInput(self)
  self.input_state = nil

  if self:game_ended() == false then
    if self.input_buffer and #self.input_buffer > 0 then
      self.input_state = table.remove(self.input_buffer, 1)
    end
  else
    self.input_state = self:idleInput()
  end

  self:controls()
end

function Stack.receiveConfirmedInput(self, input)
  if string.len(input) == 1 then
    self.confirmedInput[#self.confirmedInput + 1] = input
    self.input_buffer[#self.input_buffer + 1] = input
  else
    local inputs = string.toCharTable(input)
    table.appendToList(self.confirmedInput, inputs)
    table.appendToList(self.input_buffer, inputs)
  end
  -- logger.debug("Player " .. self.which .. " got new input. Total length: " .. #self.confirmedInput)
end

-- Enqueue a card animation
function Stack.enqueue_card(self, chain, x, y, n)
  if self.canvas == nil then
    return
  end

  local card_burstAtlas = nil
  local card_burstParticle = nil
  if config.popfx == true then
    card_burstAtlas = characters[self.character].images["burst"]
    local card_burstFrameDimension = card_burstAtlas:getWidth() / 9
    card_burstParticle = GraphicsUtil:newRecycledQuad(card_burstFrameDimension, 0, card_burstFrameDimension, card_burstFrameDimension,
                                                      card_burstAtlas:getDimensions())
  end
  self.card_q:push({frame = 1, chain = chain, x = x, y = y, n = n, burstAtlas = card_burstAtlas, burstParticle = card_burstParticle})
end

-- Enqueue a pop animation
function Stack.enqueue_popfx(self, x, y, popsize)
  if self.canvas == nil then
    return
  end

  local burstAtlas = nil
  local burstFrameDimension = nil
  local burstParticle = nil
  local bigParticle = nil
  local fadeAtlas = nil
  local fadeFrameDimension = nil
  local fadeParticle = nil
  if characters[self.character].images["burst"] then
    burstAtlas = characters[self.character].images["burst"]
    burstFrameDimension = burstAtlas:getWidth() / 9
    burstParticle = GraphicsUtil:newRecycledQuad(burstFrameDimension, 0, burstFrameDimension, burstFrameDimension,
                                                 burstAtlas:getDimensions())
    bigParticle = GraphicsUtil:newRecycledQuad(0, 0, burstFrameDimension, burstFrameDimension, burstAtlas:getDimensions())
  end
  if characters[self.character].images["fade"] then
    fadeAtlas = characters[self.character].images["fade"]
    fadeFrameDimension = fadeAtlas:getWidth() / 9
    fadeParticle = GraphicsUtil:newRecycledQuad(fadeFrameDimension, 0, fadeFrameDimension, fadeFrameDimension, fadeAtlas:getDimensions())
  end
  self.pop_q:push({
    frame = 1,
    burstAtlas = burstAtlas,
    burstFrameDimension = burstFrameDimension,
    burstParticle = burstParticle,
    fadeAtlas = fadeAtlas,
    fadeFrameDimension = fadeFrameDimension,
    fadeParticle = fadeParticle,
    bigParticle = bigParticle,
    bigTimer = 0,
    popsize = popsize,
    x = x,
    y = y
  })
end

local d_col = {up = 0, down = 0, left = -1, right = 1}
local d_row = {up = 1, down = -1, left = 0, right = 0}

function Stack.hasPanelsInTopRow(self)
  local panelRow = self.panels[self.height]
  for idx = 1, self.width do
    if panelRow[idx]:dangerous() then
      return true
    end
  end
  return false
end

function Stack.updateDangerBounce(self)
  -- calculate which columns should bounce
  self.danger = false
  local panelRow = self.panels[self.height - 1]
  for idx = 1, self.width do
    if panelRow[idx]:dangerous() then
      self.danger = true
      self.danger_col[idx] = true
    else
      self.danger_col[idx] = false
    end
  end
  if self.danger then
    if self.panels_in_top_row and self.speed ~= 0 and self.match.mode ~= "puzzle" then
      -- Player has topped out, panels hold the "flattened" frame
      self.danger_timer = 15
    elseif self.stop_time == 0 then
      self.danger_timer = self.danger_timer - 1
    end
    if self.danger_timer < 0 then
      self.danger_timer = 17
    end
  end
end
-- determine whether to play danger music
-- Changed this to play danger when something in top 3 rows
-- and to play normal music when nothing in top 3 or 4 rows
function Stack.shouldPlayDangerMusic(self)
  if not self.danger_music then
    -- currently playing normal music
    for row = self.height - 2, self.height do
      local panelRow = self.panels[row]
      for column = 1, self.width do
        if panelRow[column].color ~= 0 and panelRow[column].state ~= Panel.states.falling or panelRow[column]:dangerous() then
          if self.shake_time > 0 then
            return false
          else
            return true
          end
        end
      end
    end
  else
    -- currently playing danger
    local minRowForDangerMusic = self.height - 2
    if config.danger_music_changeback_delay then
      minRowForDangerMusic = self.height - 3
    end
    for row = minRowForDangerMusic, self.height do
      local panelRow = self.panels[row]
      if panelRow ~= nil and type(panelRow) == "table" then
        for column = 1, self.width do
          if panelRow[column].color ~= 0 then
            return true
          end
        end
      elseif self.warningsTriggered["Panels Invalid"] == nil then
        logger.warn("Panels have invalid data in them, please tell your local developer." .. dump(panels, true))
        self.warningsTriggered["Panels Invalid"] = true
      end
    end
  end

  return false
end

function Stack.updatePanels(self)
  self.shake_time_on_frame = 0
  for row = 1, #self.panels do
    for col = 1, self.width do
      self.panels[row][col]:update(self.panels)
    end
  end
end

function Stack.shouldDropGarbage(self)
  -- this is legit ugly, these should rather be returned in a parameter table
  -- or even better in a dedicated garbage class table
  local garbage = self.garbage_q:peek()

  -- new garbage can't drop if the stack is full
  -- new garbage always drops one by one
  if not self.panels_in_top_row and not self:has_falling_garbage() then
    if garbage.height > 1 then
      -- drop chain garbage higher than 1 row immediately
      return garbage.isChain
      -- there is a gap here for combo garbage higher than 1 but unless you implement a meme mode,
      -- that doesn't exist anyway
    else
      -- otherwise garbage should only be dropped if there are no active panels
      return not self:hasActivePanels()
    end
  end
end

-- One run of the engine routine.
function Stack.simulate(self)
  -- Don't run the main logic if the player has simulated past one of the game overs or the time attack time
  if self:game_ended() == false then
    self:prep_first_row()
    local panels = self.panels
    local panel = nil
    local swapped_this_frame = nil
    self.garbageLandedThisFrame = {}
    if self.do_countdown then
      self.game_stopwatch_running = false
      self.rise_lock = true
      if not self.countdown_cursor_state then
        self.countdown_CLOCK = self.CLOCK
        self.starting_cur_row = self.cur_row
        self.starting_cur_col = self.cur_col
        self.cur_row = self.height
        self.cur_col = self.width - 1
        self.countdown_cursor_state = "ready_falling"
        self.countdown_cur_speed = 4 -- one move every this many frames
        self.cursor_lock = true
      end
      if self.countdown_CLOCK == 8 then
        self.countdown_cursor_state = "moving_down"
        self.countdown_timer = 180 -- 3 seconds at 60 fps
      elseif self.countdown_cursor_state == "moving_down" then
        -- move down
        if self.cur_row == self.starting_cur_row then
          self.countdown_cursor_state = "moving_left"
        elseif self.CLOCK % self.countdown_cur_speed == 0 then
          self.cur_row = self.cur_row - 1
        end
      elseif self.countdown_cursor_state == "moving_left" then
        -- move left
        if self.cur_col == self.starting_cur_col then
          self.countdown_cursor_state = "ready"
          self.cursor_lock = nil
        elseif self.CLOCK % self.countdown_cur_speed == 0 then
          self.cur_col = self.cur_col - 1
        end
      end
      if self.countdown_timer then
        if self.countdown_timer == 0 then
          -- we are done counting down
          self.do_countdown = nil
          self.countdown_timer = nil
          self.starting_cur_row = nil
          self.starting_cur_col = nil
          self.countdown_CLOCK = nil
          self.game_stopwatch_running = true
          if self.which == 1 and self:shouldChangeSoundEffects() then
            SFX_Go_Play = 1
          end
        elseif self.countdown_timer and self.countdown_timer % 60 == 0 and self.which == 1 then
          -- play beep for timer dropping to next second in 3-2-1 countdown
          if self.which == 1 and self:shouldChangeSoundEffects() then
            SFX_Countdown_Play = 1
          end
        end
        if self.countdown_timer then
          self.countdown_timer = self.countdown_timer - 1
        end
      end
      if self.countdown_CLOCK then
        self.countdown_CLOCK = self.countdown_CLOCK + 1
      end
    else
      self.game_stopwatch_running = true
    end

    if self.pre_stop_time ~= 0 then
      self.pre_stop_time = self.pre_stop_time - 1
    elseif self.stop_time ~= 0 then
      self.stop_time = self.stop_time - 1
    end

    self.panels_in_top_row = self:hasPanelsInTopRow()
    self:updateDangerBounce()
    self.danger_music = self:shouldPlayDangerMusic()

    if self.displacement == 0 and self.has_risen then
      self.top_cur_row = self.height
      self:new_row()
    end

    self:updateRiseLock()

    -- Increase the speed if applicable
    if self.speedIncreaseMode == 1 then
      -- increase per interval
      if self.CLOCK == self.nextSpeedIncreaseClock then
        self.speed = min(self.speed + 1, 99)
        self.nextSpeedIncreaseClock = self.nextSpeedIncreaseClock + DT_SPEED_INCREASE
      end
    elseif self.panels_to_speedup <= 0 then
      -- mode 2: increase speed based on cleared panels
      self.speed = min(self.speed + 1, 99)
      self.panels_to_speedup = self.panels_to_speedup + panels_to_next_speed[self.speed]
    end

    -- Phase 0 //////////////////////////////////////////////////////////////
    -- Stack automatic rising
    if self.speed ~= 0 and not self.manual_raise and self.stop_time == 0 and not self.rise_lock then
      if self.match.mode == "puzzle" then
        -- only reduce health after the first swap to give the player a chance to strategize
        if self.puzzle.puzzleType == "clear" and self.puzzle.remaining_moves - self.puzzle.moves < 0 and self.shake_time < 1 then
          self.health = self.health - 1
          -- no gameover because it can't return otherwise, exit is taken care of by puzzle_failed
        end
      else
        if self.panels_in_top_row then
          self.health = self.health - 1
          if self.health < 1 and self.shake_time < 1 then
            self:set_game_over()
          end
        else
          if self.match.mode ~= "puzzle" then
            self.rise_timer = self.rise_timer - 1
            if self.rise_timer <= 0 then -- try to rise
              self.displacement = self.displacement - 1
              if self.displacement == 0 then
                self.prevent_manual_raise = false
                self.top_cur_row = self.height
                self:new_row()
              end
              self.rise_timer = self.rise_timer + speed_to_rise_time[self.speed]
            end
          end
        end
      end
    end

    if not self.panels_in_top_row and self.match.mode ~= "puzzle" and not self:has_falling_garbage() then
      self.health = self.max_health
    end

    if self.displacement % 16 ~= 0 then
      self.top_cur_row = self.height - 1
    end

    -- Begin the swap we input last frame.
    if self.do_swap then
      self:swap()
      swapped_this_frame = true
      self.do_swap = nil
    end

    -- Look for matches.
    self:checkMatches()

    self:updatePanels()

    local prev_shake_time = self.shake_time
    self.shake_time = self.shake_time - 1
    self.shake_time = max(self.shake_time, self.shake_time_on_frame)
    if self.shake_time == 0 then
      self.peak_shake_time = 0
    end

    -- Phase 3. /////////////////////////////////////////////////////////////
    -- Actions performed according to player input

    -- CURSOR MOVEMENT
    local playMoveSounds = true -- set this to false to disable move sounds for debugging
    if self.cur_dir and (self.cur_timer == 0 or self.cur_timer == self.cur_wait_time) and not self.cursor_lock then
      local prev_row = self.cur_row
      local prev_col = self.cur_col
      self.cur_row = bound(1, self.cur_row + d_row[self.cur_dir], self.top_cur_row)
      self.cur_col = bound(1, self.cur_col + d_col[self.cur_dir], self.width - 1)
      if (playMoveSounds and (self.cur_timer == 0 or self.cur_timer == self.cur_wait_time) and
          (self.cur_row ~= prev_row or self.cur_col ~= prev_col)) then
        if self:shouldChangeSoundEffects() then
          SFX_Cur_Move_Play = 1
        end
        if self.cur_timer ~= self.cur_wait_time then
          self.analytic:register_move()
        end
      end
    else
      self.cur_row = bound(1, self.cur_row, self.top_cur_row)
    end

    if self.cur_timer ~= self.cur_wait_time then
      self.cur_timer = self.cur_timer + 1
    end
    -- TAUNTING
    if self:shouldChangeSoundEffects() then
      if self.taunt_up ~= nil then
        characters[self.character]:playTauntUpSfx(self.taunt_up)
        self:taunt("taunt_up")
        self.taunt_up = nil
      elseif self.taunt_down ~= nil then
        characters[self.character]:playTauntDownSfx(self.taunt_down)
        self:taunt("taunt_down")
        self.taunt_down = nil
      end
    end

    -- SWAPPING
    if (self.swap_1 or self.swap_2) and not swapped_this_frame then
      local leftPanel = self.panels[self.cur_row][self.cur_col]
      local rightPanel = self.panels[self.cur_row][self.cur_col + 1]
      local do_swap = self:canSwapPanels(leftPanel, rightPanel)

      if do_swap then
        self.do_swap = true
        self.analytic:register_swap()
      end
      self.swap_1 = false
      self.swap_2 = false
    end

    -- MANUAL STACK RAISING
    if self.manual_raise and self.match.mode ~= "puzzle" then
      if not self.rise_lock then
        if self.panels_in_top_row then
          self:set_game_over()
        end
        self.has_risen = true
        self.displacement = self.displacement - 1
        if self.displacement == 1 then
          self.manual_raise = false
          self.rise_timer = 1
          if not self.prevent_manual_raise then
            self.score = self.score + 1
          end
          self.prevent_manual_raise = true
        end
        self.manual_raise_yet = true -- ehhhh
        self.stop_time = 0
      elseif not self.manual_raise_yet then
        self.manual_raise = false
      end
      -- if the stack is rise locked when you press the raise button,
      -- the raising is cancelled
    end

    -- if at the end of the routine there are no chain panels, the chain ends.
    if self.chain_counter ~= 0 and not self:hasChainingPanels() then
      self.chains[self.currentChainStartFrame].finish = self.CLOCK
      self.chains[self.currentChainStartFrame].size = self.chain_counter
      self.currentChainStartFrame = nil
      if self:shouldChangeSoundEffects() then
        SFX_Fanfare_Play = self.chain_counter
      end
      self.analytic:register_chain(self.chain_counter)
      self.chain_counter = 0

      if self.garbage_target and self.garbage_target.telegraph then
        self.telegraph:chainingEnded(self.CLOCK)
      end
    end

    if (self.score > 99999) then
      self.score = 99999
      -- lol owned
    end

    self:updateActivePanels()

    if self.telegraph then
      local to_send = self.telegraph:popAllReadyGarbage(self.CLOCK)
      if to_send and to_send[1] then
        -- Right now the training attacks are put on the players telegraph, 
        -- but they really should be a seperate telegraph since the telegraph on the player's stack is for sending outgoing attacks.
        local receiver = self.garbage_target or self
        receiver:receiveGarbage(self.CLOCK + GARBAGE_DELAY_LAND_TIME, to_send)
      end
    end

    if self.later_garbage[self.CLOCK] then
      self.garbage_q:push(self.later_garbage[self.CLOCK])
      self.later_garbage[self.CLOCK] = nil
    end

    self:remove_extra_rows()

    -- double-check panels_in_top_row

    self.panels_in_top_row = false
    -- If any dangerous panels are in the top row, garbage should not fall.
    for col_idx = 1, self.width do
      if panels[self.height][col_idx]:dangerous() then
        self.panels_in_top_row = true
      end
    end

    -- local garbage_fits_in_populated_top_row 
    -- if self.garbage_q:len() > 0 then
    --   --even if there are some panels in the top row,
    --   --check if the next block in the garbage_q would fit anyway
    --   --ie. 3-wide garbage might fit if there are three empty spaces where it would spawn
    --   garbage_fits_in_populated_top_row = true
    --   local next_garbage_block_width, next_garbage_block_height, _metal, from_chain = unpack(self.garbage_q:peek())
    --   local cols = self.garbage_cols[next_garbage_block_width]
    --   local spawn_col = cols[cols.idx]
    --   local spawn_row = #self.panels
    --   for idx=spawn_col, spawn_col+next_garbage_block_width-1 do
    --     if panelRow[idx]:dangerous() then 
    --       garbage_fits_in_populated_top_row = nil
    --     end
    --   end
    -- end

    -- If any panels (dangerous or not) are in rows above the top row, garbage should not fall.
    for row_idx = self.height + 1, #self.panels do
      for col_idx = 1, self.width do
        if panels[row_idx][col_idx].color ~= 0 then
          self.panels_in_top_row = true
        end
      end
    end

    if self.garbage_q:len() > 0 then
      if self:shouldDropGarbage() then
        if self:tryDropGarbage(self.garbage_q:peek()) then
          self.garbage_q:pop()
        end
      end
    end

    -- Update Music
    if self:shouldChangeMusic() then
      if self.do_countdown then
        if SFX_Go_Play == 1 then
          themes[config.theme].sounds.go:stop()
          themes[config.theme].sounds.go:play()
          SFX_Go_Play = 0
        elseif SFX_Countdown_Play == 1 then
          themes[config.theme].sounds.countdown:stop()
          themes[config.theme].sounds.countdown:play()
          SFX_Go_Play = 0
        end
      else
        local winningPlayer = self
        if GAME.battleRoom then
          winningPlayer = GAME.battleRoom:winningPlayer(P1, P2)
        end

        local musics_to_use = nil
        local dynamicMusic = false
        local stageHasMusic = current_stage and stages[current_stage].musics and stages[current_stage].musics["normal_music"]
        local characterHasMusic = winningPlayer.character and characters[winningPlayer.character].musics and
                                      characters[winningPlayer.character].musics["normal_music"]
        if ((current_use_music_from == "stage") and stageHasMusic) or not characterHasMusic then
          if stages[current_stage].music_style == "dynamic" then
            dynamicMusic = true
          end
          musics_to_use = stages[current_stage].musics
        elseif characterHasMusic then
          if characters[winningPlayer.character].music_style == "dynamic" then
            dynamicMusic = true
          end
          musics_to_use = characters[winningPlayer.character].musics
        else
          -- no music loaded
        end

        local wantsDangerMusic = self.danger_music
        if self.garbage_target and self.garbage_target.danger_music then
          wantsDangerMusic = true
        end

        if dynamicMusic then
          local fadeLength = 60
          if not self.fade_music_clock then
            self.fade_music_clock = fadeLength -- start fully faded in
            self.match.current_music_is_casual = true
          end

          local normalMusic = {musics_to_use["normal_music"], musics_to_use["normal_music_start"]}
          local dangerMusic = {musics_to_use["danger_music"], musics_to_use["danger_music_start"]}

          if #currently_playing_tracks == 0 then
            find_and_add_music(musics_to_use, "normal_music")
            find_and_add_music(musics_to_use, "danger_music")
          end

          -- Do we need to switch music?
          if self.match.current_music_is_casual ~= wantsDangerMusic then
            self.match.current_music_is_casual = not self.match.current_music_is_casual

            if self.fade_music_clock >= fadeLength then
              self.fade_music_clock = 0 -- Do a full fade
            else
              -- switched music before we fully faded, so start part way through
              self.fade_music_clock = fadeLength - self.fade_music_clock
            end
          end

          if self.fade_music_clock < fadeLength then
            self.fade_music_clock = self.fade_music_clock + 1
          end

          local fadePercentage = self.fade_music_clock / fadeLength
          if wantsDangerMusic then
            setFadePercentageForGivenTracks(1 - fadePercentage, normalMusic)
            setFadePercentageForGivenTracks(fadePercentage, dangerMusic)
          else
            setFadePercentageForGivenTracks(fadePercentage, normalMusic)
            setFadePercentageForGivenTracks(1 - fadePercentage, dangerMusic)
          end
        else -- classic music
          if wantsDangerMusic then -- may have to rethink this bit if we do more than 2 players
            if (self.match.current_music_is_casual or #currently_playing_tracks == 0) and musics_to_use["danger_music"] then -- disabled when danger_music is unspecified
              stop_the_music()
              find_and_add_music(musics_to_use, "danger_music")
              self.match.current_music_is_casual = false
            elseif #currently_playing_tracks == 0 and musics_to_use["normal_music"] then
              stop_the_music()
              find_and_add_music(musics_to_use, "normal_music")
              self.match.current_music_is_casual = true
            end
          else -- we should be playing normal_music or normal_music_start
            if (not self.match.current_music_is_casual or #currently_playing_tracks == 0) and musics_to_use["normal_music"] then
              stop_the_music()
              find_and_add_music(musics_to_use, "normal_music")
              self.match.current_music_is_casual = true
            end
          end
        end
      end
    end

    -- Update Sound FX
    if self:shouldChangeSoundEffects() then
      if SFX_Swap_Play == 1 then
        themes[config.theme].sounds.swap:stop()
        themes[config.theme].sounds.swap:play()
        SFX_Swap_Play = 0
      end
      if SFX_Cur_Move_Play == 1 then
        if not (self.match.mode == "vs" and themes[config.theme].sounds.swap:isPlaying()) and not self.do_countdown then
          themes[config.theme].sounds.cur_move:stop()
          themes[config.theme].sounds.cur_move:play()
        end
        SFX_Cur_Move_Play = 0
      end
      if self.sfx_land then
        themes[config.theme].sounds.land:stop()
        themes[config.theme].sounds.land:play()
        self.sfx_land = false
      end
      if SFX_Countdown_Play == 1 then
        if self.which == 1 then
          themes[config.theme].sounds.countdown:stop()
          themes[config.theme].sounds.countdown:play()
        end
        SFX_Countdown_Play = 0
      end
      if SFX_Go_Play == 1 then
        if self.which == 1 then
          themes[config.theme].sounds.go:stop()
          themes[config.theme].sounds.go:play()
        end
        SFX_Go_Play = 0
      end
      if self.combo_chain_play then
        -- stop ongoing landing sound
        themes[config.theme].sounds.land:stop()
        -- and cancel it because an attack is performed on the exact same frame (takes priority)
        self.sfx_land = false
        themes[config.theme].sounds.pops[self.lastPopLevelPlayed][self.lastPopIndexPlayed]:stop()
        characters[self.character]:playAttackSfx(self.combo_chain_play)
        self.combo_chain_play = nil
      end
      if SFX_garbage_match_play then
        characters[self.character]:playGarbageMatchSfx()
        SFX_garbage_match_play = nil
      end
      if SFX_Fanfare_Play == 0 then
        -- do nothing
      elseif SFX_Fanfare_Play >= 6 then
        themes[config.theme].sounds.fanfare3:play()
      elseif SFX_Fanfare_Play >= 5 then
        themes[config.theme].sounds.fanfare2:play()
      elseif SFX_Fanfare_Play >= 4 then
        themes[config.theme].sounds.fanfare1:play()
      end
      SFX_Fanfare_Play = 0
      if self.sfx_garbage_thud >= 1 and self.sfx_garbage_thud <= 3 then
        local interrupted_thud = nil
        for i = 1, 3 do
          if themes[config.theme].sounds.garbage_thud[i]:isPlaying() and self.shake_time > prev_shake_time then
            themes[config.theme].sounds.garbage_thud[i]:stop()
            interrupted_thud = i
          end
        end
        if interrupted_thud and interrupted_thud > self.sfx_garbage_thud then
          themes[config.theme].sounds.garbage_thud[interrupted_thud]:play()
        else
          themes[config.theme].sounds.garbage_thud[self.sfx_garbage_thud]:play()
        end
        if interrupted_thud == nil then
          characters[self.character]:playGarbageLandSfx()
        end
        self.sfx_garbage_thud = 0
      end
      if SFX_Pop_Play or SFX_Garbage_Pop_Play then
        local popLevel = min(max(self.chain_counter, 1), 4)
        local popIndex = 1
        if SFX_Garbage_Pop_Play then
          popIndex = min(SFX_Garbage_Pop_Play + self.poppedPanelIndex, 10)
        else
          popIndex = min(self.poppedPanelIndex, 10)
        end
        -- stop the previous pop sound
        themes[config.theme].sounds.pops[self.lastPopLevelPlayed][self.lastPopIndexPlayed]:stop()
        -- play the appropriate pop sound
        themes[config.theme].sounds.pops[popLevel][popIndex]:play()
        self.lastPopLevelPlayed = popLevel
        self.lastPopIndexPlayed = popIndex
        SFX_Pop_Play = nil
        SFX_Garbage_Pop_Play = nil
      end
      if self.game_over or (self.garbage_target and self.garbage_target.game_over) then
        if self:shouldChangeSoundEffects() then
          SFX_GameOver_Play = 1
        end
      end
    end

    self.CLOCK = self.CLOCK + 1

    if self.garbage_target and self.CLOCK > self.garbage_target.CLOCK + MAX_LAG then
      self.garbage_target.tooFarBehindError = true
    end

    local gameEndedClockTime = self.match:gameEndedClockTime()
    if self.game_stopwatch_running and (gameEndedClockTime == 0 or self.CLOCK <= gameEndedClockTime) then
      self.game_stopwatch = (self.game_stopwatch or -1) + 1
    end
  end

  self:update_popfxs()
  self:update_cards()
end

-- Called on a stack by the attacker with the time to start processing the garbage drop
function Stack:receiveGarbage(frameToReceive, garbageList)

  -- If we are past the frame the attack would be processed we need to rollback
  if self.CLOCK > frameToReceive then
    self:rollbackToFrame(frameToReceive)
  end

  local garbage = self.later_garbage[frameToReceive] or {}
  for i = 1, #garbageList do
    garbage[#garbage + 1] = garbageList[i]
  end
  self.later_garbage[frameToReceive] = garbage
end

function Stack:updateFramesBehind()
  if self.garbage_target and self.garbage_target ~= self then
    if not self.framesBehindArray[self.CLOCK] then
      local framesBehind = math.max(0, self.garbage_target.CLOCK - self.CLOCK)
      self.framesBehindArray[self.CLOCK] = framesBehind
      self.totalFramesBehind = self.totalFramesBehind + framesBehind
    end
  end
end

function Stack.behindRollback(self)
  if self.lastRollbackFrame > self.CLOCK then
    return true
  end

  return false
end

function Stack.shouldChangeMusic(self)
  local result = not GAME.gameIsPaused and not GAME.preventSounds

  if result then
    if self:game_ended() or self.canvas == nil then
      result = false
    end

    -- If we are still catching up from rollback don't play sounds again
    if self:behindRollback() then
      result = false
    end

    if self.play_to_end then
      result = false
    end

    if self.garbage_target and self.garbage_target.play_to_end then
      result = false
    end
  end

  return result
end

function Stack.shouldChangeSoundEffects(self)
  local result = self:shouldChangeMusic() and not GAME.muteSoundEffects

  return result
end

function Stack:averageFramesBehind()
  local average = tonumber(string.format("%1.1f", round(self.totalFramesBehind / math.max(self.CLOCK, 1)), 1))
  return average
end

-- Returns true if the stack is simulated past the end of the match.
function Stack.game_ended(self)

  local gameEndedClockTime = self.match:gameEndedClockTime()

  if self.match.mode == "vs" then
    -- Note we use "greater" and not "greater than or equal" because our stack may be currently processing this clock frame.
    -- At the end of the clock frame it will be incremented and we know we have process the game over clock frame.
    if gameEndedClockTime > 0 and self.CLOCK > gameEndedClockTime then
      return true
    end
  elseif self.match.mode == "time" then
    if gameEndedClockTime > 0 and self.CLOCK > gameEndedClockTime then
      return true
    elseif self.game_stopwatch then
      if self.game_stopwatch > time_attack_time * 60 then
        return true
      end
    end
  elseif self.match.mode == "endless" then
    if gameEndedClockTime > 0 and self.CLOCK > gameEndedClockTime then
      return true
    end
  elseif self.match.mode == "puzzle" then
    if self:puzzle_done() or self:puzzle_failed() then
      return true
    end
  end

  return false
end

-- Returns 1 if this player won, 0 for draw, and -1 for loss, nil if no result yet
function Stack.gameResult(self)
  if self:game_ended() == false then
    return nil
  end

  local gameEndedClockTime = self.match:gameEndedClockTime()

  if self.match.mode == "vs" then
    local otherPlayer = self.garbage_target
    if otherPlayer == self or otherPlayer == nil then
      return -1
      -- We can't call it until someone has lost and everyone has played up to that point in time.
    elseif otherPlayer:game_ended() then
      if self.game_over_clock == gameEndedClockTime and otherPlayer.game_over_clock == gameEndedClockTime then
        return 0
      elseif self.game_over_clock == gameEndedClockTime then
        return -1
      elseif otherPlayer.game_over_clock == gameEndedClockTime then
        return 1
      end
    end
  elseif self.match.mode == "time" then
    if gameEndedClockTime > 0 and self.CLOCK > gameEndedClockTime then
      return -1
    elseif self.game_stopwatch then
      if self.game_stopwatch > time_attack_time * 60 then
        return 1
      end
    end
  elseif self.match.mode == "endless" then
    if gameEndedClockTime > 0 and self.CLOCK > gameEndedClockTime then
      return -1
    end
  elseif self.match.mode == "puzzle" then
    if self:puzzle_done() then
      return 1
    elseif self:puzzle_failed() then
      return -1
    end
  end

  return nil
end

-- Sets the current stack as "lost"
-- Also begins drawing game over effects
function Stack.set_game_over(self)

  if self.game_over_clock ~= 0 then
    error("should not set gameover when it is already set")
  end

  self.game_over = true
  self.game_over_clock = self.CLOCK

  if self.canvas then
    local popsize = "small"
    local panels = self.panels
    for row = 1, #panels do
      for col = 1, self.width do
        local panel = panels[row][col]
        panel.state = Panel.states.dead
        if row == #panels then
          self:enqueue_popfx(col, row, popsize)
        end
      end
    end
  end
end

-- Randomly returns a win sound if the character has one
function Stack.pick_win_sfx(self)
  if #characters[self.character].sounds.win ~= 0 then
    return characters[self.character].sounds.win[math.random(#characters[self.character].sounds.win)]
  else
    return themes[config.theme].sounds.fanfare1 -- TODO add a default win sound
  end
end

function Stack:canSwapPanels(leftPanel, rightPanel)
  if math.abs(leftPanel.column - rightPanel.column) ~= 1 or leftPanel.row ~= rightPanel.row then
    -- panels are not horizontally adjacent, can't swap
    return false
  elseif self.do_countdown or self.CLOCK <= 1 then
    -- swapping is not possible during countdown and on the first frame
    return false
  elseif self.puzzle and self.puzzle.moves ~= 0 and self.puzzle.remaining_moves == 0 then
    -- used all available moves in a move puzzle
    return false
  elseif leftPanel.color == 0 and rightPanel.color == 0 then
    -- can't swap two empty spaces with each other
    return false
  elseif not leftPanel:allowsSwap() or not rightPanel:allowsSwap() then
    -- one of the panels can't be swapped based on its state / color / garbage
    return false
  end

  local row = leftPanel.row
  local column = leftPanel.column

  local panels = self.panels
  -- in order for a swap to occur, one of the two panels in
  -- the cursor must not be a non-panel.
  local do_swap = -- also, neither space above us can be hovering.
                      (row == #panels or
                          (panels[row + 1][column].state ~= Panel.states.hovering and panels[row + 1][column + 1].state ~=
                              Panel.states.hovering))
  -- If you have two pieces stacked vertically, you can't move
  -- both of them to the right or left by swapping with empty space.
  -- TODO: This might be wrong if something lands on a swapping panel?
  if panels[row][column].color == 0 or panels[row][column + 1].color == 0 then -- if either panel inside the cursor is air
    do_swap = do_swap -- failing the condition if we already determined we cant swap 
    and not -- one of the next 4 lines must be false in order to swap
    (row ~= self.height -- true if cursor is not at top of stack
    and (panels[row + 1][column].state == Panel.states.swapping and panels[row + 1][column + 1].state == Panel.states.swapping) -- true if BOTH panels above cursor are swapping
    and (panels[row + 1][column].color == 0 or panels[row + 1][column + 1].color == 0) -- true if either panel above the cursor is air
    and (panels[row + 1][column].color ~= 0 or panels[row + 1][column + 1].color ~= 0)) -- true if either panel above the cursor is not air

    do_swap = do_swap -- failing the condition if we already determined we cant swap 
    and not -- one of the next 4 lines must be false in order to swap
    (row ~= 1 -- true if the cursor is not at the bottom of the stack
    and (panels[row - 1][column].state == Panel.states.swapping and panels[row - 1][column + 1].state == Panel.states.swapping) -- true if BOTH panels below cursor are swapping
    and (panels[row - 1][column].color == 0 or panels[row - 1][column + 1].color == 0) -- true if either panel below the cursor is air
    and (panels[row - 1][column].color ~= 0 or panels[row - 1][column + 1].color ~= 0)) -- true if either panel below the cursor is not air
  end

  return do_swap
end

function Stack:canSwapPanelsOld(leftPanel, rightPanel)
  if math.abs(leftPanel.column - rightPanel.column) ~= 1 or leftPanel.row ~= rightPanel.row then
    -- panels are not horizontally adjacent, can't swap
    return false
  elseif self.do_countdown or self.CLOCK <= 1 then
    -- swapping is not possible during countdown and on the first frame
    return false
  elseif self.puzzle and self.puzzle.moves ~= 0 and self.puzzle.remaining_moves == 0 then
    -- used all available moves in a move puzzle
    return false
  elseif leftPanel.color == 0 and rightPanel.color == 0 then
    -- can't swap two empty spaces with each other
    return false
  elseif not leftPanel:allowsSwap() or not rightPanel:allowsSwap() then
    -- one of the panels can't be swapped based on its state / color / garbage
    return false
  end

  local row = leftPanel.row

  local panelAboveLeft
  local panelAboveRight

  if row < self.height then
    panelAboveLeft = self.panels[row + 1][leftPanel.column]
    panelAboveRight = self.panels[row + 1][rightPanel.column]
    -- neither space above us can be hovering
    if panelAboveLeft.state == Panel.states.hovering or panelAboveRight.state == Panel.states.hovering then
      return false
    end

    -- can't swap an empty panel if the panel above is scheduled to fall
    if leftPanel.color == 0 then
      -- a regular panel will always fall, no questions asked
      if (panelAboveLeft.color ~= 0 and not panelAboveLeft.isGarbage) then
        return false
      elseif panelAboveLeft.isGarbage and not panelAboveLeft:supportedFromBelow(self.panels) then
        return false
      end
    end

    -- can't swap an empty panel if the panel above is scheduled to fall
    if rightPanel.color == 0 then
      -- a regular panel will always fall, no questions asked
      if (panelAboveRight.color ~= 0 and not panelAboveRight.isGarbage) then
        return false
      elseif panelAboveRight.isGarbage and not panelAboveRight:supportedFromBelow(self.panels) then
        return false
      end
    end
  end

  local panelBelowLeft
  local panelBelowRight

  if row > 1 then
    panelBelowLeft = self.panels[row - 1][leftPanel.column]
    panelBelowRight = self.panels[row - 1][rightPanel.column]

    -- can't swap if the panel is scheduled to fall
    if leftPanel.color ~= 0 then
      if panelBelowLeft.state == Panel.states.falling then
        return false
      elseif panelBelowLeft.color == 0 then
        return false
      end
    end
    if rightPanel.color ~= 0 then
      if panelAboveRight == Panel.states.falling then
        return false
      elseif panelBelowRight.color == 0 then
        return false
      end
    end
  end

  -- If you have two pieces stacked vertically, 
  -- you can't move both of them to the right or left by swapping with empty space
  -- TODO: This might be wrong if something lands on a swapping panel?
  if leftPanel.color == 0 or rightPanel == 0 then
    -- true if we're not in the top row
    if panelAboveLeft and panelAboveRight -- true if BOTH panels above cursor are swapping
    and (panelAboveLeft.state == "swapping" and panelAboveRight.state == "swapping") -- -- these two together are true if 1 panel is air, the other isn't
    and (panelAboveLeft.color == 0 or panelAboveRight.color == 0) and (panelAboveLeft.color ~= 0 or panelAboveRight.color ~= 0) then
      return false
    elseif panelBelowLeft and panelBelowRight -- true if BOTH panels below cursor are swapping
    and (panelBelowLeft.state == Panel.states.swapping and panelBelowRight.state == Panel.states.swapping) -- -- these two together are true if 1 panel is air, the other isn't
    and (panelBelowLeft.color == 0 or panelBelowRight.color == 0) and (panelBelowLeft.color ~= 0 or panelBelowRight.color ~= 0) then
      return false
    end
  end

  return true
end

function Stack.canSwap(self, row, column)
  local panels = self.panels
  -- in order for a swap to occur, one of the two panels in
  -- the cursor must not be a non-panel.
  local do_swap = (panels[row][column].color ~= 0 or panels[row][column + 1].color ~= 0) and -- also, both spaces must be swappable.
  panels[row][column]:allowsSwap() and panels[row][column + 1]:allowsSwap() and -- also, neither space above us can be hovering.
                      (row == #panels or
                          (panels[row + 1][column].state ~= Panel.states.hovering and panels[row + 1][column + 1].state ~=
                              Panel.states.hovering)) and -- also, we can't swap if the game countdown isn't finished
  not self.do_countdown and -- also, don't swap on the first frame
  not (self.CLOCK and self.CLOCK <= 1)
  -- If you have two pieces stacked vertically, you can't move
  -- both of them to the right or left by swapping with empty space.
  -- TODO: This might be wrong if something lands on a swapping panel?
  if panels[row][column].color == 0 or panels[row][column + 1].color == 0 then -- if either panel inside the cursor is air
    do_swap = do_swap -- failing the condition if we already determined we cant swap 
    and not -- one of the next 4 lines must be false in order to swap
    (row ~= self.height -- true if cursor is not at top of stack
    and (panels[row + 1][column].state == Panel.states.swapping and panels[row + 1][column + 1].state == Panel.states.swapping) -- true if BOTH panels above cursor are swapping
    and (panels[row + 1][column].color == 0 or panels[row + 1][column + 1].color == 0) -- true if either panel above the cursor is air
    and (panels[row + 1][column].color ~= 0 or panels[row + 1][column + 1].color ~= 0)) -- true if either panel above the cursor is not air

    do_swap = do_swap -- failing the condition if we already determined we cant swap 
    and not -- one of the next 4 lines must be false in order to swap
    (row ~= 1 -- true if the cursor is not at the bottom of the stack
    and (panels[row - 1][column].state == Panel.states.swapping and panels[row - 1][column + 1].state == Panel.states.swapping) -- true if BOTH panels below cursor are swapping
    and (panels[row - 1][column].color == 0 or panels[row - 1][column + 1].color == 0) -- true if either panel below the cursor is air
    and (panels[row - 1][column].color ~= 0 or panels[row - 1][column + 1].color ~= 0)) -- true if either panel below the cursor is not air
  end

  do_swap = do_swap and (not self.puzzle or self.puzzle.moves == 0 or self.puzzle.remaining_moves > 0)

  return do_swap
end

-- Swaps panels at the current cursor location
function Stack.swap(self)
  local panels = self.panels
  local row = self.cur_row
  local col = self.cur_col
  self:processPuzzleSwap()
  local leftPanel = panels[row][col]
  local rightPanel = panels[row][col + 1]
  leftPanel:startSwap(true)
  rightPanel:startSwap(false)
  Panel.switch(leftPanel, rightPanel, panels)

  if self:shouldChangeSoundEffects() then
    SFX_Swap_Play = 1
  end

  -- If you're swapping a panel into a position
  -- above an empty space or above a falling piece
  -- then you can't take it back since it will start falling.
  if self.cur_row ~= 1 then
    if (panels[row][col].color ~= 0) and (panels[row - 1][col].color == 0 or panels[row - 1][col].state == Panel.states.falling) then
      panels[row][col].dont_swap = true
    end
    if (panels[row][col + 1].color ~= 0) and (panels[row - 1][col + 1].color == 0 or panels[row - 1][col + 1].state == Panel.states.falling) then
      panels[row][col + 1].dont_swap = true
    end
  end

  -- If you're swapping a blank space under a panel,
  -- then you can't swap it back since the panel should
  -- start falling.
  if self.cur_row ~= self.height then
    if panels[row][col].color == 0 and panels[row + 1][col].color ~= 0 then
      panels[row][col].dont_swap = true
    end
    if panels[row][col + 1].color == 0 and panels[row + 1][col + 1].color ~= 0 then
      panels[row][col + 1].dont_swap = true
    end
  end
end

function Stack.processPuzzleSwap(self)
  if self.puzzle then
    if self.puzzle.remaining_moves == self.puzzle.moves and self.puzzle.puzzleType == "clear" then
      -- start depleting stop / shake time
      self.stop_time = self.puzzle.stop_time
      self.shake_time = self.puzzle.shake_time
    end
    self.puzzle.remaining_moves = self.puzzle.remaining_moves - 1
  end
end

-- Removes unneeded rows
function Stack.remove_extra_rows(self)
  local panels = self.panels
  for row = #panels, self.height + 1, -1 do
    local nonempty = false
    local panelRow = panels[row]
    for col = 1, self.width do
      nonempty = nonempty or (panelRow[col].color ~= 0)
    end
    if nonempty then
      break
    else
      panels[row] = nil
    end
  end
end

-- tries to drop a width x height garbage.
-- returns true if garbage was dropped, false otherwise
function Stack.tryDropGarbage(self, garbage)

  logger.debug("trying to drop garbage at frame " .. self.CLOCK)

  -- Do one last check for panels in the way.
  for i = self.height + 1, #self.panels do
    if self.panels[i] then
      for j = 1, self.width do
        if self.panels[i][j] then
          if self.panels[i][j].color ~= 0 then
            logger.trace("Aborting garbage drop: panel found at row " .. tostring(i) .. " column " .. tostring(j))
            return false
          end
        end
      end
    end
  end

  if self.canvas ~= nil then
    logger.trace(string.format("Dropping garbage on player %d - height %d  width %d  %s", self.player_number, garbage.height, garbage.width,
                               garbage.isMetal and "Metal" or ""))
  end

  self:dropGarbage(garbage)

  return true
end

function Stack.getGarbageSpawnColumn(self, garbageWidth)
  local columns = self.garbageSizeDropColumnMaps[garbageWidth]
  local index = self.currentGarbageDropColumnIndexes[garbageWidth]
  local spawnColumn = columns[index]
  -- the next piece of garbage of that width should fall at a different idx
  self.currentGarbageDropColumnIndexes[garbageWidth] = wrap(1, index + 1, #columns)
  return spawnColumn
end

function Stack.dropGarbage(self, garbage)
  -- garbage always drops in row 13
  local originRow = self.height + 1
  -- combo garbage will alternate it's spawn column
  local originCol = self:getGarbageSpawnColumn(garbage.width)
  local function isPartOfGarbage(column)
    return column >= originCol and column < (originCol + garbage.width)
  end

  self.garbageCreatedCount = self.garbageCreatedCount + 1
  local shakeTime = garbage_to_shake_time[garbage.width * garbage.height]

  for row = originRow, originRow + garbage.height - 1 do
    if not self.panels[row] then
      self.panels[row] = {}
      -- every row that will receive garbage needs to be fully filled up
      -- so iterate from 1 to stack width instead of column to column + width - 1
      for col = 1, self.width do
        self.panels[row][col] = self:createPanel(row, col)

        if isPartOfGarbage(col) then
          local panel = self.panels[row][col]
          panel.garbageId = self.garbageCreatedCount
          panel.isGarbage = true
          panel.color = 9
          panel.width = garbage.width
          panel.height = garbage.height
          panel.y_offset = row - originRow
          panel.x_offset = col - originCol
          panel.shake_time = shakeTime
          panel.state = Panel.states.falling
          panel.row = row
          panel.column = col
          panel.metal = garbage.isMetal
        end
      end
    end
  end
end

-- Adds a new row to the play field
function Stack.new_row(self)
  local panels = self.panels
  -- move cursor up
  self.cur_row = bound(1, self.cur_row + 1, self.top_cur_row)

  -- create new row at the top
  local stackHeight = #panels + 1
  panels[stackHeight] = {}

  for col = 1, self.width do
    panels[stackHeight][col] = self:createPanel(stackHeight, col)
  end

  -- move panels up
  for row = stackHeight, 1, -1 do
    for col = #panels[row], 1, -1 do
      Panel.switch(panels[row][col], panels[row - 1][col], panels)
    end
  end

  -- the new row we created earlier at the top is now at row 0!
  -- while the former row 0 is at row 1 and in play
  -- therefore we need to override dimmed state in row 1
  for col = 1, self.width do
    panels[1][col].state = Panel.states.normal
    panels[1][col].stateChanged = true
  end

  if string.len(self.panel_buffer) <= 10 * self.width then
    local opponentLevel = nil
    if self.garbage_target then
      opponentLevel = self.garbage_target.level
    end
    self.panel_buffer = PanelGenerator.makePanels(self.match.seed + self.panelGenCount, self.NCOLORS, self.panel_buffer, self.match.mode,
                                                  self.level, opponentLevel)
    logger.debug("generating panels with seed: " .. self.match.seed + self.panelGenCount .. " buffer: " .. self.panel_buffer)
    self.panelGenCount = self.panelGenCount + 1
  end

  -- assign colors to the new row 0
  local metal_panels_this_row = 0
  if self.metal_panels_queued > 3 then
    self.metal_panels_queued = self.metal_panels_queued - 2
    metal_panels_this_row = 2
  elseif self.metal_panels_queued > 0 then
    self.metal_panels_queued = self.metal_panels_queued - 1
    metal_panels_this_row = 1
  end
  for col = 1, self.width do
    local panel = panels[0][col]
    local this_panel_color = string.sub(self.panel_buffer, col, col)
    -- a capital letter for the place where the first shock block should spawn (if earned), and a lower case letter is where a second should spawn (if earned).  (color 8 is metal)
    if tonumber(this_panel_color) then
      -- do nothing special
    elseif this_panel_color >= "A" and this_panel_color <= "Z" then
      if metal_panels_this_row > 0 then
        this_panel_color = 8
      else
        this_panel_color = PanelGenerator.PANEL_COLOR_TO_NUMBER[this_panel_color]
      end
    elseif this_panel_color >= "a" and this_panel_color <= "z" then
      if metal_panels_this_row > 1 then
        this_panel_color = 8
      else
        this_panel_color = PanelGenerator.PANEL_COLOR_TO_NUMBER[this_panel_color]
      end
    end
    panel.color = this_panel_color + 0
    panel.state = Panel.states.dimmed
  end
  self.panel_buffer = string.sub(self.panel_buffer, 7)
  self.displacement = 16
end

function Stack:getAttackPatternData()

  local data = {}
  data.name = "Player " .. self.which
  data.mergeComboMetalQueue = false
  data.delayBeforeStart = 0
  data.delayBeforeRepeat = 91
  self.currentChainStartFrame = nil
  local defaultEndTime = 70
  local sortedAttackPatterns = {}

  -- Add in all the chains by time
  for time, currentChain in pairsSortedByKeys(self.chains) do
    local endTime = currentChain.finish or currentChain.starts[#currentChain.starts] + defaultEndTime
    if sortedAttackPatterns[time] == nil then
      sortedAttackPatterns[time] = {}
    end
    local attackPatternBucket = sortedAttackPatterns[time]
    attackPatternBucket[#attackPatternBucket + 1] = {chain = currentChain.starts, chainEndTime = endTime}
  end

  -- Add in all the combos by time
  for time, combos in pairsSortedByKeys(self.combos) do
    for index, garbage in ipairs(combos) do
      if sortedAttackPatterns[time] == nil then
        sortedAttackPatterns[time] = {}
      end
      local attackPatternBucket = sortedAttackPatterns[time]
      attackPatternBucket[#attackPatternBucket + 1] = {
        width = garbage.width,
        height = garbage.height,
        startTime = time,
        chain = false,
        metal = garbage.metal
      }
    end
  end

  -- Save the final attack patterns in sorted order without the times since the file format doesn't want that (duplicate data)
  data.attackPatterns = {}
  for _, attackPatterns in pairsSortedByKeys(sortedAttackPatterns) do
    for _, attackPattern in ipairs(attackPatterns) do
      data.attackPatterns[#data.attackPatterns + 1] = attackPattern
    end
  end

  return data
end

function Stack.createPanel(self, row, column)
  self.panelsCreatedCount = self.panelsCreatedCount + 1
  local panel = Panel(self.panelsCreatedCount, row, column, self.FRAMECOUNTS)
  panel.onPop = function(panel)
    self:onPop(panel)
  end
  panel.onPopped = function(panel)
    self:onPopped(panel)
  end
  panel.onLand = function(panel)
    self:onLand(panel)
  end
  panel.onGarbageLand = function(panel)
    self:onGarbageLand(panel)
  end
  self.panels[row][column] = panel
  return panel
end

function Stack.onPop(self, panel)
  -- logger.debug("POP")
  if (panel.combo_size > 6) or self.chain_counter > 1 then
    popsize = "normal"
  end
  if self.chain_counter > 2 then
    popsize = "big"
  end
  if self.chain_counter > 3 then
    popsize = "giant"
  end
  if config.popfx == true then
    self:enqueue_popfx(panel.column, panel.row, popsize)
  end
  self.score = self.score + 10

  self.panels_cleared = self.panels_cleared + 1
  if self.match.mode == "vs" and self.panels_cleared % level_to_metal_panel_frequency[self.level] == 0 then
    self.metal_panels_queued = min(self.metal_panels_queued + 1, level_to_metal_panel_cap[self.level])
  end
  if self:shouldChangeSoundEffects() then
    SFX_Pop_Play = 1
  end
  self.poppedPanelIndex = panel.combo_index
end

function Stack.onPopped(self, panel)
  if self.panels_to_speedup then
    self.panels_to_speedup = self.panels_to_speedup - 1
  end
end

function Stack.onLand(self, panel)
  if self:shouldChangeSoundEffects() then
    self.sfx_land = true
  end
end

function Stack.onGarbageLand(self, panel)
  if panel.shake_time and panel.state == Panel.states.normal -- only parts of the garbage that are on the visible board can be considered for shake
  and panel.row <= self.height then
    -- runtime optimization to not repeatedly update shaketime for the same piece of garbage
    if not table.contains(self.garbageLandedThisFrame, panel.garbageId) then
      if self:shouldChangeSoundEffects() then
        if panel.height > 3 then
          self.sfx_garbage_thud = 3
        else
          self.sfx_garbage_thud = panel.height
        end
      end
      self.shake_time_on_frame = max(self.shake_time_on_frame, panel.shake_time, self.peak_shake_time or 0)
      -- a smaller garbage block landing should renew the largest of the previous blocks' shake times since our shake time was last zero.
      self.peak_shake_time = max(self.shake_time_on_frame, self.peak_shake_time or 0)

      -- to prevent from running this code dozens of time for the same garbage block
      -- all panels of a garbage block have the same id + shake time
      self.garbageLandedThisFrame[#self.garbageLandedThisFrame + 1] = panel.garbageId
    end

    -- whether we ran through it or not, the panel should lose its shake time
    panel.shake_time = nil
  end
end

function Stack.hasChainingPanels(self)
  -- row 0 panels can never chain cause they're dimmed
  for row = 1, #self.panels do
    for col = 1, self.width do
      local panel = self.panels[row][col]
      if panel.chaining and panel.color ~= 0 then
        return true
      end
    end
  end

  return false
end

function Stack.updateActivePanels(self)
  self.n_prev_active_panels = self.n_active_panels
  self.n_active_panels = #self:getActivePanels()
end

function Stack.getActivePanels(self)
  local activePanels = {}

  for row = 1, self.height do
    for col = 1, self.width do
      local panel = self.panels[row][col]
      if panel.isGarbage then
        if panel.state ~= Panel.states.normal then
          activePanels[#activePanels + 1] = panel
        end
      else
        if panel.color ~= 0 -- dimmed is implicitly filtered by only checking in row 1 and up
        and panel.state ~= Panel.states.normal and panel.state ~= Panel.states.landing then
          activePanels[#activePanels + 1] = panel
        end
      end
    end
  end

  return activePanels
end

function Stack.updateRiseLock(self)
  self.prev_rise_lock = self.rise_lock
  if self.do_countdown then
    self.rise_lock = true
  elseif self.do_swap then
    self.rise_lock = true
  elseif self.shake_time > 0 then
    self.rise_lock = true
  elseif self:hasActivePanels() then
    self.rise_lock = true
  else
    self.rise_lock = false
  end

  -- prevent manual raise is set true when manually raising
  if self.prev_rise_lock and not self.rise_lock then
    self.prevent_manual_raise = false
  end
end
