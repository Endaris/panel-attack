local logger = require("logger")

local PREFIX_OF_IGNORED_DIRECTORIES = "__"

--@module FileUtils
-- Collection of functions for file operations
local fileUtils = {}

function fileUtils.getFilteredDirectoryItems(path)
  local results = {}

  local directoryList = love.filesystem.getDirectoryItems(path)
  for i = 1, #directoryList do
    local file = directoryList[i]
    
    local startOfFile = string.sub(file, 0, string.len(PREFIX_OF_IGNORED_DIRECTORIES))
   -- macOS sometimes puts these files in folders without warning, they are never useful for PA, so filter them.
    if startOfFile ~= PREFIX_OF_IGNORED_DIRECTORIES and file ~= ".DS_Store" then
      results[#results+1] = file
    end
  end

  return results
end

function fileUtils.getFileNameWithoutExtension(filename)
  return filename:gsub("%..*", "")
end

-- copies a file from the given source to the given destination
function fileUtils.copyFile(source, destination)
  local lfs = love.filesystem
  local source_file = lfs.newFile(source)
  source_file:open("r")
  local source_size = source_file:getSize()
  temp = source_file:read(source_size)
  source_file:close()

  local new_file = lfs.newFile(destination)
  new_file:open("w")
  local success, message = new_file:write(temp, source_size)
  new_file:close()
end

-- copies a file from the given source to the given destination
function fileUtils.recursiveCopy(source, destination)
  local lfs = love.filesystem
  local names = lfs.getDirectoryItems(source)
  local temp
  for i, name in ipairs(names) do
    local info = lfs.getInfo(source .. "/" .. name)
    if info and info.type == "directory" then
      logger.trace("calling recursive_copy(source" .. "/" .. name .. ", " .. destination .. "/" .. name .. ")")
      fileUtils.recursiveCopy(source .. "/" .. name, destination .. "/" .. name)
    elseif info and info.type == "file" then
      local destination_info = lfs.getInfo(destination)
      if not destination_info or destination_info.type ~= "directory" then
        love.filesystem.createDirectory(destination)
      end
      logger.trace("copying file:  " .. source .. "/" .. name .. " to " .. destination .. "/" .. name)

      local source_file = lfs.newFile(source .. "/" .. name)
      source_file:open("r")
      local source_size = source_file:getSize()
      temp = source_file:read(source_size)
      source_file:close()

      local new_file = lfs.newFile(destination .. "/" .. name)
      new_file:open("w")
      local success, message = new_file:write(temp, source_size)
      new_file:close()

      if not success then
        logger.warn(message)
      end
    else
      logger.warn("name:  " .. name .. " isn't a directory or file?")
    end
  end
end

-- Deletes any file matching the target name from the file tree recursively
function fileUtils.recursiveRemoveFiles(folder, targetName)
  local lfs = love.filesystem
  local filesTable = lfs.getDirectoryItems(folder)
  for _, fileName in ipairs(filesTable) do
    local file = folder .. "/" .. fileName
    local info = lfs.getInfo(file)
    if info then
      if info.type == "directory" then
        fileUtils.recursiveRemoveFiles(file, targetName)
      elseif info.type == "file" and fileName == targetName then
        love.filesystem.remove(file)
      end
    end
  end
end

function fileUtils.readJsonFile(file)
  if not love.filesystem.getInfo(file, "file") then
    logger.info("No file at specified path " .. file)
    return nil
  else
    local fileContent, info = love.filesystem.read(file)
    if type(info) == "string" then
      -- info is the number of read bytes if successful, otherwise an error string
      -- thus, if it is of type string, that indicates an error
      logger.warn("Could not read file at path " .. file)
      return nil
    else
      local value, _, errorMsg = json.decode(fileContent)
      if errorMsg then
        logger.error(errorMsg .. ":\n" .. fileContent)
        return nil
      else
        return value
      end
    end
  end
end

return fileUtils