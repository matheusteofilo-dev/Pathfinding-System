# NPC Pathfinding System

Server-side NPC system for Roblox with vision, hearing, pathfinding, search behavior and a live debug panel.

## Features

- **Vision**: field of view, vision range and per-body-part line-of-sight checks (R6 and R15).
- **Hearing**: NPCs react to noises inside their hearing range. Player footsteps, sprinting, sneaking, jumping and landing make noise. An NPC that is chasing ignores every noise.
- **Pathfinding**: chasing with `PathfindingService`, stuck recovery, alternate destinations and a budget for path computations.
- **Search**: when an NPC loses its target it goes to the last seen position and scans 360 degrees. If it finds nothing it moves on to its next action: a pending noise, going back to its spawn point, or idling.
- **Narrow gaps**: after seeing a player squeeze through a narrow gap sideways, the NPC learns that gap and can cross it the same way.
- **Giving up**: if a target can't be reached for a while, the NPC gives up and ignores it for some time.
- **Debug panel**: in-game toggles for vision rays, search rays, paths, noise, hearing range, state labels and gaps.

## Getting started

### Option 1: open the place

Open [`build/NPCSystemTest.rbxlx`](build/NPCSystemTest.rbxlx) in Roblox Studio and press Play. Everything is already in place: the test map, two NPCs (`bandit` and `citizen`), the remotes, the debug panel and a test sword.

### Option 2: add it to your game

The folders tell you where each file goes:

```
<Studio location>/<client or server>/<Name>.<luau or rbxmx>
```

- The first folders are the place in Studio (for example `ServerScriptService`, `StarterPlayer/StarterPlayerScripts`).
- `server` means it runs on the server, `client` means it runs on the player's device.
- The file name is the name of the object in Studio.
- A folder with the same name as a script holds that script's children. `ServerScriptService/server/NPCSystem/` holds the modules that go inside the `NPCSystem` ModuleScript.
- `.luau` files are code. Copy the text into a new script of the type shown in the tables below.
- `.rbxmx` files are ready-made Studio objects (remotes, GUI, tools, the map). Select the location in Studio (for example `ReplicatedStorage`), right-click → **Insert from File...** and pick the file. You can also drag the file into the Studio window and move the result to the right place.

Required:

| File | Create in Studio | Type |
|---|---|---|
| `ServerScriptService/server/NPCSystem.luau` | `ServerScriptService` → `NPCSystem` | ModuleScript |
| `ServerScriptService/server/NPCSystem/*.luau` | inside `NPCSystem`, one per file | ModuleScript |
| `ServerScriptService/server/NPCBootstrap.luau` | `ServerScriptService` → `NPCBootstrap` | Script |
| `ReplicatedStorage/server/MovementInputRemote.rbxmx` | `ReplicatedStorage` | RemoteEvent |
| `ReplicatedStorage/server/NPCDebugRemote.rbxmx` | `ReplicatedStorage` | RemoteEvent |
| `StarterPlayer/StarterPlayerScripts/client/MovementInput.luau` | `StarterPlayer` → `StarterPlayerScripts` → `MovementInput` | LocalScript |
| `StarterPlayer/StarterCharacterScripts/client/Sound.luau` | `StarterPlayer` → `StarterCharacterScripts` → `Sound` | LocalScript |

The system does not create the two RemoteEvents itself. If one is missing it prints a warning and the feature that uses it is disabled (player movement noise for `MovementInputRemote`, the debug panel for `NPCDebugRemote`).

`Sound` is empty on purpose: it replaces Roblox's default character sound script, because the system plays its own footstep sounds.

Optional (used by the test place):

| File | Insert into | What it is |
|---|---|---|
| `StarterGui/client/NPCDebugPanel.rbxmx` | `StarterGui` | Debug panel: the GUI and its LocalScript |
| `StarterPack/server/ResetSword.rbxmx` | `StarterPack` | A sword that kills on hit, for testing |
| `Workspace/server/NPCTestScene.rbxmx` | `Workspace` | Test map with walls, rooms, a noise button and narrow gaps |
| `Workspace/server/NPCs.rbxmx` | `Workspace` | Two test NPCs: `bandit` and `citizen` |
| `ServerScriptService/server/TestSceneRuntime.luau` | `ServerScriptService` → `TestSceneRuntime` (Script) | Tags and respawns the test NPCs |
| `ServerScriptService/server/NoiseExample.luau` | `ServerScriptService` → `NoiseExample` (Script) | Makes the test map's button emit a noise |

