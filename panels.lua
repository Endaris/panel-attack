require("graphics_util")
require("graphics.animated_sprite")
local logger = require("logger")
local tableUtils = require("tableUtils")
--defaults: {frames = 1, row = 1, fps = 30, loop = true}
local DEFAULT_PANEL_ANIM =
{
	size =  16,
	normal = {},
	swappingLeft = {},
	swappingRight = {},
	matched = {row = 4}, 
	popping = {row = 4},
	hover = {},
	falling = {frames= 2, row = 2},
	landing = {frames= 4, row = 7, fps = 20, loop = false},
	danger = {frames= 6, row = 3, fps = 20},
	panic = {row = 7},
	dead = {row = 4},
	flash = {frames= 2},
	dimmed = {row = 5}, 
	fromGarbage = {frames= 4, row = 6, fps = 20}
}
local BLANK_PANEL_ANIM =
{
	size = 16,
	normal = {},
	swappingLeft = {},
	swappingRight = {},
	matched = {},
	popping = {},
	hover = {},
	falling = {},
	landing = {},
	danger = {},
	panic = {},
	dead = {},
	flash = {},
	dimmed = {},
	fromGarbage = {}
}
local METAL_PANEL_ANIM =
{
	size = {["width"] = 8,["height"] = 16},
	normal = {},
	falling = {},
	landing = {},
	danger = {},
	panic = {},
	dead = {}
}
local fileUtils = require("FileUtils")
local GraphicsUtil = require("graphics_util")

local METAL_FLASH_PANEL_ANIM =
{
	size = 16,
	flash = {frames = 2},
	matched = {},
	popping = {},
}
local PANEL_ANIM_CONVERTS =
{
	{1,5},
	{2,3},
	{1,2,3,2,1,4},
	{6},
	{7},
	{2,3,4,1},
	{4,3,2,1}
}

local metal_names = {"garbage-L", "garbage-M", "garbage-R", "garbage-flash"}
-- The class representing the panel image data
-- Not to be confused with "Panel" which is one individual panel in the game stack model
Panels =
  class(
  function(self, full_path, folder_name)
    self.path = full_path -- string | path to the panels folder content
    self.id = folder_name -- string | id of the panel set, is also the name of its folder by default, may change in id_init
    self.sheet = false
    self.images = {}
    -- sprite sheets indexed by color
    self.colors = {}
    self.animations = {}
    self.size = 16
  end
)

function Panels:id_init()
  local read_data = {}
  local config_file, err = love.filesystem.newFile(self.path .. "/config.json", "r")
  if config_file then
    local teh_json = config_file:read(config_file:getSize())
    config_file:close()
    for k, v in pairs(json.decode(teh_json)) do
      read_data[k] = v
    end
  end

  if read_data.sheet then
    self.sheet = read_data.sheet
  end

  for i = 0, 12 do
    local name = (i < 9 and "panel-"..tostring(i) or metal_names[i-8])
    if read_data.animations and read_data.animations[name] then
      self.animations[name] = read_data.animations[name]
    else
      self.animations[name] = i ~= 0 and (i < 9 and DEFAULT_PANEL_ANIM or (i ~= 12 and METAL_PANEL_ANIM or METAL_FLASH_PANEL_ANIM)) or BLANK_PANEL_ANIM
    end
  end

  if read_data.id then
    self.id = read_data.id
    return true
  end

  return false
end

-- Recursively load all panel images from the given directory
local function add_panels_from_dir_rec(path)
  local lfs = love.filesystem
  local raw_dir_list = fileUtils.getFilteredDirectoryItems(path)
  for i, v in ipairs(raw_dir_list) do
    local current_path = path .. "/" .. v
    if lfs.getInfo(current_path) and lfs.getInfo(current_path).type == "directory" then
      -- call recursively: facade folder
      add_panels_from_dir_rec(current_path)

      -- init stage: 'real' folder
      local panel_set = Panels(current_path, v)
      local success = panel_set:id_init()

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
    fileUtils.recursiveCopy("panels/__default", "panels/pacci")
    fileUtils.recursiveCopy("default_data/panels", "panels")
    config.defaultPanelsCopied = true
    add_panels_from_dir_rec("panels")
  end

  -- temporary measure to deliver pacci to existing users
  if not panels["pacci"] and os.time() < os.time({year = 2024, month = 1, day = 31}) then
    fileUtils.recursiveCopy("panels/__default", "panels/pacci")
    add_panels_from_dir_rec("panels/pacci")
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

