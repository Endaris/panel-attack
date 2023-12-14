local NetworkProtocol = require("network.NetworkProtocol")
local class = require("class")
local util = require("util")

-- a message listener listens to exactly ONE type of server message
local MessageListener = class(function(self, messageHeader)
  self.messageHeader = messageHeader
  self.subscriptionList = util.getWeaklyKeyedTable()
end)


-- listens for messages with the specified header
-- passes any messages caught to the registered events
function MessageListener:listen()
  messages = GAME.server_queue:pop_all_with(self.messageHeader)
  for i = 1, #messages do
    local message = messages[i]
    for subscriber, callback in pairs(self.subscriptionList) do
      callback(subscriber, message)
    end
  end
end

function MessageListener:subscribe(subscriber, callback)
  self.subscriptionList[subscriber] = callback
end

function MessageListener:unsubscribe(subscriber)
  self.subscriptionList[subscriber] = nil
end