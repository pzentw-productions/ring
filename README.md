# ring

An entity component system implementation (ECS) for lua.

## Basic requirements

The basic requirements to use ring are just to

1. Install it
2. Import it
3. Create a world
4. Call the world update function every tick
5. Call the world process function every tick, after the world update function

Ring was made to do game development with [Love](https://love2d.org/), but it
isn't necessary for you to use it with [Love](https://love2d.org/), as long as
you follow the steps above.

## Installing

The easiest way to do this is just to clone the git repository.

`mkdir ring && git clone git@github.com:eherz1/ring.git ring`

... or, if you prefer, it might be nice to use a lib directory.

`mkdir -p lib/ring && clone git@github.com:eherz1/ring.git lib/ring`

## Importing

You should add ring to the lua path so you can import it easily.

Here is a start script for [Love](https://love2d.org/) that will work on a Mac.

```sh
#!/usr/bin/env sh

# Path to the love executable on your system
LOVE="/Applications/love.app/Contents/MacOS/love"

# List of libraries to add to the lua path
export LUA_PATH="$LUA_PATH;lib/ring/?.lua;"
#export LUA_PATH="$LUA_PATH;lib/<libname>/?.lua;"

#echo $LUA_PATH

$LOVE src
```

It assumes that your project will keep its source files in a directory called
`src` and that the entry point for [Love](https://love2d.org/) will be a file
called `main.lua` inside the `src` directory.

## Usage


Creating a world is as simple as calling `ring:newWorld()`.

```lua
local ring = require "ring"

local world = ring.newWorld()
```

### Adding systems

Creating a world in itself is not very useful unless you add some systems.

### A note about syntax

LUA is a bit limited in its support for OOP, so we follow a compositional
pattern. Basically how it works is that a constructor function such as
ring.newSystem accepts a single argument, table `t`. ring.newSystem creates a
new table, `u`, and assigns all properties of `t` onto `u`. It then _decorates_
`u` with additional properties.


Sometimes, this means that a key of table `t`
is overwritten on `u`, so be careful to avoid using the same keys as ring
does internally. Most of the time, it means that optional functions will
be given stub implementations if they are not present. In some cases, it
means that `t`'s implementation of a function will be replaced with another,
which _also_ invokes `t`'s implementation.

This pattern is lightweight, fits LUA well,
and in general doesn't cause too many issues, and it allows us to avoid
having to deal with LUA prototypes. Although object constructors have
to do more work to copy properties of the origin table than when assigning
a prototype, once a system is constructed this way, function invocations
require no call to the __index metamethod.

There are two ways of defining a system:

#### Table syntax

Table syntax is the default syntax - just because that's what I prefer -
although it requires that you explicitly declare 'self' as a parameter to
your functions, or else LUA won't support calling functions on the table
using the colon (:) operator. Also, you must use comma (,) after your
function declarations, because you're declaring table properties.

```lua
local MySystem = ring.newSystem({
  interestingVariable = 5,

  update = function(self, dt)
    self.interestingVariable = self.interestingVariable + self.interestingVariable / 2
  end,

  process = function(self)
    -- Do great things
  end
})
```

Notice that we haven't declared initialize or destroy functions. It's not
that our system won't have them - it will - but their implementations will
be set to the default implementation for ring.newSystem (no-op) because they
are optional.

#### Class syntax

Class syntax uses the colon (:) operator to declare the system. You can then
pass the completed table to ring.newSystem.

```lua
local _MySystem = {}

_MySystem.interestingVariable = 5

function _MySystem:update(dt)
  self.interestingVariable = self.interestingVariable + self.interestingVariable / 2
end

function _MySystem:process()
  -- Do great things
end

local MySystem = ring.newSystem(_MySystem)
```

It's a little bit cleaner, but lacks some readability, in my opinion.

### Creating a new base system

The first type of system is the base system. Base systems are very simple, and
don't offer much more than the ability to implement the update and process
functions. Here's an example of a system which calculates and prints the game's
FPS, implemented using love's `graphics.print` function.

```lua
local FpsSystem = ring:newSystem({
  initialize = function(self)
    self.frames = 0
    self.timer = 0
    self.fps = 0
  end,

  update = function(self, dt)
    self.timer = self.timer + dt
    self.frames = self.frames + 1
    if self.timer >= 1 then
      self.fps = self.frames
      self.frames = 0
      self.timer = 0
    end
  end,

  process = function(self)
    love.graphics.print("fps:" .. self.fps)
  end
})

world:addSystem(FpsSystem)
```

### Tying ring into your game loop

In order for our new system to work, we need to make sure we are executing
the `update` and `process` functions of our world every tick. In love, this
is done like so:

```lua
function love.update(dt)
  world:update(dt)
end

function love.draw()
  world:process()
end
```

You should now be able to run your game and see the FPS displayed.

### Entities

In ring, in the traditional ECS way, entities are only ints. When you create an
entity you get an int back, and when you want to do something with that entity,
you call a method of `World` and provide the int as the entity's id.

```lua
local fighter = world:createEntity()

world:addComponent(fighter, "health", {
  hp = 110,
  mp = 100
})

local fighterHealth = world:getComponent(fighter, "health")
fighterHealth.hp = fighterHealth.hp - 10
```

### EntitySystem

In order to make working with entities easier, the `EntitySystem` is provided.
`EntitySystem` works on a set of entities every tick, adding the functions
`match(entityId)`, `updateEntity(entityId, dt)` and `processEntity(entityId)`.

```lua
-- If an entity has a health component and it's hp falls below zero, then
-- add a 'dead' component.
local DeathSystem = world:createEntitySystem({
  matchEntity = function(self, entityId)
    return self.world:hasComponent(entityId, "health")
  end,

  updateEntity = function(self, entityId, dt)
    local health = self.world:getComponent(entityId, "health")
    if health.hp <= 0 then
      self.world:addComponent(entityId, "dead")
    end
  end,

  processEntity = function(self, entityId)
    -- noop
  end
})

-- If an entity has a 'dead' component, execute its optional cleanup and
-- remove it from the world.
local ReaperSystem = world:createEntitySystem({
  matchEntity = function(self, entityId)
    return self.world:hasComponent(entityId, "dead")
  end,

  updateEntity = function(self, entityId)
    local cleanup = self.world:hasComponent(entityId, "cleanup")
    if cleanup then
      cleanup(entityId)
    end
    self.world:removeEntity(entityId)
  end
})

world:addSystem(DeathSystem)
world:addSystem(ReaperSystem)
```

### EventSystem

Sometimes it can be useful to listen to events that happen on the world. For
that purpose, you can use `EventSystem`.

```lua
-- If an entity has a 'composite' component, then when it's created, 
-- also call createEntity for each of its children, and assign each
-- of its children a parent component which refers to the entityId
-- of the parent.
local CompositeSystem = ring.newEventSystem({
  onEntityCreated = function(self, entityId)
    local composite = self.world:getComponent(entityId, "composite")
    if composite then
      for _, child in ipairs(composite.children) do
        self.world:createEntity(child)
        child.parent = entityId
      end
    end
  end
})

world:addSystem(CompositeSystem)
```

## Testing

Ring is still pretty small and most of its functionality is being tested by its
use in my own projects, so there is no unit test suite. However, that will
likely change in the future. If you'd like to contribute to ring, let me know.
And if you find any bugs, please do report them and I will get them fixed as
soon as I can.