function Panels:load()
  logger.debug("loading panels " .. self.id)
  local function load_panel_img(name)
    local img = GraphicsUtil.loadImageFromSupportedExtensions(self.path .. "/" .. name)
    if not img then
      img = GraphicsUtil.loadImageFromSupportedExtensions("panels/__default/" .. name)
      
      if not img then
        error("Could not find default panel image")
      end
    end

    return img
  end
  -- colors 1-7 are normal colors, 8 is [!], 9 is an empty panel.
  local sheet = nil
  local panelSet = nil
  local panelConverts = {}
  local oldFormat = not love.filesystem.getInfo(self.path.."/".."panels.png")
  if (oldFormat or (not self.sheet)) then
    if oldFormat then
      for i = 1, 9 do
        local img = load_panel_img("panel"..(i ~= 9 and tostring(i).."1" or "00"))
        local width, height = img:getDimensions()
        local newPanel = "panel-"..tostring(i ~= 9 and tostring(i) or "0")
        self.animations[newPanel].size = {width = width, height = width}
        if i ~= 9 then
          local tempCanvas = love.graphics.newCanvas(width*6, height*8)
          tempCanvas:renderTo(function()
              for row, anim in ipairs(PANEL_ANIM_CONVERTS) do
                for count, frame in ipairs(anim) do
                  img = load_panel_img("panel" .. tostring(i) .. tostring(frame))
                  love.graphics.draw(img, width*(count-1), height*(row-1))
                end
              end
            end
          )
          panelConverts[newPanel] = love.graphics.newImage(tempCanvas:newImageData())
          --love.filesystem.write(self.path.."/"..newPanel..".png", tempCanvas:newImageData():encode("png"))
        else
          panelConverts[newPanel] = img
        end
      end

      local metal_oldnames = {"metalend0", "metalmid", "metalend1", "garbageflash"}

      for i = 1, 4 do
        local newPanel = metal_names[i]
        local img = load_panel_img(metal_oldnames[i])
        local width, height = img:getDimensions()
        self.animations[newPanel].size = {width = width, height = height}
        local tempCanvas = love.graphics.newCanvas(i ~= 4 and width or width*2, height)
        tempCanvas:renderTo(function()
            if i ~= 4 then
              love.graphics.draw(img, 0, 0)
            else
              love.graphics.draw(load_panel_img("metalend0"), 0, 0)
              love.graphics.draw(load_panel_img("metalend1"), width/2, 0)
              love.graphics.draw(img, width, 0)
            end
          end
        )
        panelConverts[newPanel] = love.graphics.newImage(tempCanvas:newImageData())
        --love.filesystem.write(self.path.."/"..metal_names[i]..".png", tempCanvas:newImageData():encode("png"))
      end
    end
    -- local newInfo = {
    --   ["id"] = self.id,
    --   ["sheet"] = true,
    --   ["animations"] = self.animations
    -- }
    -- love.filesystem.write(self.path.."/".."config.json", json.encode(newInfo))
  end
  for i = 1, 9 do
    local name = "panel-" .. (i ~= 9 and tostring(i) or "0")
    panelSet = self.animations[name]
    sheet = oldFormat and panelConverts[name] or load_panel_img(name)
    self.colors[i] = {}
    self.colors[i].sheet = sheet
    self.colors[i].batch = love.graphics.newSpriteBatch(sheet)
  end

  self.images.metals = {}
  for i = 1, 4 do
    local name = metal_names[i]
    panelSet = self.animations[name]
    sheet = oldFormat and panelConverts[name] or load_panel_img(name)
    self.images.metals[i] = AnimatedSprite(sheet, i, panelSet, panelSet.size.width, panelSet.size.height)
  end
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

function Panels:addToDrawBatch(panel, danger, dangerTimer)
  local batch = self.colors[panel.color].batch
  local conf
  if panel.state == "normal" then
    if panel.fell_from_garbage then
      conf = self.animations.fromGarbage
    elseif danger then

    else

    end

  end
end

function Panels:draw()

end