### Making an NPC

1. The model needs a `Humanoid` and a `HumanoidRootPart` (or a `PrimaryPart`).
2. Put it in `Workspace`.
3. Add a [CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService) tag that matches a profile name in `config.npcs` (for example `bandit`).

The test NPCs get their tag from a `StringValue` named `NPCTag` inside the model, which `TestSceneRuntime` reads. You don't need that for your own NPCs: tag them yourself.

## Configuration

Everything is in [`config.luau`](ServerScriptService/server/NPCSystem/config.luau), a ModuleScript that returns one table. This section documents every key in it.

- **Units:** every distance is in **studs**, every time is in **seconds**, every angle is in **degrees**.
- **Validation:** when the system starts it checks the numbers below. An invalid global value stops `Start()` with an error that lists every problem. An invalid NPC profile is only disabled, with a warning, and the other profiles keep working.
- **Valid** column: the range the validator accepts. "none" means the value is not range-checked.
- Runtime changes: the table is shared (`NPCSystem.config`), so most values can be changed while the game runs. The profiles in `npcs` are validated and copied once in `Start()`, so changes to them need `NPCSystem.Stop()` and `NPCSystem.Start()` again.

Contents:
[`randomSeed`](#randomseed) ·
[`debug`](#debug-config) ·
[`perception`](#perception) ·
[`navigation`](#navigation) ·
[`investigation`](#investigation) ·
[`gap`](#gap) ·
[`pursuit`](#pursuit) ·
[`movement`](#movement) ·
[`stateMachine`](#statemachine) ·
[`managedArea`](#managedarea) ·
[`testScene`](#testscene) ·
[`defaults`](#defaults) ·
[`npcs`](#npcs-profiles)

### randomSeed

| Key | Default | Meaning |
|---|---|---|
| `randomSeed` | `1` | Seed of each NPC's random generator (the seed plus the NPC's id). Use `nil` to seed from the current time. It is used to randomize when each NPC starts its perception cycle, so many NPCs don't all perceive in the same frame. A fixed seed makes that spread repeatable. |

### debug (config)

Debug drawing, shown in the world. Everything here is visual only and never changes how NPCs behave. All the `show...` flags can be toggled in game with the debug panel.

| Key | Default | Valid | Meaning |
|---|---|---|---|
| `enabled` | `true` | boolean | Master switch for all debug drawing. Also controllable at runtime with `NPCSystem.SetDebug(true)` or `Workspace:SetAttribute("NPCDebug", true)`. |
| `showVisionRays` | `true` | boolean | Rays from the NPC's eye to each body sample point of a candidate player. Green: the point is visible. Red: blocked. |
| `showLastSeenGhost` | `true` | boolean | A white ghost of the target's pose at the last place the NPC saw it. |
| `showPaths` | `true` | boolean | Path waypoints the NPC is following (the current one is white). |
| `showNoise` | `true` | boolean | A sphere at every noise, sized to the noise radius. Colors and lifetimes come from `noiseStyle`. |
| `showSearchRays` | `true` | boolean | The yellow rays of the 360 degree search. |
| `showState` | `true` | boolean | A label above each NPC with its state, the reason, the target, navigation status, noise counters, known gaps and the number of dropped visuals. |
| `showHearingRange` | `false` | boolean | A blue sphere with the NPC's hearing range. Not the same as the noise radius (cyan). |
| `showGaps` | `true` | boolean | The narrow gaps the NPC learned, and the parallel probe rays used to measure them. |
| `panelUserIds` | `{}` | array of UserIds | Who can use the debug panel in a live game. In Studio everyone can. |
| `rayLifetime` | `0.15` | `>= 0` | How long a vision ray stays on screen. Search rays stay 4 times longer. |
| `noiseLifetime` | `3` | `>= 0` | Lifetime of a noise sphere when `noiseStyle` has no entry for it. |
| `noiseStyle` | see below | none | Color and lifetime of the noise sphere for each noise tag. |
| `maxVisualParts` | `900` | `>= 0` | Limit on the number of debug parts alive at once. Only limits the drawing, never the NPC logic. Extra parts are counted in the state label. |
| `labelRefreshInterval` | `0.25` | `>= 0.05` | How often the state label text is updated. |

`noiseStyle` is a table keyed by the noise **tag**: the tag passed to `EmitNoise(position, radius, { tag = ... })`. The movement system uses `walk`, `sprint`, `sneak`, `jump` and `land`. Noises with no tag, or with a tag that has no entry, use `default`. Each entry is `{ color = Color3, lifetime = seconds }`.

| Tag | Color | Lifetime |
|---|---|---|
| `default` | cyan (0, 230, 255) | 3 |
| `walk` | cyan (0, 230, 255) | 0.8 |
| `sprint` | pink (255, 60, 150) | 0.8 |
| `sneak` | green (120, 255, 160) | 0.8 |
| `jump` | lime (190, 255, 60) | 1.2 |
| `land` | yellow (255, 255, 120) | 1.2 |

### perception

How NPCs see.

| Key | Default | Valid | Meaning |
|---|---|---|---|
| `lossGraceTime` | `1` | `>= 0` | Seconds without seeing the target before the NPC declares it lost and goes to the last seen position. `0` is immediate. |
| `updateInterval` | `0.10` | `>= 0.01` | Seconds between two perception cycles of the same NPC. The whole set of sample points is tested in one cycle. |
| `maxPerceptionsPerStep` | `6` | `>= 1` | Budget: how many NPCs run their perception cycle in one frame. NPCs that are due first go first, so the load is spread out. Each NPC still tests its full sample set. |
| `onSeeingInterval` | `0.10` | `>= 0` | Minimum seconds between two `onSeeing` callbacks of an NPC. In practice it can't be lower than `updateInterval`, because the callback runs at most once per cycle. |
| `candidateRangeMargin` | `8` | `>= 0` | Players farther than `visionRange` plus this margin (measured from the NPC's root) are skipped without any ray. The margin covers the size of the body. |
| `stopAtFirstVisible` | `false` | boolean | `true` stops testing sample points as soon as one is visible: cheaper, but you lose the count of visible points and the complete debug rays. `false` tests them all. |
| `maxSeeThroughRecasts` | `6` | `0` to `32` | How many times a ray is cast again after it hits something that doesn't count as a blocker: parts of the target itself that can't be seen, and parts marked see-through. |
| `seeThroughAttribute` | `"NPCSeeThrough"` | none | A part with this attribute set to `true`, or with a CollectionService tag with this name, does not block vision (glass, fences). |
| `minVisibleTransparency` | `0.95` | `0` to `1` | A body part of the target with `Transparency` at or above this is not counted as visible body. |
| `ignoredBodyParts` | `{ HumanoidRootPart = true }` | none | Part names that never count as body, for example an invisible root or hitbox. |
| `eyeAttachmentName` | `"VisionOrigin"` | none | Where the NPC looks from: 1) an Attachment with this name anywhere inside the NPC model, 2) the `Head`, 3) the root plus `eyeFallbackOffset`. |
| `eyeFallbackOffset` | `Vector3.new(0, 1.5, 0)` | none | Eye offset from the root, used only when there is no attachment and no `Head`. |
| `rigs` | `R15` and `R6` tables | none | The sample points on a target's body, see below. |

An NPC sees a player when at least one sample point of the player's body is inside the field of view and the vision range, and a ray from the eye to it is not blocked. While an NPC is in the `Searching` state its field of view is 360 degrees.

**`rigs`:** a table with one entry per rig type (`R15`, `R6`). Each entry maps a body part name to a list of sample points. A sample point is a `Vector3` in **fractions of the part's size**: `0, 0, 0` is the center, and values with an absolute value of `0.5` or less stay inside the part (`0, 0.3, 0` is a point 30% of the part's height above its center). More points mean more rays and a more accurate view of what is hidden. If a target's rig is not recognized as R15 or R6, the system uses generic samples and prints a warning. For custom rigs, give the profile a `rigMap` with the same format as one rig entry.

Default sample points (fractions of each part's size, `x, y, z`):

| Rig | Part | Points |
|---|---|---|
| R15 | `Head` | `0, 0, 0` and `0, 0.3, 0` |
| R15 | `UpperTorso` | `0, 0.25, 0` and `0, -0.25, 0` |
| R15 | `LowerTorso` | `0, 0, 0` |
| R15 | `LeftUpperArm`, `RightUpperArm` | `0, 0, 0` |
| R15 | `LeftUpperLeg`, `RightUpperLeg` | `0, 0, 0` |
| R15 | `LeftFoot`, `RightFoot` | `0, -0.2, 0` |
| R6 | `Head` | `0, 0, 0` and `0, 0.3, 0` |
| R6 | `Torso` | `0, 0.3, 0` and `0, -0.3, 0` |
| R6 | `Left Arm`, `Right Arm` | `0, 0, 0` |
| R6 | `Left Leg`, `Right Leg` | `0, 0, 0` and `0, -0.4, 0` |

### navigation

Path following, stuck recovery and alternate destinations.

| Key | Default | Valid | Meaning |
|---|---|---|---|
| `repathInterval` | `0.35` | `>= 0.05` | Minimum seconds between two path recomputations while following a moving target. |
| `targetMoveThreshold` | `3` | `>= 0` | The target has to move at least this far from the current destination before the path is recomputed. |
| `arrivalTolerance` | `2` | `> 0` | Distance (ignoring height) at which the NPC counts as arrived at a normal goal. |
| `preciseArrivalTolerance` | `0.8` | `> 0` | Tolerance for goals that need to be exact: the last seen position, a noise source, routes and gap crossings. |
| `waypointTolerance` | `2.5` | `> 0` | Distance at which an intermediate path waypoint counts as reached. The last waypoint uses the arrival tolerance. |
| `stuckTimeout` | `1.5` | `>= 0.1` | Seconds without progress toward the current waypoint before the NPC is considered stuck and starts recovering. |
| `minProgressDistance` | `0.5` | `>= 0` | How much closer to the waypoint the NPC must get to count as progress. |
| `maxRecoveryAttempts` | `3` | `>= 0` | How many times the NPC tries to get unstuck before the navigation fails. Attempt 1: jump (if the profile can jump) and compute a new path. Attempt 2: sidestep. Attempt 3 and later: walk to an alternate reachable point near the destination. |
| `recoveryResetDistance` | `10` | `>= 0` | Real distance the NPC has to travel to reset the recovery counter. |
| `sidestepDistance` | `3` | none | Recovery step: how far the NPC steps sideways. |
| `sidestepDuration` | `0.45` | none | Recovery step: how long the sidestep lasts. |
| `moveCommandInterval` | `1.0` | `>= 0.1` | How often `Humanoid:MoveTo` is issued again. `MoveTo` expires after about 8 seconds. It is also issued again whenever the waypoint changes. |
| `jumpTriggerDistance` | `4` | none | Distance to a `Jump` waypoint at which the NPC jumps (only if its profile has `agent.canJump`). |
| `computeTimeout` | `6` | `>= 0.5` | Seconds to wait for a path computation before failing. |
| `maxConcurrentComputes` | `6` | `>= 1` | Global budget of simultaneous `ComputeAsync` calls for all NPCs. |
| `incapacitatedTimeout` | `6` | `>= 0` | If an NPC stays seated, ragdolled or in `PlatformStand` longer than this, its navigation fails with `incapacitated`. |
| `maxAlternatePoints` | `6` | `>= 0` | When the destination is unreachable, how many reachable points near it are tried instead. |
| `alternateRadii` | `{ 4, 8, 14 }` | none | Rings (distances from the destination) where alternate points are searched. |
| `alternateDirections` | `8` | `>= 1` | How many points are placed around each ring. |
| `groundSnapDepth` | `120` | none | How far down a ray is cast to put a destination on the ground. |
| `verticalTolerance` | `6` | none | Maximum height difference for which a waypoint or the destination still counts as reached. |
| `agentDefaults` | `{ radius = 2, height = 5, canJump = true, canClimb = false }` | table | Default `PathfindingService` agent parameters. A profile's `agent` table overrides them key by key. |

### investigation

What an NPC does about noises and after it loses the target.

| Key | Default | Valid | Meaning |
|---|---|---|---|
| `noisePriority` | `"TargetFirst"` | `"TargetFirst"` or `"InvestigateFirst"` | How noises compete with other actions, see below. |
| `searchDuration` | `3` | `>= 0` | Seconds the 360 degree search lasts at the last seen position or at a noise source. |
| `searchRayCount` | `24` | `>= 1` | Rays per elevation in one search. They are spread over `searchDuration` while the NPC turns. |
| `searchElevations` | `{ -15, 0, 25 }` | non-empty array, each `-89` to `89` | Vertical angles of the search rays, to cover drops and heights. |
| `searchRayRange` | `60` | `> 0` | Reach of the search rays. The smaller of this and the NPC's `visionRange` is used. A profile can override it with its own `searchRayRange`. |
| `noiseDedupeWindow` | `0.75` | `>= 0` | Noises closer than `noiseDedupeRadius` to an earlier one, and heard within this many seconds of it, are merged into it. |
| `noiseDedupeRadius` | `2` | `>= 0` | See above. |
| `noiseQueueCapacity` | `16` | `>= 1` | How many noises an NPC keeps waiting. New distinct noises beyond this are rejected (and counted in the debug label). |
| `noiseExpiry` | `30` | `> 0` | A queued noise older than this many seconds is dropped. |

**`noisePriority`:**

- `"TargetFirst"`: seeing the target is more important than a noise. A noise is investigated right away only when the NPC is idle or returning. Otherwise it waits in the queue and is checked after the current action ends.
- `"InvestigateFirst"`: a noise interrupts what the NPC is doing and is investigated at once. Noises that arrive while the NPC is already investigating wait in the queue until that spot has been checked.

In both modes, an NPC that is **chasing** ignores every noise, and starting a chase also discards the noises that were waiting.

**How noises are heard:** a noise has a position and a radius. An NPC hears it only if the distance to the noise is less than or equal to both the noise radius and the NPC's own `hearing` (so `hearing = 0` is deaf). Heard noises go to the NPC's queue and are investigated one by one.

**After losing the target:** the NPC goes to the last seen position, runs the 360 degree search, and if it finds nothing it continues with its next action: a queued noise, then going back to its spawn point when `returnPos` is `true`, otherwise idling.

### gap

Narrow gaps that a player can cross sideways (for example with shift lock) and an NPC facing forward can't. The NPC learns a gap only after **seeing** a player cross it, then turns 90 degrees to cross it the same way. The gap is measured with rays fired sideways, parallel to each other, along the player's walked path.

| Key | Default | Valid | Meaning |
|---|---|---|---|
| `heights` | `{ 1, 2.5, 4 }` | non-empty array, each `> 0` | Heights above the feet at which the sideways probe rays are fired. |
| `probeRange` | `6` | `> 0` | Length of each sideways probe ray, to each side. |
| `minWidth` | `1.0` | `> 0` | The smallest gap a body can still cross sideways. Narrower gaps are ignored. |
| `minMove` | `0.25` | `>= 0` | Minimum distance the target must move between two observations for the NPC to infer its direction. |
| `mergeDistance` | `3` | `>= 0` | Gaps closer to each other than this are treated as the same gap. |
| `marchStep` | `1` | `>= 0.1` | Step of the sweep along the gap direction used to find where it starts and ends. |
| `marchRange` | `12` | `>= 1` | Maximum distance of that sweep. |
| `entryBackoff` | `1.5` | `>= 0` | Extra distance before the entrance where the NPC stops to line up. |
| `cooldown` | `6` | `>= 0` | Seconds between two gap detour attempts. |
| `maxGaps` | `16` | `>= 1` | Maximum number of gaps an NPC remembers. |
| `sampleStep` | `0.5` | `>= 0.1` | Spacing of the samples taken along the target's observed movement. |
| `maxApproach` | `40` | `>= 0` | Farthest an entrance can be for the NPC to consider the detour. |
| `bodyDepth` | `1.0` | `> 0` | Thickness of the body seen from the side. A gap narrower than this is not used. A profile can override it with `agent.bodyDepth`. |
| `crossSpeedFactor` | `0.5` | `0.05` to `1` | Fraction of the NPC's speed used while crossing sideways, for more control. |
| `crossLookahead` | `1.5` | `>= 0.1` | How far ahead on the center line of the gap the NPC aims, to keep its body centered. |
| `reachSlack` | `2.5` | `>= 0` | If the NPC ends up at an alternate point farther than this from its real goal, the goal counts as unreachable, which triggers the gap detour. |

### pursuit

When an NPC gives up chasing.

| Key | Default | Valid | Meaning |
|---|---|---|---|
| `giveUpTime` | `10` | `>= 0.5` | If the target can't be reached or approached for this many seconds, the NPC gives up. Progress is measured along the walkable path, not in a straight line. |
| `progressDelta` | `2` | `>= 0` | How many studs of path length shorter count as real progress. |
| `ignoreTime` | `20` | `>= 0` | After giving up, the NPC ignores that target for this many seconds. |

### movement

Player movement: sprint, sneak, and the noise and footstep sounds they make. Runs on the server together with the `MovementInput` LocalScript and the `MovementInputRemote` remote.

| Key | Default | Valid | Meaning |
|---|---|---|---|
| `enabled` | `true` | boolean | `false` turns the whole player movement system off (no sprint, sneak, noise or footsteps from it). |
| `doubleTapWindow` | `0.3` | `>= 0.05` | Seconds between two taps of `W` to start sprinting. Sent to the client as an attribute of the remote. |
| `speeds` | `{ walk = 16, sprint = 26, sneak = 16 }` | each `> 0` | `WalkSpeed` of the player in each mode while on the ground. Lower `sneak` to make sneaking slower. |
| `stepDistance` | `{ walk = 4, sprint = 5.5, sneak = 3 }` | each `> 0` | Studs walked between two steps. Every step makes a noise and plays a footstep sound. |
| `noiseRadius` | `{ walk = 18, sprint = 36, sneak = 6, jump = 24, land = 28 }` | each `>= 0` | Radius of the noise of each action, in studs. This is the radius passed to `EmitNoise`, with the action name as the tag. |
| `minLandFallTime` | `0.3` | `>= 0` | Seconds in the air for a landing to make noise. |
| `soundMaxDistance` | `80` | `>= 1` | Maximum distance at which the footstep sounds can be heard. |
| `sounds` | see below | each with a string `id` | The sound played for each action. |

Each entry in `sounds` is `{ id = "rbxasset://...", volume = number, speed = number }`: the sound id, the volume (`>= 0`) and the playback speed (`> 0`). The defaults use the sounds that come with Roblox:

| Action | Sound | Volume | Speed |
|---|---|---|---|
| `walk` | `rbxasset://sounds/action_footsteps_plastic.mp3` | 0.5 | 1 |
| `sprint` | `rbxasset://sounds/action_footsteps_plastic.mp3` | 0.8 | 1.35 |
| `sneak` | `rbxasset://sounds/action_footsteps_plastic.mp3` | 0.15 | 0.8 |
| `jump` | `rbxasset://sounds/action_jump.mp3` | 0.7 | 1 |
| `land` | `rbxasset://sounds/action_jump_land.mp3` | 0.8 | 1 |

### stateMachine

| Key | Default | Meaning |
|---|---|---|
| `strict` | `false` | `true` refuses an illegal state change. `false` applies it and prints a warning, which is useful while developing. |

### managedArea

| Key | Default | Meaning |
|---|---|---|
| `managedArea` | `nil` | Optional box `{ center = Vector3, size = Vector3 }`. An NPC that leaves the box is unregistered (it stops being controlled). Checked every 2 seconds. `nil` means no limit. |

### testScene

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Lets the optional `TestSceneRuntime` script run: it tags the test NPCs from their `NPCTag` value and respawns them after they die. Set it to `false`, or delete the script, in a real game. |

### defaults

Values used when an NPC profile leaves a field out.

| Key | Default |
|---|---|
| `speed` | `16` |
| `hearing` | `40` |
| `returnPos` | `true` |
| `visionRange` | `80` |
| `fieldOfView` | `180` |

### npcs (profiles)

`config.npcs` has one entry per NPC type. **The key is the CollectionService tag**, not the model's name. If a model has more than one profile tag, the first one in alphabetical order is used and a warning is printed.

| Field | Valid | Meaning |
|---|---|---|
| `speed` | `> 0` | Walk speed of the NPC. |
| `hearing` | `>= 0` | Hearing range. `0` is deaf: the NPC never hears noises. |
| `chases` | boolean | `false` only detects players: it never chases, searches or follows noises. Default `true`. |
| `returnPos` | boolean | Walk back to the place where the NPC was registered when there is nothing left to do. |
| `visionRange` | `> 0` | Vision range. |
| `fieldOfView` | `(0, 360]` | Field of view, centered on where the NPC is looking. `360` sees everything around it. |
| `agent` | table | `PathfindingService` agent parameters: `radius`, `height` (both `> 0`), `canJump`, `canClimb` (booleans). Keys you leave out come from `navigation.agentDefaults`. You can also set `bodyDepth` here, which overrides `gap.bodyDepth` for this NPC. |
| `searchRayRange` | `> 0` | Reach of this NPC's search rays. Overrides `investigation.searchRayRange`. |
| `rigMap` | table | Sample points for custom rigs, in the format of one entry of `perception.rigs`. |
| `onSeeing` | function | `(player, context)`. Called on the server while the NPC has confirmed vision of a player, at most once per perception cycle and no more often than `perception.onSeeingInterval`. |
| `onStateChanged` | function | `(model, oldState, newState, reason)`. Called when the NPC changes state. |
| `canTarget` | function | `(player) -> boolean`. Optional filter: return `false` to make the NPC ignore that player. |

Fields left out use `config.defaults` (`speed`, `hearing`, `returnPos`, `visionRange`, `fieldOfView`) or the values above.

The `context` table given to `onSeeing`:

| Field | Meaning |
|---|---|
| `npc` | The NPC's model. |
| `distance` | Distance to the player in studs. |
| `isVisible` | Always `true` when the callback runs. |
| `targetHumanoid` | The player's `Humanoid`. |
| `lastSeenPosition` | Where the NPC last saw the player. |
| `memory` | A table that belongs to this NPC only and is kept between calls. Use it to store your own state, for example a cooldown. |
| `visiblePoints` | How many body sample points are visible right now. |
| `time` | `os.clock()` when the check ran. |

If you yield (for example with `task.wait`) inside `onSeeing`, check the target, the distance and the visibility again before you apply any effect. The NPC will not call `onSeeing` again until the previous call has finished.

The two profiles that come with the project:

- **`citizen`** only detects (`chases = false`), is slow (`speed = 10`), deaf (`hearing = 0`) and doesn't return (`returnPos = false`). Its `onSeeing` writes the name of the player it sees to the attribute `SeeingPlayer` on the NPC model, an extension point for things like calling the police.
- **`bandit`** chases, has `hearing = 40`, `visionRange = 80`, and walks back after a search. Its `onSeeing` hurts the player: when the player is within 3 studs and alive, it deals 10 damage with `TakeDamage`, at most once per second (the time of the last hit is stored in `context.memory`).

## API

```lua
local NPCSystem = require(game.ServerScriptService.NPCSystem)

NPCSystem.Start()
NPCSystem.Stop()

NPCSystem.EmitNoise(position, radius, { tag = "explosion" })

NPCSystem.SetDebug(true)
NPCSystem.IsDebugEnabled()

NPCSystem.GetController(model)
NPCSystem.GetControllers()
NPCSystem.GetDebugStats()
```

`EmitNoise` returns how many NPCs were inside the noise's hearing range. NPCs that are chasing hear it but ignore it. The optional `tag` picks the debug color from `debug.noiseStyle`.

## Player controls

| Input | Action |
|---|---|
| Double tap `W` | Sprint (louder) |
| Hold `Shift` | Sneak (quieter) |

## Debug

Debug drawing is configured in `config.debug` (see above), and can be changed at runtime with `NPCSystem.SetDebug` or the `NPCDebug` attribute on `Workspace`.

In Studio everyone can use the debug panel. In a live game only the user IDs in `config.debug.panelUserIds` can.

## NPC states

| State | Meaning |
|---|---|
| `Idle` | Doing nothing, waiting. |
| `Chasing` | Chasing a player it sees. Ignores noises. |
| `InvestigatingNoise` | Walking to the source of a noise. |
| `GoingToLastSeen` | Walking to where it last saw the target. |
| `Searching` | Doing the 360 degree search at a noise source or at the last seen position. |
| `Returning` | Walking back to where it was registered. |
| `Disabled` | Removed from the system (died, left the workspace, tag removed, or the system stopped). |
