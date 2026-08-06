# The Smog & The Swarm - Master Development Todo & Technical Specification
> **Project Title:** `The Smog & The Swarm`
> **Project Code:** `SMOG-SWARM-1890`  
> **Github Url:** https://github.com/LimtlessLtd/Smog-Swarm-1890
> **Engine & Language:** Godot Engine 4.x (GDScript)  
> **Target Release:** PC / Steam (£5–£10 target price point)  
> **Genre:** Persistent Background Real-Time Strategy & Base-Building  
> **Setting:** 1890 Victorian Britain Post-Apocalypse (Grounded Industrial Revolution Tech, Zombies, Hidden Alien Origins)

---

## 🏛️ Project Architecture & Design Overview

- **Core Loop:** Continuous persistent expansion across Victorian Britain hex sectors. Build defenses, automate patrols, manage daily resource upkeeps (Food/Coal/Gunpowder), and protect supply lines while working in the background.
- **Aesthetic Direction:** Grounded late-18th/19th-century Industrial Revolution (brick, cast iron, coal smoke, authentic Victorian architecture)—explicitly **no** retro-futuristic steampunk tropes.
- **Dual Perspective Engine:** Dynamic camera toggle between **Top-Down Orthographic** (tactical layout) and **2.5D Isometric** (cinematic viewing).
- **Multi-Layer Macro-Hex System:** Continuous tilemap hiding an underlying axial hex grid `(q, r)`. Each hex represents a 5x5 mile macro-region (~25 sq miles). Cities scale dynamically across multiple macro-tiles—Manchester spans 4 hexes (~100 sq miles), while Greater London spans 12 hexes (~300 sq miles). Features internal district partitioning and subterranean layers (Sewers/London Underground).
- **Time Controls & Day/Night Cycle:** Global `TickManager` supporting `0x` (Pause), `1x`, `2x`, `3x` and `5x` speeds (`Engine.time_scale`). Features a 40-minute real-time day/night cycle (20 minutes Day / 20 minutes Night at 1x speed).

---

## 📝 Phase 1: Engine Foundation, Terrain & Geography
- [x] **1.1 Project Setup & Configuration**
  - [x] Initialize Godot 4.x project repository with modular GDScript folder structure (`/scripts`, `/scenes`, `/assets`, `/ui`).
  - [x] Configure display settings for low-CPU background execution (Unfocused FPS limit, background audio processing).
- [x] **1.2 Dual Camera Controller (`CameraController.gd`)**
  - [x] Implement smooth pan, zoom, and perspective toggle (`TOP_DOWN` vs `ISOMETRIC`).
- [x] **1.3 Continuous Axial Hex Map & Real British Geography (`HexGridMap.gd`)**
  - [x] **5x5 Mile Macro-Hex Grid System:** Axial coordinate system `(q, r)` where each hex acts as a ~25 sq mile regional container. Manchester spans 4 macro-hexes; London covers 12 macro-hexes.
  - [x] **Authentic British Biomes & Topography:**
    - [x] **Elevated Terrain & Natural Barriers:** Pennine Chain (Peak District chokepoints south of Manchester), Chiltern Hills, and Cotswold Escarpment.
    - [x] **Major Waterways & Canals:** River Thames, River Mersey, River Trent, and historic canal networks (Manchester Ship Canal, Grand Union Canal).
    - [x] **Swamps & Waterlogged Basins:** Fenlands, Thames Estuary Marshes, and Chat Moss peat bogs.
  - [x] **Granular Soil Fertility:** Map localized soil patches (`Lush` Cheshire/Midlands farmland, `Poor` moorland, `Desolate` industrial slag heaps) inside individual hexes to determine specific farm placement and crop yields.
  - [x] **District & Frontline Partitioning:** Divide macro-hexes into sub-districts (Urban Center, Industrial Estate, Uncleared Wilderness), enabling active zombie combat in contested halves while safe zones harvest resources and build infrastructure.

---

## 🏭 Phase 2: Historical Building Tree, Economy & Logistics
- [ ] **2.1 Authentic 19th-Century Building Tree (`BuildingManager.gd`)**
  - [ ] **Housing & Civil:** Terraced Tenements, Workhouses, Church Steeple Watchtowers, Gas Streetlamps, Telegraph Relay Offices, Steam Printing Presses.
  - [ ] **Industry & Extraction:** Clay Brickworks, Charcoal Kilns, Coal Pitheads, Cast Iron Foundries, Saltpetre/Powder Mills, Forward Ammo Dumps.
  - [ ] **Agriculture:** Tenant Farms (requires `Lush`/`Poor` soil), Grain Silos, Cattle Yards.
- [ ] **2.2 Resource Upkeep Engine (`ResourceManager.gd`)**
  - [ ] Manage daily upkeep drains: **Food** (population drain), **Coal** (boiler/heating/streetlamp upkeep), and **Gunpowder** (ranged combat upkeep).
  - [ ] Track construction materials: **Wood**, **Bricks**, **Cast Iron**, **Reinforced Concrete**.
- [ ] **2.3 Supply Line Logistics & Two-Zone Control System (`LogisticsNetwork.gd`)**
  - [ ] Build supply flow nodes connecting outer resource sectors to central population hubs via roads, railways, and canal lines.
  - [ ] **Simplified Dual Zone of Control (ZoC):**
    - [ ] **1. Military ZoC (Supply, Vision & Suppression):** Projected by Forward Ammo Dumps, Garrisons, Watch Towers, and Combat Units. Gives off a resupply aura covering 66% of a tile. Permits small-scale wooden barricades to keep zombies at bay and protect assets.
    - [ ] **2. Civilian ZoC (Civil Infrastructure & Construction):** Projected by Town Halls, Churches, and Telegraph Relays. Can only be placed on secure hex tiles (no zombies) and covers the entire hex tile. Unlocks major wall fortifications and Barracks for unit recruitment.
  - [ ] Implement supply line disruption logic: If zombies sever a road, rail, or canal segment connected to an Ammo Dump, its Military ZoC supply aura deactivates.

