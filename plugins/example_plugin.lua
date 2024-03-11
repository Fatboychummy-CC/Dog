local example_plugin = {
  name = "example_plugin",
  description = "An example plugin.",
  version = "1.0.0",
  author = "Fatboychummy",
}

local interval_id, listener_id
local state

function example_plugin.init()
  logger.info("Example plugin initialized.")

  interval_id = thready.interval(1, function()
    logger.info("Example plugin interval ran.")
  end)
  listener_id = thready.listen("turtle_response", function(...)
    logger.info("Waw the turtle did a thing poggers", ...)
  end)

  state = loader.request("dog.state")
end

function example_plugin.run()
  while true do
    logger.info("Example plugin main-loop, dog is in state:", state.state)
    sleep(3)
  end
end

function example_plugin.teardown()
  thready.kill(interval_id)
  thready.remove_listener(listener_id)
  logger.info("Example plugin torn down.")
end

return example_plugin