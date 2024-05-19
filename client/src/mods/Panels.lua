local logger = require("common.lib.logger")
local tableUtils = require("common.lib.tableUtils")
local fileUtils = require("client.src.FileUtils")
local GraphicsUtil = require("client.src.graphics.graphics_util")

local ANIMATION_STATES = {
  "normal", "landing", "swapping",
  "flash", "face", "popping",
  "hovering", "falling",
  "dimmed", "dead",
  "danger", "panic",
  "garbageBounce"
}
local DEFAULT_PANEL_ANIM =
{
  -- loops
	normal = {frames = {1}},
  -- doesn't loop, fixed duration of 12 frames
	landing = {frames = {4, 3, 2, 1}, durationPerFrame = 3},
  -- doesn't loop, fixed duration of 4 frames
  swapping = {frames = {1}},
  -- loops
	flash = {frames = {5, 1}},
  -- doesn't loop
  face = {frames = {6}},
  -- doesn't loop
	popping = {frames = {6}},
  -- doesn't loop
	hovering = {frames = {1}},
  -- doesn't loop
	falling = {frames = {1}},
  -- loops
  dimmed = {frames = {7}},
  -- doesn't loop
	dead = {frames = {6}},
  -- loops; frames play back to front
  -- danger is special in that there is a frame offset depending on column offset
  -- col 1 and 2 start on frame 3, col 3 and 4 start on frame 4 and col 5 and 6 start on frame 5 of the animation
	danger = {frames = {1, 2, 3, 2, 1, 4}, durationPerFrame = 3},
  -- loops
  panic = {frames = {4}},
  -- doesn't loop; the frames play back to front, fixed to 12 frames
	garbageBounce = {frames = {2, 3, 4, 1}, durationPerFrame = 3},
}

-- The class representing the panel image data
-- Not to be confused with "Panel" which is one individual panel in the game stack model
Panels =
  class(
  function(self, full_path, folder_name)
    self.path = full_path -- string | path to the panels folder content
    self.id = folder_name -- string | id of the panel set, is also the name of its folder by default, may change in json_init
    self.sheet = false
    self.images = {}
    -- sprite sheets indexed by color
    self.sheets = {}
    -- mapping each animation state to a row on the sheet
    self.sheetConfig = {}
    self.batches = {}
    self.size = 16
  end
)

function Panels:json_init()
  local read_data = fileUtils.readJsonFile(self.path .. "/config.json")
  if read_data then
    if read_data.id then
      self.id = read_data.id

      self.name = read_data.name or self.id
      self.type = read_data.type or "single"
      self.animationConfig = read_data.animationConfig or DEFAULT_PANEL_ANIM

      return true
    end
  end

  return false
end

