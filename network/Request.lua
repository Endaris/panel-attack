local class = require("class")

-- how many tries (read: frames) it takes for a request to give up waiting for a response
local REQUEST_TIMEOUT = 10 * 60

-- A  simple coroutine wrapper for requests to the server that allows to get the response from the request itself
local Request = class(function(self, messageContent, ...)
  self.messageContent = messageContent
  if ... then
    self.expectedMessages = { ... }
  end
  self.awaitingResponse = false
  self.done = false
end)

-- resumes the coroutine to see if a response arrived
-- returns true if a response arrived and the callback executed
-- if no response arrived, returns false
function Request:tryRunCallback()
  assert(self.awaitingResponse and not self.done, "you're not supposed to try and get a response from this")
  self.responseCheckCount = self.responseCheckCount + 1
  response = server_queue:pop_next_with(unpack(self.expectedMessages))

  if response or self.responseCheckCount > REQUEST_TIMEOUT then
    self.awaitingResponse = false
    self.callback(self.scene, response)
    self.done = true
    return true
  end
end

-- sends the request, updates awaitingResponse status field
function Request:send()
  json_send(self.messageContent)
  if self.callback then
    self.awaitingResponse = true
  else
    self.done = true
  end
end

function Request:setCallback(func, scene)
  -- how often the response was checked already, used for timeout
  self.responseCheckCount = 0
  self.callback = func
  self.scene = scene
end


return Request