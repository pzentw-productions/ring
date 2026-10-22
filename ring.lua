--- An entity component system implementation (ECS) for lua.
-- @module ring
local ring = {}

ring.COMPONENT_PREFIX = "@"
ring.ENTITY_PREFIX = "#"
ring.ADD_SUFFIX = "+"
ring.SUBTRACT_SUFFIX = "-"
ring.CHANGE_SUFFIX = "~"

ring.copyIpairs = function(a)
  local r = {}
  for k, v in ipairs(a) do r[k] = v end
  return r
end

ring.copyPairs = function(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

ring.countKeys = function(t)
  local i = 0
  for _k, _v in pairs(t) do i = i + 1 end
  return i
end

-- Credits to http://lua-users.org/lists/lua-l/2006-12/msg00414.html
ring.stringSplit = function(s, pat)
  local st, g = 1, s:gmatch("()(" .. pat .. ")")
  local function getter(self, segs, seps, sep, cap1, ...)
    st = sep and seps + #sep
    return s:sub(segs, (seps or 0) - 1), cap1 or sep, ...
  end
  local function splitter(self)
    if st then return getter(s, st, g()) end
  end
  return splitter, s
end

--- Create a new `ring.Entity` table.
-- @tfield string name The name of the entity.
ring.newEntity = function(name, components)
  return { name = name, components = components }
end

--- A definition of a `ring.System`.
-- @table SystemDefinition
-- @tfield ()=>void initialize An optional function which will be called when the system is added to a world.
-- @tfield ()=>void destroy An optional function which will be called when the system is removed from a world.
-- @tfield (delta)=>void update A required function that computes updates before frame processing.
-- @tfield ()=>void process A required function which does per-frame processing.
ring.SystemDefinition = {}

--- A system implementation.
-- @table System
-- @tfield ()=>void initialize An optional function which will be called when the system is added to a world.
-- @tfield ()=>void destroy An optional function which will be called when the system is removed from a world.
-- @tfield (dt)=>void update A required function which performs updates before frame processing.
-- @tfield ()=>void process A required function which performs per-frame processing.
ring.System = {}

--- Create a new `ring.System` table.
-- @function newSystem
-- @tparam ring.SystemDefinition definition A `ring.SystemDefinition` table.
-- @treturn ring.System A `ring.System` table.
ring.newSystem = function(definition)
  local b = {}

  for k, v in pairs(definition) do b[k] = v end

  b.initialize = definition.initialize or function(self)
  end

  b.destroy = definition.destroy or function(self)
  end

  b.update = definition.update or function(self, dt)
    error("SystemDefinition.update must be implemented")
  end

  b.process = definition.process or function(self)
    error("SystemDefinition.process must be implemented")
  end

  return b
end

--- A definition of a `EventSystem`.
-- @table EventSystemDefinition
-- @tfield {{subject, callback},...} listeners A set of subjects to listen to.
-- @tfield ()=>void initialize Optional function which will be called when the system is initialized.
-- @tfield ()=>void destroy Optional function which will be called when the system is destroyed.
ring.EventSystemDefinition = {}

--- An event system implementation.
-- EventSystem is a system that is primarily interested in responding to
-- events that occur on the world to which the system belongs. It accepts a
-- set of subjects mapped to callback functions, the subjects of which will be
-- subscribed to automatically during initialization and unsubscribed from
-- during destruction. The system may implement update and process functions
-- as well, but these are considered optional.
ring.EventSystem = {}

--- Create a new `ring.EventSystem` table.
-- @tparam ring.EventSystemDefinition definition A `ring.EventSystemDefinition` table.
ring.newEventSystem = function(definition)
  local b = ring.copyPairs(definition)

  b.subscriptions = {}

  local subscribe = function(self, subject, callback)
    self.subscriptions[subject] = self.world:subscribe(subject, function(...)
      callback(self, ...)
    end)
  end

  local unsubscribe = function(self, subject, callback)
    self.world:unsubscribe(subject, self.subscriptions[subject])
    self.subscriptions[subject] = nil
  end

  b.initialize = function(self)
    for subject, callback in pairs(self.listeners or {}) do
      subscribe(self, subject, callback)
    end

    if definition.initialize then definition.initialize(self) end
  end

  b.destroy = function(self)
    for subject, callback in pairs(self.listeners or {}) do
      unsubscribe(self, subject, callback)
    end

    if definition.destroy then definition.destroy(self) end
  end

  b.update = definition.update or function(self, dt)
  end

  b.process = definition.process or function(self)
  end

  return b
end

--- A definition of a `ring.EntitySystem`.
-- @table EntitySystemDefinition
-- @tfield ()=>void initialize An optional function which will be called when the system is added to a world.
-- @tfield ()=>void destroy An optional function which will be called when the system is removed from a world.
-- @tfield (entityId)=>void Required function which will be called once per-entity to perform updates before per-frame processing.
-- @tfield (entityId)=>void Required function which will be called once per-entity to perform per-frame processing.
ring.EntitySystemDefinition = {}

--- An entity system implementation.
-- An entity system keeps a set of entity IDs and calls its `updateEntity`
-- and `processEntity` functions iteratively for each entity ID in the set.
-- Membership in the set is determined by a call to `matchEntity` on the
-- following events,
-- (1) `"+#"` aka `entity created`,
-- (2) `"-#"` aka `entity destroyed`,
-- (3) `"+@"` aka `component added`,
-- (4) `"-@"` aka `component removed`,
-- (5) `"~@"` aka `component changed` via `setComponent`.
-- @table EntitySystem
-- @tfield ()=>void initialize An optional function which will be called when the system is added to a world.
-- @tfield ()=>void destroy An optional function which will be called when the system is removed from a world.
-- @tfield (dt,entityId)=>void updateEntity A required function which performs updates before frame processing on all matching entities.
-- @tfield ()=>void processEntity A required function which performs per-frame processing on all matching entities.
ring.EntitySystem = {}

--- Create a new `ring.EntitySystem` table.
-- @tparam EntitySystemDefinition definition A `ring.EntitySystemDefinition` table.
-- @treturn EntitySystem A `ring.EntitySystem` table.
ring.newEntitySystem = function(definition)
  local b = {}

  for k, v in pairs(definition) do b[k] = v end

  b.entities = {}

  local recomputeMembership = function(self, e)
    self.entities[e] = self:matchEntity(e) or nil
  end

  b.initialize = function(self)
    self.entities = {}
    self.subscriptions = {}
    for e in pairs(self.world.entities) do recomputeMembership(self, e) end

    local listeners = {
      ["+#"] = function(e) recomputeMembership(self, e) end,
      ["-#"] = function(e) self.entities[e] = nil end,
      ["+@"] = function(_, e) recomputeMembership(self, e) end,
      ["-@"] = function(_, e) recomputeMembership(self, e) end,
      ["~@"] = function(_, e) recomputeMembership(self, e) end
    }
    for subject, callback in pairs(listeners) do
      self.subscriptions[subject] = self.world:subscribe(subject, callback)
    end

    if definition.initialize then definition.initialize(self) end
  end

  b.destroy = function(self)
    for subject, callback in pairs(self.subscriptions) do
      self.world:unsubscribe(subject, callback)
    end
    self.subscriptions = {}

    if definition.destroy then definition.destroy(self) end
  end

  b.matchEntity = definition.matchEntity or function(self, e)
    error("EntitySystemDefinition.matchEntity must be implemented")
  end

  b.updateEntity = definition.updateEntity or function(self, e, dt)
    error("EntitySystemDefinition.updateEntity must be implemented")
  end

  b.update = function(self, dt)
    for e, _ in pairs(self.entities) do self:updateEntity(e, dt) end

    if definition.update then definition.update(self, dt) end
  end

  b.processEntity = definition.processEntity or function(self, entityId)
    error("EntitySystemDefinition.processEntity must be implemented")
  end

  b.process = function(self)
    for e, _ in pairs(self.entities) do self:processEntity(e) end

    if definition.process then definition.process(self) end
  end

  return b
end

--- A `ring.MessageBus` style subject string.
ring.SubjectString = {}

--- Split a `ring.SubjectString` into a `ring.SubjectParts` array.
-- @tparam ring.SubjectString subject The subject to listen to.
ring.subjectToParts = function(subject)
  local parts = {}

  local char1 = string.sub(subject, 1, 1)

  -- When referring to a built-in change modifier, allow prefixing
  -- the modifier, and ring will automatically use it as the leaf
  -- node.
  -- For example, '+@component' will become '@component.+'
  if char1 == "+" or char1 == "-" or char1 == "~" or char1 == "!" then
    subject = string.sub(subject, 2) .. "." .. char1
    char1 = string.sub(subject, 1, 1)
  end

  -- for part, delim in ring.stringSplit(subject, "([^\\.\\@\\#]+)") do
  for part, delim in ring.stringSplit(subject, "[\\.|(@)|(#)]") do
    if part ~= "" then table.insert(parts, part) end
    if delim == "@" or delim == "#" then table.insert(parts, delim) end
  end

  return parts
end

local newMessageBusNodeContainer = {}

newMessageBusNodeContainer.newMessageBusNode = function()
  local b = {}

  b.children = {}
  b.listeners = {}

  local getOrCreateNodeContainer = {}

  getOrCreateNodeContainer.getOrCreateNode =
      function(self, name)
        local node = self.children[name]
        if not node then
          node = newMessageBusNodeContainer.newMessageBusNode()
          self.children[name] = node
        end
        return node
      end

  local subscribePartsContainer = {}

  subscribePartsContainer.subscribeParts =
      function(self, parts, callback)
        if #parts == 0 then
          self.listeners[callback] = true
        else
          local nextPart = table.remove(parts, 1)
          local nextNode =
              getOrCreateNodeContainer.getOrCreateNode(self, nextPart)
          return
              subscribePartsContainer.subscribeParts(nextNode, parts, callback)
        end
        return callback
      end

  b.subscribeParts = function(self, parts, callback)
    return subscribePartsContainer.subscribeParts(self, ring.copyIpairs(parts),
                                                  callback)
  end

  b.subscribe = function(self, subject, callback)
    return self:subscribeParts(ring.subjectToParts(subject), callback)
  end

  local unsubscribeParts
  unsubscribeParts = function(self, parts, callback)
    if #parts == 0 then
      self.listeners[callback] = nil
    else
      local nextPart = table.remove(parts, 1)
      local nextNode = getOrCreateNodeContainer.getOrCreateNode(self, nextPart)
      return unsubscribeParts(nextNode, parts, callback)
    end
    return callback
  end

  b.unsubscribe = function(self, subject, callback)
    return unsubscribeParts(self, ring.subjectToParts(subject), callback)
  end

  local publishPartsContainer = {}

  publishPartsContainer.publishParts = function(self, parts, ...)
    if #parts == 0 then
      for listener, _ in pairs(self.listeners) do listener(...) end
    else
      local nextPart = table.remove(parts, 1)
      -- if #parts == 0 and nextPart ~= "*" then
      --   local starNode = getOrCreateNodeContainer.getOrCreateNode(self, "*")
      --   publishPartsContainer.publishParts(starNode, parts, ...)
      -- end
      local nextNode = getOrCreateNodeContainer.getOrCreateNode(self, nextPart)
      publishPartsContainer.publishParts(nextNode, parts, ...)
    end
  end

  b.publishParts = function(self, parts, ...)
    -- TODO: Debug print
    -- print("[" .. table.concat(parts, ".") .."] => " .. ...)
    publishPartsContainer.publishParts(self, ring.copyIpairs(parts), ...)
  end

  return b
end

--- A message bus implementation.
-- @table MessageBus
-- @tfield (subject,message)=>void publish
-- @tfield (subject,callback)=>void subscribe
ring.MessageBus = {}

--- Create a new `ring.MessageBus` table.
ring.newMessageBus = function()
  local b = {}

  b.root = newMessageBusNodeContainer.newMessageBusNode()

  b.subscribe = function(self, subject, callback)
    return self.root:subscribe(subject, callback)
  end

  b.subscribeParts = function(self, parts, callback)
    return self.root:subscribeParts(parts, callback)
  end

  b.unsubscribe = function(self, subject, callback)
    return self.root:unsubscribe(subject, callback)
  end

  b.publishParts = function(self, parts, ...)
    self.root:publishParts(parts, ...)
  end

  b.publish = function(self, subject, ...)
    self:publishParts(ring.subjectToParts(subject), ...)
  end

  return b
end

--- A world implementation.
-- World represents a context in which a set of entities
-- with various compositional components are acted upon by a ordered set of
-- of systems.
-- @table World
-- @tfield (subject,callback)=>void subscribe Subscribe to a `ring.SubjectString`.
-- @tfield (subject,callback)=>void unsubscribe Unsubscribe from a `ring.SubjectString`.
-- @tfield (subject,message)=>void publish Publish a message to a `ring.SubjectString`.
-- @tfield (entityId,componentName,value)=>void putComponent Add a component to an entity. The form of a component is unstructured, but if values are provided, the component will be initialized with those values. Otherwise, the component will be initialized to boolean 'true'. *Aliases: putc,addComponent,addc.*
-- @tfield (entityId,componentName)=>void deleteComponent Delete a component from an entity. *Aliases: delc,removeComponent,remc.*
-- @tfield (entityId,componentName,[componentKey])=>void getComponent Get a copy of a component value or a copy of the entire component table. *Aliases: getc.*
-- @tfield (entityId,componentName)=>boolean hasComponent Check whether a entity has a component.
-- @tfield ({componentName,defaults},...},[name])=>void createEntity Create an entity.
-- @tfield (name)=>void getEntity Get an entity by name.
-- @tfield (entityId)=>void destroyEntity Destroy an entity.
-- @tfield (system,[name])=>void addSystem Add a system to this world.
-- @tfield (name)=>void getSystem Get a system from this world.
-- @tfield (systemOrName)=>void removeSystem Remove a system from this world.
-- @tfield (dt)=>void update Perform world updates.
-- @tfield ()=>void process Perform world per-frame processing.
ring.World = {}

