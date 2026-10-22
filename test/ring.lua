local ring = require "ring"
local count = 0
local function test(name, run)
  local ok, err = pcall(run)
  if not ok then error(name .. ": " .. tostring(err), 0) end
  count = count + 1
  print("ok - " .. name)
end
local function entitySystem(match)
  return ring.newEntitySystem({
    matchEntity = match or function(self, e)
      return self.world:hasComponent(e, "health")
    end,
    updateEntity = function(self, e)
      self.seen = self.seen or {}
      self.seen[e] = true
    end,
    processEntity = function() end
  })
end

test("message bus publishes and unsubscribes nested subjects", function()
  local bus, calls = ring.newMessageBus(), 0
  local callback = bus:subscribe("+@health", function(value)
    assert(value == 42)
    calls = calls + 1
  end)
  bus:publish("+@health", 42)
  bus:unsubscribe("+@health", callback)
  bus:publish("+@health", 42)
  assert(calls == 1)
end)

test("initial membership contains only matching entity IDs", function()
  local world = ring.newWorld()
  local matching = world:createEntity({ health = {} })
  local other = world:createEntity()
  local system = entitySystem()
  world:addSystem(system)
  world:update(0)
  assert(system.seen[matching])
  assert(not system.seen[other] and not system.seen[true])
  assert(ring.countKeys(system.seen) == 1)
end)

test("component events observe completed changes and update membership", function()
  local world, added, changed, removed = ring.newWorld(), 0, 0, 0
  local system = entitySystem()
  world:addSystem(system)
  local e = world:createEntity()
  world:subscribe("+@", function(c, id, value)
    assert(c == "health" and id == e)
    assert(value == world:getComponent(e, c))
    added = added + 1
  end)
  world:subscribe("~@", function(c, id, value)
    assert(c == "health" and id == e and value.hp == 5)
    changed = changed + 1
  end)
  world:subscribe("-@", function(c, id)
    assert(c == "health" and id == e)
    assert(not world:hasComponent(id, c))
    removed = removed + 1
  end)
  world:addComponent(e, "health")
  assert(system.entities[e])
  world:setComponent(e, "health", "hp", 5)
  world:removeComponent(e, "health")
  assert(not system.entities[e])
  assert(added == 1 and changed == 1 and removed == 1)
end)

test("setComponent refreshes predicates based on values", function()
  local world = ring.newWorld()
  local system = entitySystem(function(self, e)
    local health = self.world:getComponent(e, "health")
    return health and health.hp > 0
  end)
  world:addSystem(system)
  local e = world:createEntity({ health = { hp = 10 } })
  assert(system.entities[e])
  world:setComponent(e, "health", { hp = 0 })
  assert(not system.entities[e])
end)

test("entity lifecycle publishes once and clears data and membership", function()
  local world, created, destroyed = ring.newWorld(), 0, 0
  local system = entitySystem(function() return true end)
  world:addSystem(system)
  world:subscribe("+#", function(e, name)
    assert(type(e) == "number" and name == "hero")
    created = created + 1
  end)
  world:subscribe("-#", function(e, name)
    assert(name == "hero" and world:getEntity(name) == nil)
    assert(world.entities[e] == nil and world:getComponent(e, "health") == nil)
    destroyed = destroyed + 1
  end)
  local e = world:createEntity("hero", { health = {} })
  assert(ring.countKeys(system.entities) == 1 and system.entities[e])
  world:destroyEntity(e)
  assert(next(system.entities) == nil)
  assert(world.entityToName[e] == nil)
  assert(created == 1 and destroyed == 1)
end)

test("false disables publication", function()
  local world = ring.newWorld(false)
  for _, subject in ipairs({ "+#", "-#", "+@", "~@", "-@" }) do
    world:subscribe(subject, function() error("unexpected event") end)
  end
  local e = world:createEntity({ health = {} })
  world:setComponent(e, "health", "hp", 5)
  world:removeComponent(e, "health")
  world:destroyEntity(e)
end)

test("component field reads preserve false and nil", function()
  local world = ring.newWorld()
  local e = world:createEntity({ health = { alive = false, hp = 0 } })
  assert(world:getComponent(e, "health", "alive") == false)
  assert(world:getComponent(e, "health", "missing") == nil)
  assert(world:getComponent(e, "health", "hp") == 0)
end)

test("event system removes shared callbacks on every subject", function()
  local world, calls, destroyed = ring.newWorld(), 0, false
  local callback = function() calls = calls + 1 end
  local system = ring.newEventSystem({
    listeners = { first = callback, second = callback },
    destroy = function() destroyed = true end
  })
  world:addSystem("events", system)
  world:publish("first")
  world:publish("second")
  world:removeSystem("events")
  world:publish("first")
  world:publish("second")
  assert(calls == 2 and destroyed and world:getSystem("events") == nil)
  local empty = ring.newEventSystem({})
  world:addSystem(empty)
  world:removeSystem(empty)
end)

test("entity systems unsubscribe and rebuild membership when readded", function()
  local world = ring.newWorld()
  local system = entitySystem()
  world:addSystem("health", system)
  local e = world:createEntity({ health = {} })
  world:removeSystem(system)
  assert(world:getSystem("health") == nil)
  world:removeComponent(e, "health")
  assert(system.entities[e]) -- Detached system must not receive events.
  world:addSystem(system)
  assert(next(system.entities) == nil)
  world:addComponent(e, "health")
  assert(system.entities[e])
end)

test("removing unknown systems leaves registered systems intact", function()
  local world = ring.newWorld()
  local system = ring.newEventSystem({})
  world:addSystem(system)
  assert(not pcall(function() world:removeSystem("missing") end))
  assert(#world.systems == 1 and world.systems[1] == system)
end)

print(count .. " tests passed")