-- Recursively load all panel images from the given directory
local function add_panels_from_dir_rec(path)
  local lfs = love.filesystem
  local raw_dir_list = fileUtils.getFilteredDirectoryItems(path)
  for i, v in ipairs(raw_dir_list) do
    local current_path = path .. "/" .. v
    if lfs.getInfo(current_path, "directory") then
      -- call recursively: facade folder
      add_panels_from_dir_rec(current_path)

      -- init stage: 'real' folder
      local panel_set = Panels(current_path, v)
      local success = panel_set:json_init()

      if success then
        if panels[panel_set.id] ~= nil then
          logger.trace(current_path .. " has been ignored since a panel set with this id has already been found")
        else
          panels[panel_set.id] = panel_set
          panels_ids[#panels_ids + 1] = panel_set.id
        end
      end
    end
  end
end

function panels_init()
  panels = {} -- holds all panels, all of them will be fully loaded
  panels_ids = {} -- holds all panels ids

  add_panels_from_dir_rec("panels")

  if #panels_ids == 0 or (config and not config.defaultPanelsCopied) then
    fileUtils.recursiveCopy("client/assets/panels/__default", "panels/pacci")
    fileUtils.recursiveCopy("client/assets/default_data/panels", "panels")
    config.defaultPanelsCopied = true
    add_panels_from_dir_rec("panels")
  end

  -- add pacci panels if not installed
  if not panels["pacci"] then
    add_panels_from_dir_rec("client/assets/panels/__default")
  end

  -- fix config panel set if it's missing
  if not config.panels or not panels[config.panels] then
    if panels["pacci"] then
      config.panels = "pacci"
    else
      config.panels = tableUtils.getRandomElement(panels_ids)
    end
  end

  for _, panel in pairs(panels) do
    panel:load()
  end
end

local function load_panel_img(path, name)
  local img = GraphicsUtil.loadImageFromSupportedExtensions(path .. "/" .. name)
  if not img then
    img = GraphicsUtil.loadImageFromSupportedExtensions("panels/__default/" .. name)

    if not img then
      error("Could not find default panel image")
    end
  end

  return img
end

function Panels:loadSheets()
  for color = 1, 8 do
    self.sheets[color] = load_panel_img(self.path, "panel-" .. color)
  end
  self.sheetConfig = self.animationConfig
  for i, animationState in ipairs(ANIMATION_STATES) do
    self.sheetConfig[animationState].totalFrames =
        self.sheetConfig[animationState].frames * self.sheetConfig[animationState].durationPerFrame
  end
end

-- 
function Panels:convertSinglesToSheetTexture(color, images)
  local canvas = love.graphics.newCanvas(self.size * 10, self.size * #DEFAULT_PANEL_ANIM)
  canvas:renderTo(function()
    local row = 1
    -- ipairs over a static table so the ordering is definitely consistent
    for _, animationState in ipairs(ANIMATION_STATES) do
      local animationConfig = self.animationConfig[animationState]
      for frameNumber, imageIndex in ipairs(animationConfig.frames) do
        love.graphics.draw(images[color][imageIndex], self.size * (frameNumber - 1), self.size * (row - 1))
      end
      row = row + 1
    end
  end)

  return canvas
end

function Panels:loadSingles()
  local panelFiles = fileUtils.getFilteredDirectoryItems(self.path, "file")
  panelFiles = tableUtils.filter(panelFiles, function(f)
    return string.match(f, "panel%d%d+%.")
  end)
  local images = {}
  for color = 1, 8 do
    images[color] = {}

    local files = tableUtils.filter(panelFiles, function(f)
      return string.match(f, "panel" .. color .. "%d+%.")
    end)

    for i, file in ipairs(files) do
      local index = tonumber(string.match(files[i], "%d+", 6))
      images[color][index] = load_panel_img(self.path, file)
    end
  end

  for color, panelImages in ipairs(images) do
    self.sheets[color] = self:convertSinglesToSheetTexture(color, panelImages)
  end

  for i, animationState in ipairs(ANIMATION_STATES) do
    self.sheetConfig[animationState] =
    {
      row = i,
      durationPerFrame = self.animationConfig[animationState].durationPerFrame or 2,
      frames = #self.animationConfig[animationState]
    }
    self.sheetConfig[animationState].totalFrames =
        self.sheetConfig[animationState].frames * self.sheetConfig[animationState].durationPerFrame
  end
end

function Panels:load()
  logger.debug("loading panels " .. self.id)

  self.greyPanel = load_panel_img(self.path, "panel00")
  self.size = self.greyPanel:getWidth()
  self.scale = 48 / self.size

  self.images.metals = {
    left = load_panel_img("metalend0"),
    mid = load_panel_img("metalmid"),
    right = load_panel_img("metalend1"),
    flash = load_panel_img("garbageflash")
  }

  if self.type == "single" then
    self:loadSingles()
  else
    self:loadSheets()
  end

  for color = 1, 8 do
    self.batches[color] = love.graphics.newSpriteBatch(self.sheets[color], 100, "stream")
  end
  self.quad = love.graphics.newQuad(0, 0, self.size, self.size, self.sheets[1])
end

local function switchFunc(self, panel)
  local floor = math.floor
  local state = panel.state
  local col = panel.column
  local row = panel.row
  local isMetal = panel.metal
  local dangerCount = #panel.animation[panel.color].animations["danger"].quads or 1
  local switch = "normal"
  local frame = 1
  local wait = false
  if state == "matched" then
    local flash_time = self.FRAMECOUNTS.MATCH - panel.timer
    if flash_time >= self.FRAMECOUNTS.FLASH then
      switch = "matched"
    else
      switch = "flash"
    end

    if isMetal and (not panel.timer > panel.pop_time) and panel.y_offset == -1 then
        switch = "fromGarbage"
    end
  elseif state == "popping" then
    switch = "popping"

  elseif panel.state == "falling" then
    switch = "falling"
  
  elseif state == "landing" then
    switch = "landing"

  elseif state == "swapping" and not isMetal then
    if panel.isSwappingFromLeft then
      switch = "swappingLeft"
    else
      switch = "swappingRight"
    end
  elseif state == "dead" then
    switch = "dead"
  elseif state == "dimmed" and not isMetal then
    switch = "dimmed"
  elseif panel.fell_from_garbage then
    switch = "fromGarbage"
  elseif self.danger_col and self.danger_col[col] then
    if self.hasPanelsInTopRow(self) and self.health > 0 then
      switch = "panic"
    else
      switch = "danger"
      frame = wrap(1, floor(self.danger_timer) + floor((col - 1) / 2), dangerCount)
    end
  elseif row == self.cur_row and (col == self.cur_col or col == self.cur_col+1) and not isMetal then
    switch = "hover" 
    wait = panel.currentAnim ~= "normal"
  elseif panel.currentAnim ~= "hover" then
    wait = true
  end
  if isMetal and state == "matched" and
    (not panel.timer > panel.pop_time) and panel.y_offset == -1 then
        switch = "fromGarbage"
        wait = false
  end
  panel.animation[panel.color]:switchAnimation(panel, switch, wait, frame)
end


local ceil = math.ceil
-- draws the panel
-- x, y: relative coordinates on the stack canvas
-- clock: Stack.clock to calculate animation frames
-- danger: nil - no danger, false - regular danger, true - panic
-- dangerTimer: remaining time for which the danger animation continues 
function Panels:drawPanel(panel, x, y, clock, danger, dangerTimer)
  if panel.color == 9 then
    love.graphics.draw(self.greyPanel, x, y, 0, self.scale)
  else
    local batch = self.sheets[panel.color].batch
    local conf
    local frame
    if panel.state == "normal" then
      if panel.fell_from_garbage then
        conf = self.sheetConfig.garbageBounce
        -- fell_from_garbage counts down from 12 to 0
        if panel.fell_from_garbage <= 0 then
          frame = conf.frames
        else
          frame = ceil(panel.fell_from_garbage / conf.durationPerFrame)
        end
      elseif danger ~= nil then
        if danger == false then
          conf = self.sheetConfig.danger
          -- danger_timer counts down from 18 or 15 to 0, depending on what triggered it and then wrapping back to 18
          frame = wrap(1, self.danger_timer + 1 + math.floor((panel.column - 1) / 2), conf.durationPerFrame * conf.frames)
        else
          conf = self.sheetConfig.panic
          frame = (clock / conf.durationPerFrame) % conf.frames
        end
      else
        conf = self.sheetConfig.normal
        frame = (clock / conf.durationPerFrame) % conf.frames
        frame = ceil((clock % conf.totalFrames) / conf.durationPerFrame)

      end
    elseif panel.state == "matched" then
      -- divide between flash and face
      -- matched timer counts down to 0
      local flashTime = self.levelData.frameConstants.FACE - panel.timer
      if flashTime >= 0 then
        conf = self.sheetConfig.face
        frame = ceil((panel.timer % conf.totalFrames) / conf.durationPerFrame)
      else
        conf = self.sheetConfig.flash
        -- flash counts down to panel.frameConstants.FACE
        -- original timer 44
        -- panel timer 23 
        -- frames 3
        -- duration per frame 2
        -- in dem fall 
        frame = ceil((flashTime % conf.totalFrames) / conf.durationPerFrame)
      end
    elseif panel.state == "popped" then
      -- draw nothing
    else
      conf = self.sheetConfig[panel.state]
      if panel.state == "landing" then
        -- landing counts down from 13, ending at 0
      end
    end

    self.quad:setViewport(frame * self.size, (conf.row - 1) * self.size, self.size, self. size)
    batch:add(self.quad, x, y, 0, self.scale)
  end
end

function Panels:draw()
  for color = 1, 8 do
    love.graphics.draw(self.batches[color])
  end
end

return Panels