---

## 🏙️ Phase 3: Urban Underground & Sewer Outbreak Mechanics
- [ ] **3.1 Subterranean Layer System (`SubterraneanMap.gd`)**
  - [ ] Urban hex underground toggle (Victorian Sewers, London Underground tunnels).
- [ ] **3.2 Sewer Zombie Ecosystem & Outbreak System (`SewerInfectionController.gd`)**
  - [ ] Subterranean infestation density tracking and outbreak risk algorithms.
  - [ ] Double sewer eruption risk during Night phase if un-sanitized.
- [ ] **3.3 Sanitation & Political Interventions**
  - [ ] Influence actions: *Sanitation Act*, *Nerve-Gas Purge*, *Militia Sewer Sweep*.

---

## 🧱 Phase 4: Defensive Construction, Infrastructure & Chokepoints
- [ ] **4.1 Chokepoint Defensive Building (`BuildingSystem.gd`)**
  - [ ] Freeform wall construction snapping across geographic bottlenecks (riverbanks, cliff passes).
  - [ ] Wall progression: Wooden Walls -> Brick Walls -> Concrete Walls.
  - [ ] Retain legacy inner walls as fallback bulkheads during breach events.
  - [ ] Build Gas Streetlamps and Searchlight Towers to illuminate perimeter walls during night defense, granting combat bonuses to garrisoned units.
- [ ] **4.2 Victorian Infrastructure Reclamation**
  - [ ] Rebuild destroyed stone bridges, steam railways, and canal locks to restore interrupted supply routes.
  - [ ] Drain swamps (e.g., Chat Moss, Fenlands) to improve soil quality and expand buildable land.
  - [ ] Wall fortification and siege survival logic: ensure outer settlements can withstand prolonged blockades.

---

## ⚔️ Phase 5: Threat Mechanics, Day/Night & Horde Intel
- [ ] **5.1 40-Minute Day/Night Simulation (`TimeCycleManager.gd`)**
  - [ ] **Day Phase (20 Minutes):**
    - [ ] +20% Construction and resource gather speed.
    - [ ] Zombies are slow/sluggish; minimal aggressive horde movement.
    - [ ] Full baseline visual range across unlocked hexes.
  - [ ] **Night Phase (20 Minutes):**
    - [ ] Zombie move speed +50%, aggression +100%, and double noise-attraction multiplier.
    - [ ] Fog of war contracts outside of Gas Streetlamps and Watchtower searchlights.
    - [ ] Sewer infestation eruption rate increases by 2x.
- [ ] **5.2 Horde Spawn & Industrial Attraction System (`HordeManager.gd`)**
  - [ ] Industrial noise fills Threat Meters, triggering night raids from uncleared wilderness.
- [ ] **5.3 Reconnaissance & Early Warning Mechanics**
  - [ ] High ground observation posts & telegraph alerts provide horde countdown timers.
- [ ] **5.4 Unit Tiers & Combat Engine (`CombatEngine.gd`)**
  - [ ] Tier 0 (Free Ammo) through Tier 3 (Heavy Artillery) combat routines.
  - [ ] Strict Gunpowder depletion penalty: 0 ammo forces ranged units into fragile, unarmored melee mode.

---

## 🖥️ Phase 6: Background HUD, Alerts & Audio Signals
- [ ] **6.1 Background Play UI & HUD Design (`MainHUD.tscn`)**
  - [ ] Day/Night Phase Clock indicator with countdown timer (e.g., "Nightfall in 04:15").
  - [ ] Threat Meter indicator per sector showing horde attraction levels.
- [ ] **6.2 Audio & Desktop Notification Alert System (`AlertManager.gd`)**
  - [ ] Sunset warning chime (e.g., Church bell toll at 2-minute nightfall mark).
  - [ ] Sunrise warning cockrel (e.g., rooster call at 2-minute dayfall mark).
  - [ ] Auto-pause during a wall breach and any other major event.

---

## 🧪 Phase 7: Narrative Campaign, Objectives & Steam Polish
- [ ] **7.1 "The Southern Expedition" Campaign Arc (Manchester to London)**
  - [ ] **Act I: The Cottonopolis & The Pennine Barrier:** Secure Manchester (4 macro-hexes), clear the Chat Moss bogs, and establish defenses across the Peak District passes.
  - [ ] **Act II: The Trent Valley & Fenland Corridors:** Rebuild rail infrastructure through Birmingham, cross the River Trent, and defend supply routes against hordes emerging from the East Anglian Fens.
  - [ ] **Act III: The Thames Basin Citadel:** Breach the Chiltern Hills, secure outer London's 12 macro-hex perimeter, navigate the flooded London Underground, and reclaim Imperial headquarters.
- [ ] **7.2 Major Milestone Objectives System (`CampaignManager.gd`)**
  - [ ] **Primary Objective:** Establish a continuous, defended rail/road logistics link from Manchester to London.
  - [ ] **Secondary Objective:** Investigate regional relic sites (wrecked observatories, strange craters) revealing alien spore origins.
  - [ ] **Final Mystery:** Uncover the fate of Queen Victoria and the Imperial Cabinet inside the sealed Tower of London bunker.
- [ ] **7.3 Playtesting & Steam Integration**
  - [ ] Balance multi-week campaign progression from Manchester down to London.
  - [ ] Implement Steam Cloud Saves, Achievements, and Steam Deck controller layout support.