--- Create a new `ring.World` table.
-- @treturn World A `ring.World` table.
ring.newWorld = function(isPublish)
  if isPublish == nil then isPublish = true end

  local b = {}

  b.bus = ring.newMessageBus()
  b.components = {}
  b.componentMetadata = {}
  b.entityDefinitions = {}
  b.entities = {}
  b.entityMetadata = {}
  b.nameToEntity = {}
  b.entityToName = {}
  b.nameToSystem = {}
  b.systems = {}

  local componentSubjects = {
    add = { ring.COMPONENT_PREFIX, ring.ADD_SUFFIX },
    change = { ring.COMPONENT_PREFIX, ring.CHANGE_SUFFIX },
    subtract = { ring.COMPONENT_PREFIX, ring.SUBTRACT_SUFFIX }
  }

  local entitySubjects = {
    add = { ring.ENTITY_PREFIX, ring.ADD_SUFFIX },
    subtract = { ring.ENTITY_PREFIX, ring.SUBTRACT_SUFFIX }
  }

  -- Metadata

  local makeComponentMetadata = function(self, c)
    return {
      subjects = {
        add = { ring.COMPONENT_PREFIX, c, ring.ADD_SUFFIX },
        change = { ring.COMPONENT_PREFIX, c, ring.CHANGE_SUFFIX },
        subtract = { ring.COMPONENT_PREFIX, c, ring.SUBTRACT_SUFFIX }
      }
    }
  end

  local createComponentMetadata = function(self, c)
    self.componentMetadata[c] = makeComponentMetadata(self, c)
  end

  -- Component Helpers

  local createComponent = function(self, c)
    local component = {}
    self.components[c] = component
    createComponentMetadata(self, c)
    return component
  end

  local deleteComponent = function(self, c)
    self.components[c] = nil
    self.componentMetadata[c] = nil
  end

  local getOrCreateComponent = function(self, c)
    local component = self.components[c]
    if not component then return createComponent(self, c) end
    return component
  end

  -- Entity Helpers

  local entityId = function(self, e)
    return type(e) == "number" and e or self.nameToEntity[e]
  end

  local entityName = function(self, e)
    return type(e) == "string" and e or self.entityToName[e] or e
  end

  b.printEntity = function(self, e, showComponentValues)
    print("#" .. e .. " (" .. entityName(self, e) .. "):")
    for c, component in pairs(self.components) do
      local entityComponent = component[e]
      if entityComponent then
        print("  " .. c .. (showComponentValues and ":" or ""))
        if showComponentValues then
          for k, v in pairs(entityComponent) do
            print("    " .. tostring(k) .. " = " .. tostring(v))
          end
        end
      end
    end
  end

  -- Message Bus

  b.subscribe = function(self, subject, callback)
    return self.bus:subscribeParts(self:subjectToParts(subject), callback)
  end

  b.unsubscribe = function(self, subject, callback)
    return self.bus:unsubscribe(subject, callback)
  end

  b.subjectToParts = function(self, subject)
    local parts = ring.subjectToParts(subject)

    -- If the subject refers to an entity by name, then replace the name
    -- with the entity's ID.
    -- if #parts > 1 and parts[1] == "#" and string.match(parts[2], "%w+") then
    --   local n = self.nameToEntity[parts[2]]
    --   if n then
    --     parts[2] = n
    --   end
    -- end

    return parts
  end

  b.publishParts = function(self, parts, ...)
    return self.bus:publishParts(parts, ...)
  end

  b.publish = function(self, subject, ...)
    self:publishParts(self:subjectToParts(subject), ...)
  end

  -- Add Component

  local publishComponentAdd = function(self, e, c, t)
    self:publishParts(componentSubjects.add, c, e, t)
    self:publishParts(self.componentMetadata[c].subjects.add, e, t)
  end

  local addComponentPure = function(self, e, c, t)
    local component = getOrCreateComponent(self, c)
    if component[e] then
      error("World.addComponent cannot be called for existing component: " .. c)
    end

    t = t or {}
    component[e] = t
    return t
  end

  local addComponent = function(self, e, c, t)
    local r = addComponentPure(self, e, c, t)
    publishComponentAdd(self, e, c, r)
    return r
  end

  b.addComponent = isPublish and addComponent or addComponentPure

  -- Set Component

  local publishComponentSet = function(self, e, c, t)
    self:publishParts(componentSubjects.change, c, e, t)
    self:publishParts(self.componentMetadata[c].subjects.change, e, t)
  end

  local setComponentPure = function(self, e, c, t, value)
    local component = getOrCreateComponent(self, c)
    local entityComponent = component[e]

    if not entityComponent then
      error(
          "World.setComponent cannot be called for non-existing component '" ..
              c .. "' of #" .. entityName(self, e))
    end

    if type(t) == "table" then
      for k, v in pairs(t) do entityComponent[k] = v end
    else
      entityComponent[t] = value
    end
    return entityComponent
  end

  local setComponent = function(self, e, c, t, value)
    local r = setComponentPure(self, e, c, t, value)
    publishComponentSet(self, e, c, r)
    return r
  end

  b.setComponent = isPublish and setComponent or setComponentPure

  -- Get Component

  b.getComponent = function(self, e, c, k)
    local component = getOrCreateComponent(self, c)
    local entityComponent = component[e]

    if not entityComponent then return nil end

    if k ~= nil then return entityComponent[k] end
    return entityComponent
  end

  b.hasComponent = function(self, e, c)
    local component = self.components[c]
    return component and component[entityId(self, e)] ~= nil
  end

  -- Remove Component

  local publishComponentRemove = function(self, e, c)
    self:publishParts(componentSubjects.subtract, c, e)
    self:publishParts(self.componentMetadata[c].subjects.subtract, e)
  end

  local removeComponentPure = function(self, e, c)
    local component = self.components[c]
    if not component then
      error("Cannot remove non-existing component '" .. c .. "' of #" .. e)
    end
    component[e] = nil
    return e, c
  end

  local removeComponent = function(self, e, c)
    removeComponentPure(self, e, c)
    publishComponentRemove(self, e, c)
    return e, c
  end

  b.removeComponent = isPublish and removeComponent or removeComponentPure

  -- Create Entity

  local entityIdCounter = 0

  local nextEntityId = function()
    entityIdCounter = entityIdCounter + 1
    return entityIdCounter
  end

  local setEntityName = function(self, e, n)
    self.nameToEntity[n] = e
    self.entityToName[e] = n
  end

  local clearEntityName = function(self, e, n)
    self.nameToEntity[n] = nil
    self.entityToName[e] = nil
  end

  local publishEntityCreate = function(self, e, n)
    self:publishParts(entitySubjects.add, e, n)
  end

  local createEntityPure = function(self, componentsOrName, components)
    if type(componentsOrName) == "table" then components = componentsOrName end

    local e = nextEntityId()
    self.entities[e] = true

    local n = (type(componentsOrName) == "string" and componentsOrName) or
                  (components and components.name and components.name.value and
                      components.name.value .. e) or ("entity" .. e)
    setEntityName(self, e, n)

    if components ~= nil then
      for c, t in pairs(components) do self:addComponent(e, c, t) end
    end

    return e, n
  end

  local createEntity = function(self, componentsOrName, components)
    local e, n = createEntityPure(self, componentsOrName, components)
    publishEntityCreate(self, e, n)
    return e, n
  end

  b.createEntity = isPublish and createEntity or createEntityPure

  -- Get Entity

  b.getEntity = function(self, name)
    return self.nameToEntity[name]
  end

  b.getEntityName = function(self, e)
    return self.entityToName[e] or e
  end

  -- Destroy Entity

  local publishEntityDestroy = function(self, e, n)
    self:publishParts(entitySubjects.subtract, e, n)
  end

  local destroyEntityPure = function(self, e)
    self.entities[e] = nil
    local n = self.entityToName[e]
    if n then clearEntityName(self, e, n) end
    for _, component in pairs(self.components) do component[e] = nil end
    self.entityMetadata[e] = nil
    return e, n
  end

  local destroyEntity = function(self, e)
    local _, n = destroyEntityPure(self, e)
    publishEntityDestroy(self, e, n)
  end

  b.destroyEntity = isPublish and destroyEntity or destroyEntityPure

  -- Add System

  b.addSystem = function(self, systemOrName, system)
    if type(systemOrName) == "table" then
      system = systemOrName
    else
      self.nameToSystem[systemOrName] = system
    end

    system.world = self
    table.insert(self.systems, system)
    system:initialize()
  end

  local findIndexOfSystem = function(self, system)
    for i, s in ipairs(self.systems) do if s == system then return i, s end end
    return -1, system
  end

  b.removeSystem = function(self, systemOrName)
    local system = type(systemOrName) == "table" and systemOrName or
                       self.nameToSystem[systemOrName]
    local i = findIndexOfSystem(self, system)
    if i == -1 then error("Cannot remove a system that is not in this world") end
    table.remove(self.systems, i)
    system:destroy()
    for name, namedSystem in pairs(self.nameToSystem) do
      if namedSystem == system then self.nameToSystem[name] = nil end
    end
  end

  b.getSystem = function(self, name)
    return self.nameToSystem[name]
  end

  -- Performs updates on data prior to frame processing. This function calls
  -- the update function of every system belonging to this world iteratively,
  -- in the order in which they were added to this world. It is expected that
  -- this function will be invoked before the world process method, once per
  -- tick, every tick.
  -- @param dt Delta time elapsed since the last tick, as a floating point number.
  b.update = function(self, dt)
    for _, system in ipairs(self.systems) do system:update(dt) end
  end

  -- Performs frame processing. This is where all draw operations should occur,
  -- and it is assumed that all changes to data that occur this tick should
  -- have already been taken care of by calling World:update(dt).
  b.process = function(self)
    for _, system in ipairs(self.systems) do system:process() end
  end

  return b
end

return ring
