# Ascension: 200 technology examples

Generated from [technologies.json](technologies.json). Edit JSON, then run `python3 tools/ascension_catalog.py --render`.

**Design-only catalogue.** Twenty technologies per era. These are not 200 implemented unlocks. All costs are initial normalized balance seeds; commissioning and production remain separate.

Starting knowledge: electromagnetism, semiconductor physics, integrated circuits, classical mechanics, thermodynamics, nuclear physics, calculus and probability, modern chemistry, cell biology, contemporary military engineering.

Every project requires a built, powered research campus or the named successor facility. Facilities below are requirements, not automatically created by completing prerequisites. Work, specialists and compute use era-local normalized capacity units. The minimum powered fraction is a hard operating threshold; progress above it scales with delivered service. Energy expenditure integrates actual delivered power over runtime. One stellar power unit means 10²⁶ W for display.

Required evidence is AND; alternative evidence is an OR clause in addition to required evidence. A prototype validation is mandatory before deployment. Prerequisites shown include facility-enabling discoveries.

Each project then requires compatible factory tooling, materials and logistics; unlocks are designs, not spawned units. Plausibility applies to the whole proposed capability. See [science boundaries](SCIENCE.md).

## Era 1 — Contemporary Humanity

### T001 — Combined-Arms Doctrine

Coordinate infantry and armour under one command network.

- **Field / plausibility:** Military science; Established. Ruleset: both.
- **Prerequisites:** Starting knowledge.
- **Research:** 90 theory work + 45 experimental work; 3 specialist capacity, 1 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 60 refined_material; 45 prototype industrial work.
- **Power:** 10 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock formation escort and role-aware target priorities.
- **Units unlocked:** Rifle squad.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T008, T016.
- **Science:** Military science applied to combined-arms doctrine. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T002 — Field Power Distribution

Deploy protected switchgear and local distribution circuits.

- **Field / plausibility:** Electrical engineering; Established. Ruleset: both.
- **Prerequisites:** Starting knowledge.
- **Research:** 120 theory work + 60 experimental work; 4 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 80 refined_material; 60 prototype industrial work.
- **Power:** 15 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Connect production loads and set load-shedding priorities.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Substation.
- **Technologies enabled:** T006, T011, T012, T013, T014, T024.
- **Science:** Electrical engineering applied to field power distribution. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T003 — Ore Characterization

Measure grade and recoverable content before processing.

- **Field / plausibility:** Geology; Established. Ruleset: both.
- **Prerequisites:** Starting knowledge.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 100 refined_material; 75 prototype industrial work.
- **Power:** 20 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Display deposit yield and depletion forecasts.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Survey station.
- **Technologies enabled:** T004, T026.
- **Science:** Geology applied to ore characterization. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T004 — Mobile Refining

Package crushing and separation in forward industrial modules.

- **Field / plausibility:** Metallurgy; Established. Ruleset: both.
- **Prerequisites:** T003.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 120 refined_material; 90 prototype industrial work.
- **Power:** 25 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Convert hauled ore to usable material with explicit waste.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Ore processor.
- **Technologies enabled:** T005, T006, T007.
- **Science:** Metallurgy applied to mobile refining. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T005 — Industrial Scheduling

Use constrained schedules to share machinery among orders.

- **Field / plausibility:** Operations research; Established. Ruleset: both.
- **Prerequisites:** T004.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 5 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 140 refined_material; 105 prototype industrial work.
- **Power:** 30 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reserve material and work across competing queues.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Production office.
- **Technologies enabled:** T009, T014, T017, T021.
- **Science:** Operations research applied to industrial scheduling. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T006 — Diesel-Electric Logistics

Standardize vehicle power and maintenance interfaces.

- **Field / plausibility:** Mechanical engineering; Established. Ruleset: both.
- **Prerequisites:** T002, T004.
- **Research:** 90 theory work + 45 experimental work; 3 specialist capacity, 1 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 60 refined_material; 45 prototype industrial work.
- **Power:** 10 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Deploy supply routes with finite fuel and cargo.
- **Units unlocked:** Supply truck.
- **Buildings unlocked:** Supply depot.
- **Technologies enabled:** T010, T016, T017.
- **Science:** Mechanical engineering applied to diesel-electric logistics. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T007 — Composite Armour Packages

Qualify layered armour against representative penetrators.

- **Field / plausibility:** Materials science; Established. Ruleset: both.
- **Prerequisites:** T004.
- **Research:** 120 theory work + 60 experimental work; 4 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 80 refined_material; 60 prototype industrial work.
- **Power:** 15 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock costly vehicle protection kits with a mass penalty.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Materials laboratory.
- **Technologies enabled:** T008, T009, T012, T013, T020, T023, T025, T027, T029, T033, T035, T038, T043.
- **Science:** Materials science applied to composite armour packages. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T008 — Guided Anti-Armour Systems

Integrate guidance and shaped-charge effects into portable weapons.

- **Field / plausibility:** Control engineering; Established. Ruleset: both.
- **Prerequisites:** T001, T007.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 100 refined_material; 75 prototype industrial work.
- **Power:** 20 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Field long-range anti-armour with finite missile magazines.
- **Units unlocked:** Anti-armour team.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T011, T018, T030.
- **Science:** Control engineering applied to guided anti-armour systems. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T009 — Armoured Vehicle Production

Tool a repeatable armoured chassis assembly line.

- **Field / plausibility:** Manufacturing; Established. Ruleset: both.
- **Prerequisites:** T005, T007.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 120 refined_material; 90 prototype industrial work.
- **Power:** 25 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Produce tanks using dedicated factory work and parts.
- **Units unlocked:** Battle tank.
- **Buildings unlocked:** Vehicle works.
- **Technologies enabled:** T010, T021, T030, T051.
- **Science:** Manufacturing applied to armoured vehicle production. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T010 — Rotary-Wing Integration

Support battlefield helicopter maintenance and sortie planning.

- **Field / plausibility:** Aeronautics; Established. Ruleset: both.
- **Prerequisites:** T006, T009.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 5 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 140 refined_material; 105 prototype industrial work.
- **Power:** 30 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Field gunships with limited sortie endurance and rearm time.
- **Units unlocked:** Attack helicopter.
- **Buildings unlocked:** Air pad.
- **Technologies enabled:** T034.
- **Science:** Aeronautics applied to rotary-wing integration. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T011 — Integrated Air Defence

Connect radar tracks with guns and guided interceptors.

- **Field / plausibility:** Radar engineering; Established. Ruleset: both.
- **Prerequisites:** T002, T008.
- **Research:** 90 theory work + 45 experimental work; 3 specialist capacity, 1 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 60 refined_material; 45 prototype industrial work.
- **Power:** 10 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Protect a defended arc while exposing radar and reload dependencies.
- **Units unlocked:** Air-defence team.
- **Buildings unlocked:** Radar station, Missile battery.
- **Technologies enabled:** T019, T030, T031.
- **Science:** Radar engineering applied to integrated air defence. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T012 — Battery Buffering

Qualify battery systems for industrial peak loads.

- **Field / plausibility:** Electrochemistry; Established. Ruleset: both.
- **Prerequisites:** T002, T007.
- **Research:** 120 theory work + 60 experimental work; 4 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 80 refined_material; 60 prototype industrial work.
- **Power:** 15 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Store finite energy and absorb short interruptions.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Battery bank.
- **Technologies enabled:** T023, T024.
- **Science:** Electrochemistry applied to battery buffering. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T013 — Nuclear Operations

Adapt established fission engineering to wartime modular deployment.

- **Field / plausibility:** Nuclear engineering; Established. Ruleset: both.
- **Prerequisites:** T002, T007.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 100 refined_material; 75 prototype industrial work.
- **Power:** 20 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Build high-output baseload power with fuel and maintenance costs.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Fission station.
- **Technologies enabled:** T025.
- **Science:** Nuclear engineering applied to nuclear operations. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T014 — High-Performance Computing

Allocate parallel computing to engineering workloads.

- **Field / plausibility:** Computer science; Established. Ruleset: both.
- **Prerequisites:** T002, T005.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 120 refined_material; 90 prototype industrial work.
- **Power:** 25 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Provide compute service to research instead of a flat universal bonus.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Compute centre.
- **Technologies enabled:** T015, T018, T019, T021, T022, T024, T029, T031.
- **Science:** Computer science applied to high-performance computing. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T015 — Experimental Design

Use statistics and reproducible trials to validate designs.

- **Field / plausibility:** Mathematics; Established. Ruleset: both.
- **Prerequisites:** T014.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 5 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 140 refined_material; 105 prototype industrial work.
- **Power:** 30 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Improve evidence efficiency and expose uncertainty in test forecasts.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Research laboratory.
- **Technologies enabled:** T020, T022, T023, T036, T037, T059.
- **Science:** Mathematics applied to experimental design. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T016 — Battlefield Medicine

Organize trauma care and rehabilitation near supply routes.

- **Field / plausibility:** Medicine; Established. Ruleset: both.
- **Prerequisites:** T001, T006.
- **Research:** 90 theory work + 45 experimental work; 3 specialist capacity, 1 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 60 refined_material; 45 prototype industrial work.
- **Power:** 10 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Recover surviving crews faster at a continuing supply cost.
- **Units unlocked:** Medical transport.
- **Buildings unlocked:** Field hospital.
- **Technologies enabled:** T036, T074.
- **Science:** Medicine applied to battlefield medicine. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T017 — Closed Supply Accounting

Track cargo from reservation through destination receipt.

- **Field / plausibility:** Logistics; Established. Ruleset: both.
- **Prerequisites:** T005, T006.
- **Research:** 120 theory work + 60 experimental work; 4 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 80 refined_material; 60 prototype industrial work.
- **Power:** 15 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Prevent double allocation and enable automatic reserve targets.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Warehouse.
- **Technologies enabled:** T028.
- **Science:** Logistics applied to closed supply accounting. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T018 — Precision Artillery

Combine ballistic models with calibrated targeting inputs.

- **Field / plausibility:** Ballistics; Established. Ruleset: both.
- **Prerequisites:** T008, T014.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Starting research campus.
- **Economic cost:** 100 refined_material; 75 prototype industrial work.
- **Power:** 20 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Deploy indirect fire whose performance depends on ammo and target quality.
- **Units unlocked:** Artillery battery.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T034.
- **Science:** Ballistics applied to precision artillery. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T019 — Drone Reconnaissance Analytics

Process visible battlefield signatures for targeting solutions.

- **Field / plausibility:** Robotics; Established. Ruleset: both.
- **Prerequisites:** T011, T014.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Compute centre (T014).
- **Economic cost:** 120 refined_material; 90 prototype industrial work.
- **Power:** 25 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Improve fire-control quality without introducing fog of war.
- **Units unlocked:** Observation drone.
- **Buildings unlocked:** Drone workshop.
- **Technologies enabled:** T026, T032.
- **Science:** Robotics applied to drone reconnaissance analytics. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T020 — Alien Materials Assay

Compare recovered specimens with terrestrial material models.

- **Field / plausibility:** Analytical chemistry; Established. Ruleset: both.
- **Prerequisites:** T007, T015.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 5 compute service; at most 2 parallel experiments. 1 alien_material_sample: Guaranteed Core Node perimeter salvage site; accessible before victory..
- **Infrastructure:** Research laboratory (T015).
- **Economic cost:** 140 refined_material; 105 prototype industrial work.
- **Power:** 30 kW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Open a salvage-assisted armour route without skipping domestic prerequisites.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Alien analysis lab.
- **Technologies enabled:** T040, T098.
- **Science:** Analytical chemistry applied to alien materials assay. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

## Era 2 — Advanced Industrial Civilization

### T021 — Robotic Workcells

Automate repeatable assembly operations with supervised robots.

- **Field / plausibility:** Robotics; Established. Ruleset: both.
- **Prerequisites:** T005, T009, T014.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Vehicle works (T009).
- **Economic cost:** 100 precision_components; 75 prototype industrial work.
- **Power:** 15 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Replace part of factory labour demand with power and precision parts.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Robotic factory.
- **Technologies enabled:** T026, T027, T028, T032, T039, T047, T052, T060.
- **Science:** Robotics applied to robotic workcells. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T022 — AI-Assisted Science

Use learned models to propose and screen experiments.

- **Field / plausibility:** Artificial intelligence; Experimental. Ruleset: both.
- **Prerequisites:** T014, T015.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Compute centre (T014).
- **Economic cost:** 120 precision_components; 90 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Increase eligible experiment throughput while consuming compute.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** AI cluster.
- **Technologies enabled:** T030, T031, T035, T040, T041, T055, T056.
- **Science:** Artificial intelligence applied to ai-assisted science. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T023 — Advanced Battery Chemistry

Qualify higher-performance cells and thermal management.

- **Field / plausibility:** Electrochemistry; Experimental. Ruleset: both.
- **Prerequisites:** T007, T012, T015.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 140 precision_components; 105 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Extend vehicle endurance with more expensive battery recipes.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Battery pilot line.
- **Technologies enabled:** T034, T051.
- **Science:** Electrochemistry applied to advanced battery chemistry. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T024 — Grid-Scale Dispatch

Coordinate distributed generation and storage against demand.

- **Field / plausibility:** Control engineering; Established. Ruleset: both.
- **Prerequisites:** T002, T012, T014.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Compute centre (T014).
- **Economic cost:** 160 precision_components; 120 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce avoidable curtailment and expose reserve forecasts.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Grid control centre.
- **Technologies enabled:** T028, T033, T039, T046.
- **Science:** Control engineering applied to grid-scale dispatch. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T025 — Accident-Tolerant Fission

Develop fuel and cooling systems with improved accident tolerance.

- **Field / plausibility:** Nuclear engineering; Experimental. Ruleset: both.
- **Prerequisites:** T007, T013.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 180 precision_components; 135 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce outage exposure at increased component cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Advanced fission works.
- **Technologies enabled:** T042.
- **Science:** Nuclear engineering applied to accident-tolerant fission. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T026 — Automated Prospecting

Combine robotic sampling and grade estimation.

- **Field / plausibility:** Geology; Experimental. Ruleset: both.
- **Prerequisites:** T003, T019, T021.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Drone workshop (T019).
- **Economic cost:** 100 precision_components; 75 prototype industrial work.
- **Power:** 15 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Survey expansion sites without manual sampler orders.
- **Units unlocked:** Survey rover.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T063.
- **Science:** Geology applied to automated prospecting. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T027 — Additive Precision Manufacturing

Qualify complex parts through additive processes and inspection.

- **Field / plausibility:** Manufacturing; Experimental. Ruleset: both.
- **Prerequisites:** T007, T021.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Robotic factory (T021).
- **Economic cost:** 120 precision_components; 90 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Enable small production batches with lower retooling cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Precision foundry.
- **Technologies enabled:** T035, T047, T062, T089.
- **Science:** Manufacturing applied to additive precision manufacturing. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T028 — Autonomous Freight

Validate driverless cargo dispatch in controlled corridors.

- **Field / plausibility:** Robotics; Experimental. Ruleset: both.
- **Prerequisites:** T017, T021, T024.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Robotic factory (T021).
- **Economic cost:** 140 precision_components; 105 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Automate convoy scheduling while requiring control and repair capacity.
- **Units unlocked:** Autonomous hauler.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T039, T052, T072.
- **Science:** Robotics applied to autonomous freight. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T029 — Wide-Bandgap Power Electronics

Engineer efficient switching components for industrial loads.

- **Field / plausibility:** Semiconductor physics; Established. Ruleset: both.
- **Prerequisites:** T007, T014.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 160 precision_components; 120 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce conversion losses and unlock higher-power drives.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Power-electronics works.
- **Technologies enabled:** T033, T034, T037, T038, T044, T050, T065.
- **Science:** Semiconductor physics applied to wide-bandgap power electronics. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T030 — Adaptive Protection Systems

Coordinate detection and timed interceptors on armoured vehicles.

- **Field / plausibility:** Control engineering; Experimental. Ruleset: both.
- **Prerequisites:** T008, T009, T011, T022.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required; plus one of: 3 domestic_ballistic_trials OR 1 alien_material_assay.
- **Infrastructure:** Vehicle works (T009).
- **Economic cost:** 180 precision_components; 135 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Intercept a limited missile salvo before reloading.
- **Units unlocked:** Active-protection tank.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T051.
- **Science:** Control engineering applied to adaptive protection systems. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T031 — Electronic Countermeasure Networks

Coordinate signal denial and robust friendly communication.

- **Field / plausibility:** Communications; Established. Ruleset: both.
- **Prerequisites:** T011, T014, T022.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Compute centre (T014).
- **Economic cost:** 100 precision_components; 75 prototype industrial work.
- **Power:** 15 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Degrade drone and missile target solutions in a visible radius.
- **Units unlocked:** EW support vehicle.
- **Buildings unlocked:** Electronic warfare mast.
- **Technologies enabled:** T032, T040.
- **Science:** Communications applied to electronic countermeasure networks. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T032 — Autonomous Strike Drones

Integrate constrained autonomous navigation and attack control.

- **Field / plausibility:** Robotics; Experimental. Ruleset: both.
- **Prerequisites:** T019, T021, T031.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Drone workshop (T019).
- **Economic cost:** 120 precision_components; 90 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Field cheap strike craft vulnerable to jamming and point defence.
- **Units unlocked:** Strike drone.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Robotics applied to autonomous strike drones. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T033 — Directed-Energy Demonstrators

Test high-power beam generation with realistic cooling.

- **Field / plausibility:** Photonics; Experimental. Ruleset: both.
- **Prerequisites:** T007, T024, T029.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 140 precision_components; 105 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock short-range counter-drone laser prototypes with heat limits.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Laser test range.
- **Technologies enabled:** T049.
- **Science:** Photonics applied to directed-energy demonstrators. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T034 — Hypersonic Guidance

Integrate thermal protection with high-speed terminal guidance.

- **Field / plausibility:** Aeronautics; Experimental. Ruleset: both.
- **Prerequisites:** T010, T018, T023, T029.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Air pad (T010).
- **Economic cost:** 160 precision_components; 120 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock expensive fast strike sorties with specialized maintenance.
- **Units unlocked:** Hypersonic strike craft.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Aeronautics applied to hypersonic guidance. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T035 — Advanced Composites

Qualify lightweight structural composites at scale.

- **Field / plausibility:** Materials science; Experimental. Ruleset: both.
- **Prerequisites:** T007, T022, T027.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 180 precision_components; 135 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Offer lighter chassis recipes that cost more specialist work.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Composite foundry.
- **Technologies enabled:** T037, T038, T043, T056, T061, T069, T125.
- **Science:** Materials science applied to advanced composites. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T036 — Research Universities

Build training and research institutions for specialist cohorts.

- **Field / plausibility:** Education; Established. Ruleset: both.
- **Prerequisites:** T015, T016.
- **Research:** 150 theory work + 75 experimental work; 5 specialist capacity, 2 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Research laboratory (T015).
- **Economic cost:** 100 precision_components; 75 prototype industrial work.
- **Power:** 15 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Increase specialist training capacity over campaign time.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Research university.
- **Technologies enabled:** T054, T055, T058, T078.
- **Science:** Education applied to research universities. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T037 — Plasma Diagnostics

Measure high-temperature plasma behavior accurately.

- **Field / plausibility:** Plasma physics; Established. Ruleset: both.
- **Prerequisites:** T015, T029, T035.
- **Research:** 180 theory work + 90 experimental work; 6 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Research laboratory (T015).
- **Economic cost:** 120 precision_components; 90 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Supply validated confinement data for fusion experiments.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Plasma laboratory.
- **Technologies enabled:** T038, T041.
- **Science:** Plasma physics applied to plasma diagnostics. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Underlying named technique is demonstrated; this game deployment is an abstraction.

### T038 — High-Field Superconducting Magnets

Engineer high-field magnets with demanding cryogenic support.

- **Field / plausibility:** Condensed matter physics; Experimental. Ruleset: both.
- **Prerequisites:** T007, T029, T035, T037.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 140 precision_components; 105 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock compact experimental confinement and cryogenic loads.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Magnet works.
- **Technologies enabled:** T041, T042, T046, T050, T056, T059, T087, T106.
- **Science:** Condensed matter physics applied to high-field superconducting magnets. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T039 — Distributed Factory Control

Coordinate production without relying on one central controller.

- **Field / plausibility:** Computer science; Experimental. Ruleset: both.
- **Prerequisites:** T021, T024, T028.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Robotic factory (T021).
- **Economic cost:** 160 precision_components; 120 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Keep isolated factories following local reserve policies.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Industrial control hub.
- **Technologies enabled:** T047, T052, T055, T061, T076.
- **Science:** Computer science applied to distributed factory control. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T040 — Alien Interface Isolation

Run recovered control systems behind verifiable interfaces.

- **Field / plausibility:** Computer security; Experimental. Ruleset: both.
- **Prerequisites:** T020, T022, T031.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Alien analysis lab (T020).
- **Economic cost:** 180 precision_components; 135 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Permit alien module testing without granting automatic trust.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Quarantine integration lab.
- **Technologies enabled:** T093, T099, T132.
- **Science:** Computer security applied to alien interface isolation. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

## Era 3 — Fusion Civilization

### T041 — Burning-Plasma Control

Control self-heating fusion plasma under changing conditions.

- **Field / plausibility:** Plasma physics; Experimental. Ruleset: both.
- **Prerequisites:** T022, T037, T038.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Plasma laboratory (T037).
- **Economic cost:** 140 fusion_industrial_kits; 105 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock repeatable fusion experiments that require stable power.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Fusion experimental reactor.
- **Technologies enabled:** T042, T043, T044, T045, T057, T079, T105.
- **Science:** Plasma physics applied to burning-plasma control. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.
- **Science boundary references:** [iter-engineering](https://www.iter.org/fusion-energy/making-it-work).

### T042 — Tritium Breeding Blankets

Integrate lithium breeding and fuel recovery around a neutron source.

- **Field / plausibility:** Nuclear engineering; Experimental. Ruleset: both.
- **Prerequisites:** T025, T038, T041.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Fusion experimental reactor (T041).
- **Economic cost:** 160 fusion_industrial_kits; 120 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Produce fusion fuel at a cost in materials and processing.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Breeding blanket works.
- **Technologies enabled:** T045.
- **Science:** Nuclear engineering applied to tritium breeding blankets. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.
- **Science boundary references:** [iter-engineering](https://www.iter.org/fusion-energy/making-it-work).

### T043 — Neutron-Resistant Materials

Qualify structural materials under sustained neutron damage.

- **Field / plausibility:** Materials science; Experimental. Ruleset: both.
- **Prerequisites:** T007, T035, T041.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Materials laboratory (T007).
- **Economic cost:** 180 fusion_industrial_kits; 135 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Extend fusion maintenance intervals with specialized replacement parts.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Irradiation test facility.
- **Technologies enabled:** T044, T045, T049, T057, T083, T102.
- **Science:** Materials science applied to neutron-resistant materials. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.
- **Science boundary references:** [iter-engineering](https://www.iter.org/fusion-energy/making-it-work).

### T044 — Fusion Heat Extraction

Convert intense reactor heat into useful industrial output.

- **Field / plausibility:** Thermal engineering; Experimental. Ruleset: both.
- **Prerequisites:** T029, T041, T043.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Fusion experimental reactor (T041).
- **Economic cost:** 200 fusion_industrial_kits; 150 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock fusion heat exchangers and their cooling requirements.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Fusion heat plant.
- **Technologies enabled:** T045, T048, T053, T066.
- **Science:** Thermal engineering applied to fusion heat extraction. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.
- **Science boundary references:** [iter-engineering](https://www.iter.org/fusion-energy/making-it-work).

### T045 — Commercial Fusion Commissioning

Integrate fuel cycle and plant systems into delivered electrical output.

- **Field / plausibility:** Energy engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T041, T042, T043, T044.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 15 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Fusion experimental reactor (T041).
- **Economic cost:** 220 fusion_industrial_kits; 165 prototype industrial work.
- **Power:** 40 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Build fusion stations only after the complete supporting chain.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Fusion power station.
- **Technologies enabled:** T046, T047, T048, T053, T054, T057, T060.
- **Science:** Energy engineering applied to commercial fusion commissioning. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.
- **Science boundary references:** [iter-engineering](https://www.iter.org/fusion-energy/making-it-work).

### T046 — Superconducting Distribution

Operate low-loss distribution with cryogenic maintenance.

- **Field / plausibility:** Electrical engineering; Experimental. Ruleset: both.
- **Prerequisites:** T024, T038, T045.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Magnet works (T038).
- **Economic cost:** 140 fusion_industrial_kits; 105 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Carry high power through compact links at a cooling cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Cryogenic substation.
- **Technologies enabled:** T049, T050, T103.
- **Science:** Electrical engineering applied to superconducting distribution. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T047 — Electrified Heavy Industry

Replace selected fuel-fired processes with electric production.

- **Field / plausibility:** Manufacturing; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T021, T027, T039, T045.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Robotic factory (T021).
- **Economic cost:** 160 fusion_industrial_kits; 120 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Change recipes from fuel dependence to high delivered power.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Electric industrial works.
- **Technologies enabled:** T051, T052, T060, T064.
- **Science:** Manufacturing applied to electrified heavy industry. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T048 — Thermal Storage Networks

Store process heat and schedule discharge around demand.

- **Field / plausibility:** Thermal engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T044, T045.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Fusion heat plant (T044).
- **Economic cost:** 180 fusion_industrial_kits; 135 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Buffer industrial heat independently from electrical batteries.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Thermal reservoir.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Thermal engineering applied to thermal storage networks. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T049 — High-Energy Laser Batteries

Combine beam control with sustained electrical and thermal support.

- **Field / plausibility:** Photonics; Experimental. Ruleset: both.
- **Prerequisites:** T033, T043, T046.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Laser test range (T033).
- **Economic cost:** 200 fusion_industrial_kits; 150 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Defend against drones and missiles until heat capacity saturates.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Laser defence battery.
- **Technologies enabled:** T071, T082.
- **Science:** Photonics applied to high-energy laser batteries. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T050 — Electromagnetic Launch Weapons

Engineer repetitive electromagnetic acceleration with wear control.

- **Field / plausibility:** Electromagnetism; Experimental. Ruleset: both.
- **Prerequisites:** T029, T038, T046.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 15 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Magnet works (T038).
- **Economic cost:** 220 fusion_industrial_kits; 165 prototype industrial work.
- **Power:** 40 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Field energy-intensive artillery that still needs projectile supply.
- **Units unlocked:** Railgun artillery.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T068, T071.
- **Science:** Electromagnetism applied to electromagnetic launch weapons. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T051 — Electric Armoured Platforms

Use modular electric drive and high-performance storage.

- **Field / plausibility:** Mechanical engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T009, T023, T030, T047.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Vehicle works (T009).
- **Economic cost:** 140 fusion_industrial_kits; 105 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Trade fuel logistics for charging and battery replacement.
- **Units unlocked:** Electric battle tank.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Mechanical engineering applied to electric armoured platforms. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T052 — Automated Repair Depots

Inspect and replace modular parts with supervised robotic cells.

- **Field / plausibility:** Robotics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T021, T028, T039, T047.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Robotic factory (T021).
- **Economic cost:** 160 fusion_industrial_kits; 120 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Repair units faster when compatible spare modules are stocked.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Automated repair depot.
- **Technologies enabled:** T060, T104.
- **Science:** Robotics applied to automated repair depots. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T053 — Fusion Desalination

Use heat and electricity to support large water-treatment networks.

- **Field / plausibility:** Chemical engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T044, T045.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Fusion heat plant (T044).
- **Economic cost:** 180 fusion_industrial_kits; 135 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Expand arid settlement capacity at an energy and pipeline cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Desalination complex.
- **Technologies enabled:** T054, T058, T075.
- **Science:** Chemical engineering applied to fusion desalination. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T054 — Controlled-Environment Agriculture

Optimize crops in illuminated closed growing environments.

- **Field / plausibility:** Biology; Experimental. Ruleset: both.
- **Prerequisites:** T036, T045, T053.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Research university (T036).
- **Economic cost:** 200 fusion_industrial_kits; 150 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce land dependence while increasing power and nutrient demand.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Vertical farm.
- **Technologies enabled:** T058.
- **Science:** Biology applied to controlled-environment agriculture. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T055 — Autonomous Experimentation

Combine robotic experiments with human-reviewed model selection.

- **Field / plausibility:** Artificial intelligence; Experimental. Ruleset: both.
- **Prerequisites:** T022, T036, T039.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 15 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** AI cluster (T022).
- **Economic cost:** 220 fusion_industrial_kits; 165 prototype industrial work.
- **Power:** 40 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Run more independent trials with compute and instrument limits.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Autonomous science campus.
- **Technologies enabled:** T056, T058, T059, T072, T073, T090, T091, T092, T122, T135.
- **Science:** Artificial intelligence applied to autonomous experimentation. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T056 — Molecular Materials Simulation

Model candidate molecular structures and validate promising ones.

- **Field / plausibility:** Computational chemistry; Experimental. Ruleset: both.
- **Prerequisites:** T022, T035, T038, T055.
- **Research:** 210 theory work + 105 experimental work; 7 specialist capacity, 3 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** AI cluster (T022).
- **Economic cost:** 140 fusion_industrial_kits; 105 prototype industrial work.
- **Power:** 20 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce failed prototype material costs for eligible materials projects.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Molecular simulation centre.
- **Technologies enabled:** T075, T089.
- **Science:** Computational chemistry applied to molecular materials simulation. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T057 — Fusion Propulsion Testbeds

Test plasma exhaust and spacecraft reactor integration.

- **Field / plausibility:** Propulsion; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T041, T043, T045.
- **Research:** 240 theory work + 120 experimental work; 8 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Fusion experimental reactor (T041).
- **Economic cost:** 160 fusion_industrial_kits; 120 prototype industrial work.
- **Power:** 25 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock experimental high-delta-v transfer craft with radiator costs.
- **Units unlocked:** Fusion transfer demonstrator.
- **Buildings unlocked:** Propulsion test range.
- **Technologies enabled:** T061, T063, T070, T088.
- **Science:** Propulsion applied to fusion propulsion testbeds. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T058 — Closed Ecological Loops

Recover water and nutrients while monitoring ecosystem stability.

- **Field / plausibility:** Ecology; Experimental. Ruleset: both.
- **Prerequisites:** T036, T053, T054, T055.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Research university (T036).
- **Economic cost:** 180 fusion_industrial_kits; 135 prototype industrial work.
- **Power:** 30 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Support longer isolated operations with finite makeup supplies.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Closed-ecology laboratory.
- **Technologies enabled:** T067, T074, T084, T133.
- **Science:** Ecology applied to closed ecological loops. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T059 — Quantum Error-Correction Engineering

Scale protected quantum operations and verification.

- **Field / plausibility:** Quantum computing; Experimental. Ruleset: both.
- **Prerequisites:** T015, T038, T055.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Research laboratory (T015).
- **Economic cost:** 200 fusion_industrial_kits; 150 prototype industrial work.
- **Power:** 35 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Provide specialized simulation service rather than universal faster computing.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Quantum computing laboratory.
- **Technologies enabled:** T073, T086, T089, T121, T127, T148.
- **Science:** Quantum computing applied to quantum error-correction engineering. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T060 — Fusion Industrial Standards

Certify interchangeable fusion-era industrial modules.

- **Field / plausibility:** Industrial engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T021, T045, T047, T052.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 15 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Robotic factory (T021).
- **Economic cost:** 220 fusion_industrial_kits; 165 prototype industrial work.
- **Power:** 40 MW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Enable regional conversion templates without free automatic retrofits.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Fusion tooling centre.
- **Technologies enabled:** T061, T076.
- **Science:** Industrial engineering applied to fusion industrial standards. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

## Era 4 — Solar Civilization

### T061 — Reusable Orbital Freight

Integrate reusable launch vehicles with rapid refurbishment.

- **Field / plausibility:** Astronautics; Experimental. Ruleset: both.
- **Prerequisites:** T035, T039, T057, T060.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Propulsion test range (T057).
- **Economic cost:** 180 orbital_components; 135 prototype industrial work.
- **Power:** 25 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Ship finite payloads to orbital industry.
- **Units unlocked:** Orbital cargo launcher.
- **Buildings unlocked:** Launch complex.
- **Technologies enabled:** T062, T063.
- **Science:** Astronautics applied to reusable orbital freight. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T062 — Orbital Assembly

Assemble large structures without terrestrial gravity loading.

- **Field / plausibility:** Manufacturing; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T027, T061.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Launch complex (T061).
- **Economic cost:** 200 orbital_components; 150 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Build spacecraft from delivered components in orbit.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Orbital shipyard.
- **Technologies enabled:** T064, T065, T066, T067, T069, T070, T071, T073, T077, T080, T096.
- **Science:** Manufacturing applied to orbital assembly. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T063 — Asteroid Prospecting

Characterize asteroid composition and accessible trajectories.

- **Field / plausibility:** Planetary science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T026, T057, T061.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Launch complex (T061).
- **Economic cost:** 220 orbital_components; 165 prototype industrial work.
- **Power:** 35 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reveal profitable orbital deposits and transfer costs.
- **Units unlocked:** Asteroid survey probe.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T064, T081.
- **Science:** Planetary science applied to asteroid prospecting. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T064 — Vacuum Resource Processing

Refine off-world material using locally available energy.

- **Field / plausibility:** Metallurgy; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T047, T062, T063.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 16 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 240 orbital_components; 180 prototype industrial work.
- **Power:** 40 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Process asteroid feedstock near extraction instead of returning raw mass.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Asteroid refinery.
- **Technologies enabled:** T068, T072, T076, T079, T108.
- **Science:** Metallurgy applied to vacuum resource processing. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T065 — Orbital Solar Arrays

Deploy modular photovoltaic collectors with orbital maintenance.

- **Field / plausibility:** Energy engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T029, T062.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 260 orbital_components; 195 prototype industrial work.
- **Power:** 45 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Generate power where industry or transmission receivers exist.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Orbital solar farm.
- **Technologies enabled:** T080, T082, T086, T101.
- **Science:** Energy engineering applied to orbital solar arrays. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T066 — Radiator Engineering

Reject spacecraft and habitat waste heat through optimized surfaces.

- **Field / plausibility:** Thermal engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T044, T062.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 180 orbital_components; 135 prototype industrial work.
- **Power:** 25 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Increase supported industrial power at a mass and vulnerability cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Radiator yard.
- **Technologies enabled:** T067, T070, T077, T083, T087, T102, T114, T129.
- **Science:** Thermal engineering applied to radiator engineering. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T067 — Rotating Habitats

Combine rotation and shielding for long-duration habitation.

- **Field / plausibility:** Space architecture; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T058, T062, T066.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 200 orbital_components; 150 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Support biological populations off-world.
- **Units unlocked:** Habitat ferry.
- **Buildings unlocked:** O'Neill habitat.
- **Technologies enabled:** T078, T085, T109, T184.
- **Science:** Space architecture applied to rotating habitats. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T068 — Mass-Driver Freight

Accelerate robust cargo from low-gravity industrial sites.

- **Field / plausibility:** Electromagnetism; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T050, T064.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Asteroid refinery (T064).
- **Economic cost:** 220 orbital_components; 165 prototype industrial work.
- **Power:** 35 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Replace some propellant demand with electricity and receiver infrastructure.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Mass-driver terminal.
- **Technologies enabled:** T069, T077, T080, T108.
- **Science:** Electromagnetism applied to mass-driver freight. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T069 — Lunar Elevator Systems

Engineer a tether transport system for the lunar environment.

- **Field / plausibility:** Materials science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T035, T062, T068.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 16 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 240 orbital_components; 180 prototype industrial work.
- **Power:** 40 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Provide steady low-gravity cargo lift with repairable throughput limits.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Lunar elevator.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Materials science applied to lunar elevator systems. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T070 — Fusion Transfer Fleets

Commission maintainable fusion-powered cargo spacecraft.

- **Field / plausibility:** Propulsion; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T057, T062, T066.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Propulsion test range (T057).
- **Economic cost:** 260 orbital_components; 195 prototype industrial work.
- **Power:** 45 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Move bulk freight between worlds with explicit fuel and travel time.
- **Units unlocked:** Fusion freighter.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T078, T080.
- **Science:** Propulsion applied to fusion transfer fleets. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T071 — Planetary Defence Integration

Coordinate ground and orbital defence with trajectory prediction.

- **Field / plausibility:** Military science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T049, T050, T062.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 180 orbital_components; 135 prototype industrial work.
- **Power:** 25 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Protect launch corridors using layered intercept assets.
- **Units unlocked:** Orbital interceptor.
- **Buildings unlocked:** Planetary defence array.
- **Technologies enabled:** T096.
- **Science:** Military science applied to planetary defence integration. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T072 — Autonomous Mining Swarms

Coordinate distributed excavation and processing machines.

- **Field / plausibility:** Robotics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T028, T055, T064.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Asteroid refinery (T064).
- **Economic cost:** 200 orbital_components; 150 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Automate extraction within a capped maintenance and reproduction budget.
- **Units unlocked:** Mining drone swarm.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T076.
- **Science:** Robotics applied to autonomous mining swarms. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T073 — Orbital Laboratories

Perform experiments requiring vacuum and long-duration microgravity.

- **Field / plausibility:** Experimental physics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T055, T059, T062.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 220 orbital_components; 165 prototype industrial work.
- **Power:** 35 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Provide dedicated research infrastructure for orbital science.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Orbital laboratory.
- **Technologies enabled:** T074, T075, T077, T079, T081, T083, T086, T094, T141.
- **Science:** Experimental physics applied to orbital laboratories. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T074 — Radiation-Hardened Biology

Investigate repair pathways and protection for space habitation.

- **Field / plausibility:** Genetics; Experimental. Ruleset: both.
- **Prerequisites:** T016, T058, T073.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 16 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 240 orbital_components; 180 prototype industrial work.
- **Power:** 40 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Offer optional biological resilience at a specialist healthcare cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Space medicine institute.
- **Technologies enabled:** T084, T085, T091, T098, T121.
- **Science:** Genetics applied to radiation-hardened biology. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T075 — Planetary Climate Models

Predict coupled atmosphere and surface responses.

- **Field / plausibility:** Planetary science; Experimental. Ruleset: both.
- **Prerequisites:** T053, T056, T073.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 260 orbital_components; 195 prototype industrial work.
- **Power:** 45 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Preview terraforming costs and failure margins.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Planetary climate observatory.
- **Technologies enabled:** T109, T117.
- **Science:** Planetary science applied to planetary climate models. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T076 — Self-Replicating Industrial Seeds

Close enough manufacturing loops for industrial reproduction.

- **Field / plausibility:** Robotics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T039, T060, T064, T072.
- **Research:** 270 theory work + 135 experimental work; 9 specialist capacity, 4 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Asteroid refinery (T064).
- **Economic cost:** 180 orbital_components; 135 prototype industrial work.
- **Power:** 25 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Build seed factories that consume feedstock and cap their own growth.
- **Units unlocked:** Industrial seed vessel.
- **Buildings unlocked:** Seed factory.
- **Technologies enabled:** T080, T092, T093, T101, T108.
- **Science:** Robotics applied to self-replicating industrial seeds. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T077 — Orbital Ring Dynamics

Model and actively stabilize large orbital transport structures.

- **Field / plausibility:** Orbital mechanics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T062, T066, T068, T073.
- **Research:** 300 theory work + 150 experimental work; 10 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 200 orbital_components; 150 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Start phased orbital-ring construction.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Orbital ring foundation.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Orbital mechanics applied to orbital ring dynamics. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T078 — Interplanetary Governance

Delegate policy under transport and communications delay.

- **Field / plausibility:** Political systems; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T036, T067, T070.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** O'Neill habitat (T067).
- **Economic cost:** 220 orbital_components; 165 prototype industrial work.
- **Power:** 35 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Automate planetary budgets with reserves and audit trails.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Planetary governance centre.
- **Technologies enabled:** T080, T085, T092, T118.
- **Science:** Political systems applied to interplanetary governance. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T079 — Helium-3 Fuel Studies

Investigate demanding alternative fusion fuel cycles.

- **Field / plausibility:** Nuclear physics; Experimental. Ruleset: both.
- **Prerequisites:** T041, T064, T073.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 16 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 240 orbital_components; 180 prototype industrial work.
- **Power:** 40 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Open an optional fuel route without replacing the baseline D-T chain.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Advanced fuel laboratory.
- **Technologies enabled:** T107.
- **Science:** Nuclear physics applied to helium-3 fuel studies. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T080 — Solar-System Industrial Network

Standardize commerce among specialized orbital and planetary economies.

- **Field / plausibility:** Systems engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T062, T065, T068, T070, T076, T078.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 260 orbital_components; 195 prototype industrial work.
- **Power:** 45 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Enable system-wide contracts with local inventories and travel delays.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Solar logistics exchange.
- **Technologies enabled:** T081, T095, T100, T103.
- **Science:** Systems engineering applied to solar-system industrial network. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

## Era 5 — Interstellar Civilization

### T081 — Interstellar Navigation

Map stellar targets and relativistic trajectory constraints.

- **Field / plausibility:** Astronomy; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T063, T073, T080.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 5 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 220 interstellar_components; 165 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Plan expeditions with visible transit and braking requirements.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Interstellar observatory.
- **Technologies enabled:** T082, T083, T092, T094, T095, T097, T099, T105.
- **Science:** Astronomy applied to interstellar navigation. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T082 — Beamed Sail Propulsion

Accelerate light sails using distant beam infrastructure.

- **Field / plausibility:** Photonics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T049, T065, T081.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital solar farm (T065).
- **Economic cost:** 240 interstellar_components; 180 prototype industrial work.
- **Power:** 35 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Launch small fast probes while committing beam-array power.
- **Units unlocked:** Beam sail probe.
- **Buildings unlocked:** Sail launch array.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Photonics applied to beamed sail propulsion. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T083 — Relativistic Shielding

Protect fast spacecraft against dust and energetic particles.

- **Field / plausibility:** Materials science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T043, T066, T073, T081.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 15 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 260 interstellar_components; 195 prototype industrial work.
- **Power:** 40 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Trade payload for interstellar transit survivability.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Relativistic test facility.
- **Technologies enabled:** T085, T088, T096, T097.
- **Science:** Materials science applied to relativistic shielding. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T084 — Long-Duration Hibernation

Explore controlled reduction of biological activity over long travel.

- **Field / plausibility:** Medicine; Highly speculative. Ruleset: both.
- **Prerequisites:** T058, T074.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 20 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Space medicine institute (T074).
- **Economic cost:** 280 interstellar_components; 210 prototype industrial work.
- **Power:** 45 GW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Offer an optional biological transport mode with revival risk budgeting.
- **Units unlocked:** Hibernation transport.
- **Buildings unlocked:** Hibernation institute.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Metabolic suppression and cryobiology. Assumption: Reversible long-duration suspension of whole humans without unacceptable injury. Status: Partial biological precedents do not establish centuries-long human hibernation.

### T085 — Generation Habitats

Sustain populations and institutions across many generations.

- **Field / plausibility:** Ecology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T067, T074, T078, T083.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 25 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** O'Neill habitat (T067).
- **Economic cost:** 300 interstellar_components; 225 prototype industrial work.
- **Power:** 50 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Transport biological civilizations without requiring suspended animation.
- **Units unlocked:** Generation ark.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T100, T184.
- **Science:** Ecology applied to generation habitats. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T086 — Antimatter Synthesis

Produce antiparticles using externally supplied energy.

- **Field / plausibility:** Particle physics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T059, T065, T073.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 5 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 220 interstellar_components; 165 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Manufacture an expensive energy carrier with explicit losses.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Antimatter production facility.
- **Technologies enabled:** T087.
- **Science:** Particle physics applied to antimatter synthesis. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.
- **Science boundary references:** [cern-antimatter](https://home.cern/science/physics/antimatter/).

### T087 — Antimatter Containment

Investigate long-duration containment at useful stored quantities.

- **Field / plausibility:** Plasma physics; Highly speculative. Ruleset: both.
- **Prerequisites:** T038, T066, T086.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 10 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Antimatter production facility (T086).
- **Economic cost:** 240 interstellar_components; 180 prototype industrial work.
- **Power:** 35 GW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Store limited antimatter with continuous power and containment upkeep.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Antimatter containment vault.
- **Technologies enabled:** T088, T119.
- **Science:** Matter-antimatter annihilation and electromagnetic trapping. Assumption: Bulk production, stable storage and useful conversion at engineering scale. Status: Particle physics is established; proposed macroscopic handling performance is unproved.
- **Science boundary references:** [cern-antimatter](https://home.cern/science/physics/antimatter/).

### T088 — Antimatter-Assisted Propulsion

Use scarce antimatter to assist high-energy propulsion concepts.

- **Field / plausibility:** Propulsion; Highly speculative. Ruleset: both.
- **Prerequisites:** T057, T083, T087.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 15 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Propulsion test range (T057).
- **Economic cost:** 260 interstellar_components; 195 prototype industrial work.
- **Power:** 40 GW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Field fast couriers with extreme fuel and maintenance costs.
- **Units unlocked:** Antimatter courier.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T184.
- **Science:** Matter-antimatter annihilation and electromagnetic trapping. Assumption: Bulk production, stable storage and useful conversion at engineering scale. Status: Particle physics is established; proposed macroscopic handling performance is unproved.
- **Science boundary references:** [cern-antimatter](https://home.cern/science/physics/antimatter/).

### T089 — Atomic-Scale Fabrication

Extend atomically precise processes toward useful manufacturing.

- **Field / plausibility:** Nanotechnology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T027, T056, T059.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Molecular simulation centre (T056).
- **Economic cost:** 280 interstellar_components; 210 prototype industrial work.
- **Power:** 45 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Produce specialized components from selected feedstocks and computation.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Atomic manufacturing pilot.
- **Technologies enabled:** T090, T102, T130.
- **Science:** Nanotechnology applied to atomic-scale fabrication. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T090 — Molecular Assembly Control

Control feedstock chemistry and verification in precise assembly.

- **Field / plausibility:** Chemistry; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T055, T089.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 25 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Atomic manufacturing pilot (T089).
- **Economic cost:** 300 interstellar_components; 225 prototype industrial work.
- **Power:** 50 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Expand compatible recipes; never transmute arbitrary elements for free.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Molecular assembly works.
- **Technologies enabled:** T100, T107, T113, T119, T126, T130, T138, T157.
- **Science:** Chemistry applied to molecular assembly control. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T091 — Adaptive Genetic Medicine

Tailor interventions for diverse long-duration habitats.

- **Field / plausibility:** Genetics; Experimental. Ruleset: both.
- **Prerequisites:** T055, T074.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 5 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Space medicine institute (T074).
- **Economic cost:** 220 interstellar_components; 165 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce selected habitat-support burdens through optional population traits.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Genomic medicine centre.
- **Technologies enabled:** T098, T121, T125, T133, T139.
- **Science:** Genetics applied to adaptive genetic medicine. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T092 — Interstellar Autonomy

Validate mission control that can operate without prompt home commands.

- **Field / plausibility:** Artificial intelligence; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T055, T076, T078, T081.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Seed factory (T076).
- **Economic cost:** 240 interstellar_components; 180 prototype industrial work.
- **Power:** 35 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Give expeditions bounded self-governance and contingency plans.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Autonomy verification centre.
- **Technologies enabled:** T093, T095, T096, T101, T146, T174.
- **Science:** Artificial intelligence applied to interstellar autonomy. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T093 — Replicator Safeguards

Require authenticated reproduction budgets and error checks.

- **Field / plausibility:** Computer security; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T040, T076, T092.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 15 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Autonomy verification centre (T092).
- **Economic cost:** 260 interstellar_components; 195 prototype industrial work.
- **Power:** 40 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Limit seed growth and reduce corrupted manufacturing spread.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Replicator certification yard.
- **Technologies enabled:** T100, T104, T123, T126, T128, T132, T136, T164, T176.
- **Science:** Computer security applied to replicator safeguards. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T094 — Stellar Interferometry

Combine widely separated observations of distant systems.

- **Field / plausibility:** Astronomy; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T073, T081.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Interstellar observatory (T081).
- **Economic cost:** 280 interstellar_components; 210 prototype industrial work.
- **Power:** 45 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Improve origin triangulation and long-range threat forecasts.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Distributed telescope array.
- **Technologies enabled:** T097, T099, T105, T141, T142, T161, T167.
- **Science:** Astronomy applied to stellar interferometry. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T095 — Interstellar Supply Caches

Pre-position serviceable fuel and parts along expedition plans.

- **Field / plausibility:** Logistics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T080, T081, T092.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 25 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Solar logistics exchange (T080).
- **Economic cost:** 300 interstellar_components; 225 prototype industrial work.
- **Power:** 50 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Support long-range operations without instantaneous reinforcement.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Interstellar cache.
- **Technologies enabled:** T096, T100, T116, T137, T153.
- **Science:** Logistics applied to interstellar supply caches. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T096 — Autonomous Escort Fleets

Deploy long-endurance escort formations with local rules of engagement.

- **Field / plausibility:** Military science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T062, T071, T083, T092, T095.
- **Research:** 330 theory work + 165 experimental work; 11 specialist capacity, 5 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital shipyard (T062).
- **Economic cost:** 220 interstellar_components; 165 prototype industrial work.
- **Power:** 30 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Protect arks and logistics against interception.
- **Units unlocked:** Ark escort.
- **Buildings unlocked:** Escort assembly dock.
- **Technologies enabled:** T097, T115, T174.
- **Science:** Military science applied to autonomous escort fleets. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T097 — Relativistic Intercept Modelling

Model fast threats and feasible interception windows.

- **Field / plausibility:** Astrodynamics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T081, T083, T094, T096.
- **Research:** 360 theory work + 180 experimental work; 12 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Interstellar observatory (T081).
- **Economic cost:** 240 interstellar_components; 180 prototype industrial work.
- **Power:** 35 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock defended approach corridors with explicit warning assumptions.
- **Units unlocked:** Relativistic interceptor.
- **Buildings unlocked:** Deep-space defence station.
- **Technologies enabled:** T115, T165.
- **Science:** Astrodynamics applied to relativistic intercept modelling. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T098 — Exobiological Compatibility

Characterize alien ecological interfaces and incompatible chemistry.

- **Field / plausibility:** Biology; Experimental. Ruleset: both.
- **Prerequisites:** T020, T074, T091.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 15 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Space medicine institute (T074).
- **Economic cost:** 260 interstellar_components; 195 prototype industrial work.
- **Power:** 40 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Open quarantine-safe contact and habitat exchange options.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Exobiology institute.
- **Technologies enabled:** T117, T177.
- **Science:** Biology applied to exobiological compatibility. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T099 — Alien Signal Archaeology

Interpret archived relay signatures against astronomical timing.

- **Field / plausibility:** Information theory; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T040, T081, T094.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 20 compute service; at most 2 parallel experiments. 3 alien_relay_record: Three guaranteed campaign relay sites; alternate sites regenerate objective evidence if cargo is lost..
- **Infrastructure:** Interstellar observatory (T081).
- **Economic cost:** 280 interstellar_components; 210 prototype industrial work.
- **Power:** 45 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Triangulate expedition origins without omniscient narrative coordinates.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Signal archaeology array.
- **Technologies enabled:** T177.
- **Science:** Information theory applied to alien signal archaeology. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T100 — Independent System Economies

Close essential industrial and institutional loops in a remote system.

- **Field / plausibility:** Economics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T080, T085, T090, T093, T095.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 25 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Solar logistics exchange (T080).
- **Economic cost:** 300 interstellar_components; 225 prototype industrial work.
- **Power:** 50 GW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Commission autonomous systems with enforceable export reserves.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** System capital.
- **Technologies enabled:** T101, T118, T159.
- **Science:** Economics applied to independent system economies. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

## Era 6 — Stellar Engineering Civilization

### T101 — Collector Swarm Coordination

Maintain large populations of independently orbiting collectors.

- **Field / plausibility:** Orbital mechanics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T065, T076, T092, T100.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital solar farm (T065).
- **Economic cost:** 260 stellar_fabrication_lots; 195 prototype industrial work.
- **Power:** 35 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Expand captured stellar power through incremental construction.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Dyson collector foundry.
- **Technologies enabled:** T102, T103, T104, T111, T114.
- **Science:** Orbital mechanics applied to collector swarm coordination. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T102 — High-Temperature Collectors

Qualify collector materials closer to intense stellar radiation.

- **Field / plausibility:** Materials science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T043, T066, T089, T101.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Dyson collector foundry (T101).
- **Economic cost:** 280 stellar_fabrication_lots; 210 prototype industrial work.
- **Power:** 40 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Raise output per collector at higher maintenance and shielding cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** High-temperature collector works.
- **Technologies enabled:** T105, T110, T145.
- **Science:** Materials science applied to high-temperature collectors. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T103 — Stellar Power Routing

Coordinate beamed power and regional receivers.

- **Field / plausibility:** Electrical engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T046, T080, T101.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Dyson collector foundry (T101).
- **Economic cost:** 300 stellar_fabrication_lots; 225 prototype industrial work.
- **Power:** 45 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Route captured energy through vulnerable finite-throughput links.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar power receiver.
- **Technologies enabled:** T106, T108, T110, T116, T119, T144.
- **Science:** Electrical engineering applied to stellar power routing. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T104 — Swarm Maintenance Ecologies

Recycle and repair collector modules across distributed yards.

- **Field / plausibility:** Robotics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T052, T093, T101.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 24 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Dyson collector foundry (T101).
- **Economic cost:** 320 stellar_fabrication_lots; 240 prototype industrial work.
- **Power:** 50 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Sustain a swarm without exponential free replication.
- **Units unlocked:** Collector repair swarm.
- **Buildings unlocked:** Swarm service yard.
- **Technologies enabled:** T113, T115, T120.
- **Science:** Robotics applied to swarm maintenance ecologies. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T105 — Stellar Plasma Modelling

Predict plasma behavior and extraction effects at stellar scale.

- **Field / plausibility:** Astrophysics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T041, T081, T094, T102.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 30 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Interstellar observatory (T081).
- **Economic cost:** 340 stellar_fabrication_lots; 255 prototype industrial work.
- **Power:** 55 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Forecast lifting yield and stellar disturbance margins.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar dynamics observatory.
- **Technologies enabled:** T106, T111, T143, T183, T188.
- **Science:** Astrophysics applied to stellar plasma modelling. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T106 — Magnetic Star Lifting

Investigate controlled extraction of stellar plasma.

- **Field / plausibility:** Plasma engineering; Highly speculative. Ruleset: both.
- **Prerequisites:** T038, T103, T105.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 6 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar dynamics observatory (T105).
- **Economic cost:** 260 stellar_fabrication_lots; 195 prototype industrial work.
- **Power:** 35 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Extract feedstock while paying power and separation costs.
- **Units unlocked:** Stellar extraction tender.
- **Buildings unlocked:** Star-lifting array.
- **Technologies enabled:** T107, T112, T118, T183.
- **Science:** Stellar plasma physics and momentum conservation. Assumption: Controllable sustained stellar mass flows or coordinated stellar motion at useful scale. Status: No demonstrated stellar engineering; extrapolation is constrained by energy and momentum.

### T107 — Stellar Isotope Separation

Separate useful constituents from extracted stellar material.

- **Field / plausibility:** Nuclear chemistry; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T079, T090, T106.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Star-lifting array (T106).
- **Economic cost:** 280 stellar_fabrication_lots; 210 prototype industrial work.
- **Power:** 40 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Convert mixed plasma feed into industrial fuel and matter streams.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar separator.
- **Technologies enabled:** T112, T113, T120, T143.
- **Science:** Nuclear chemistry applied to stellar isotope separation. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T108 — Planetary Disassembly

Dismantle a selected uninhabited world into managed material streams.

- **Field / plausibility:** Industrial engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T064, T068, T076, T103.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Asteroid refinery (T064).
- **Economic cost:** 300 stellar_fabrication_lots; 225 prototype industrial work.
- **Power:** 45 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Trade an irreversible planetary asset for construction feedstock.
- **Units unlocked:** Disassembly flotilla.
- **Buildings unlocked:** Planet-disassembly yard.
- **Technologies enabled:** T109.
- **Science:** Industrial engineering applied to planetary disassembly. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T109 — Artificial World Foundations

Design large engineered habitats and world-scale support structures.

- **Field / plausibility:** Space architecture; Highly speculative. Ruleset: both.
- **Prerequisites:** T067, T075, T108.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 24 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Planet-disassembly yard (T108).
- **Economic cost:** 320 stellar_fabrication_lots; 240 prototype industrial work.
- **Power:** 50 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Begin habitable artificial-world projects with continuing upkeep.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Artificial world yard.
- **Technologies enabled:** T117.
- **Science:** Orbital habitats and planetary structure. Assumption: Stable large engineered habitats and long-term ecological support. Status: Engineering feasibility at artificial-world scale is unproved; no free creation of mass.

### T110 — Full-Spectrum Harvesting

Match conversion systems to different stellar emission bands.

- **Field / plausibility:** Photonics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T102, T103.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 30 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** High-temperature collector works (T102).
- **Economic cost:** 340 stellar_fabrication_lots; 255 prototype industrial work.
- **Power:** 55 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Improve usable output while preserving heat and conversion losses.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Spectrum conversion complex.
- **Technologies enabled:** T111, T114.
- **Science:** Photonics applied to full-spectrum harvesting. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T111 — Radiation-Pressure Stellar Engines

Apply asymmetric stellar radiation pressure over long durations.

- **Field / plausibility:** Astrodynamics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T101, T105, T110.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Dyson collector foundry (T101).
- **Economic cost:** 260 stellar_fabrication_lots; 195 prototype industrial work.
- **Power:** 35 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Start slow stellar relocation with an exposed collector array.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Shkadov-style engine.
- **Technologies enabled:** T112, T169.
- **Science:** Astrodynamics applied to radiation-pressure stellar engines. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T112 — Mass-Flow Stellar Engines

Use controlled stellar material flows to produce directed thrust.

- **Field / plausibility:** Propulsion; Highly speculative. Ruleset: both.
- **Prerequisites:** T106, T107, T111.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 12 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Star-lifting array (T106).
- **Economic cost:** 280 stellar_fabrication_lots; 210 prototype industrial work.
- **Power:** 40 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Move stellar routes faster at extreme infrastructure commitment.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Mass-flow stellar engine.
- **Technologies enabled:** T169.
- **Science:** Stellar plasma physics and momentum conservation. Assumption: Controllable sustained stellar mass flows or coordinated stellar motion at useful scale. Status: No demonstrated stellar engineering; extrapolation is constrained by energy and momentum.

### T113 — Stellar-Scale Fabrication

Expand production across many automated industrial nodes.

- **Field / plausibility:** Manufacturing; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T090, T104, T107.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar separator (T107).
- **Economic cost:** 300 stellar_fabrication_lots; 225 prototype industrial work.
- **Power:** 45 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Allocate stellar industrial work without simulating every machine.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar manufacturing nexus.
- **Technologies enabled:** T115, T116, T120, T126, T130, T162.
- **Science:** Manufacturing applied to stellar-scale fabrication. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T114 — Matrioshka Thermal Architecture

Stage computation and radiation through multiple temperature shells.

- **Field / plausibility:** Computer engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T066, T101, T110.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 24 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Dyson collector foundry (T101).
- **Economic cost:** 320 stellar_fabrication_lots; 240 prototype industrial work.
- **Power:** 50 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Plan layered compute megastructures with finite cooling budgets.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Matrioshka foundation.
- **Technologies enabled:** T122, T124, T127, T128.
- **Science:** Computer engineering applied to matrioshka thermal architecture. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T115 — Megastructure Defence Geometry

Protect distributed industrial structures through layered coverage.

- **Field / plausibility:** Military science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T096, T097, T104, T113.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 30 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Escort assembly dock (T096).
- **Economic cost:** 340 stellar_fabrication_lots; 255 prototype industrial work.
- **Power:** 55 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Deploy defence formations with repair and interception priorities.
- **Units unlocked:** Collector guard.
- **Buildings unlocked:** Megastructure defence hub.
- **Technologies enabled:** T116, T136, T165, T175.
- **Science:** Military science applied to megastructure defence geometry. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T116 — Stellar Siege Logistics

Supply prolonged operations across stellar industrial space.

- **Field / plausibility:** Logistics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T095, T103, T113, T115.
- **Research:** 390 theory work + 195 experimental work; 13 specialist capacity, 6 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Interstellar cache (T095).
- **Economic cost:** 260 stellar_fabrication_lots; 195 prototype industrial work.
- **Power:** 35 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Field siege formations that depend on vulnerable support trains.
- **Units unlocked:** Stellar siege fleet.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T175.
- **Science:** Logistics applied to stellar siege logistics. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T117 — Habitable-System Preservation

Constrain stellar engineering around inhabited ecosystems.

- **Field / plausibility:** Ecology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T075, T098, T109.
- **Research:** 420 theory work + 210 experimental work; 14 specialist capacity, 12 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Artificial world yard (T109).
- **Economic cost:** 280 stellar_fabrication_lots; 210 prototype industrial work.
- **Power:** 40 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce ecological disruption through costly engineering limits.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Habitability control station.
- **Technologies enabled:** T133, T139, T172, T183.
- **Science:** Ecology applied to habitable-system preservation. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T118 — Stellar Resource Treaties

Coordinate extraction rights among independent system societies.

- **Field / plausibility:** Political systems; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T078, T100, T106.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** System capital (T100).
- **Economic cost:** 300 stellar_fabrication_lots; 225 prototype industrial work.
- **Power:** 45 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock negotiated access and limits on destructive industry.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar assembly.
- **Technologies enabled:** T120, T134, T173, T177.
- **Science:** Political systems applied to stellar resource treaties. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T119 — High-Density Energy Carriers

Integrate dense energy storage with safe transport interfaces.

- **Field / plausibility:** Energy engineering; Highly speculative. Ruleset: both.
- **Prerequisites:** T087, T090, T103.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 24 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Antimatter containment vault (T087).
- **Economic cost:** 320 stellar_fabrication_lots; 240 prototype industrial work.
- **Power:** 50 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Support mobile operations while retaining manufacturing losses.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Energy-carrier port.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Matter-antimatter annihilation and electromagnetic trapping. Assumption: Bulk production, stable storage and useful conversion at engineering scale. Status: Particle physics is established; proposed macroscopic handling performance is unproved.
- **Science boundary references:** [cern-antimatter](https://home.cern/science/physics/antimatter/).

### T120 — Stellar Industrial Sovereignty

Maintain a complete stellar-scale production and governance loop.

- **Field / plausibility:** Systems engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T104, T107, T113, T118.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 30 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar manufacturing nexus (T113).
- **Economic cost:** 340 stellar_fabrication_lots; 255 prototype industrial work.
- **Power:** 55 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Meet stellar maturity through sustained capability rather than one timer.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar capital.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Systems engineering applied to stellar industrial sovereignty. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

## Era 7 — Post-Biological Options

### T121 — Connectome Mapping

Map neural connectivity and function at increasingly fine resolution.

- **Field / plausibility:** Neuroscience; Experimental. Ruleset: both.
- **Prerequisites:** T059, T074, T091.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 7 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Space medicine institute (T074).
- **Economic cost:** 300 verified_compute_modules; 225 prototype industrial work.
- **Power:** 40 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Open optional neural-model research without claiming consciousness transfer.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Neuroscience institute.
- **Technologies enabled:** T122, T123, T125.
- **Science:** Neuroscience applied to connectome mapping. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T122 — Whole-Brain Emulation

Test whether detailed computational models preserve cognitive function.

- **Field / plausibility:** Neuroscience; Highly speculative. Ruleset: both.
- **Prerequisites:** T055, T114, T121.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 14 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Neuroscience institute (T121).
- **Economic cost:** 320 verified_compute_modules; 240 prototype industrial work.
- **Power:** 45 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Unlock an optional digital population route with substantial compute needs.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Emulation research centre.
- **Technologies enabled:** T123, T124.
- **Science:** Neural computation and functional emulation. Assumption: A sufficiently complete emulation preserves relevant cognition and identity. Status: Conscious emulation and continuity of personal identity are unresolved.

### T123 — Mind-State Verification

Compare functional continuity and integrity across emulated states.

- **Field / plausibility:** Information theory; Highly speculative. Ruleset: both.
- **Prerequisites:** T093, T121, T122.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 21 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Emulation research centre (T122).
- **Economic cost:** 340 verified_compute_modules; 255 prototype industrial work.
- **Power:** 50 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Require validation before digital migration and restoration.
- **Units unlocked:** Mind transfer tender.
- **Buildings unlocked:** Mind verification facility.
- **Technologies enabled:** T124, T131.
- **Science:** Neural computation and functional emulation. Assumption: A sufficiently complete emulation preserves relevant cognition and identity. Status: Conscious emulation and continuity of personal identity are unresolved.

### T124 — Digital Habitat Infrastructure

Provide isolated compute environments for emulated populations.

- **Field / plausibility:** Computer engineering; Highly speculative. Ruleset: both.
- **Prerequisites:** T114, T122, T123.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 28 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Matrioshka foundation (T114).
- **Economic cost:** 360 verified_compute_modules; 270 prototype industrial work.
- **Power:** 55 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Convert compute and cooling into digital habitation capacity.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Digital habitat.
- **Technologies enabled:** T131, T137.
- **Science:** Neural computation and functional emulation. Assumption: A sufficiently complete emulation preserves relevant cognition and identity. Status: Conscious emulation and continuity of personal identity are unresolved.

### T125 — Cybernetic Integration

Combine biological function with maintainable prosthetic systems.

- **Field / plausibility:** Biomedical engineering; Experimental. Ruleset: both.
- **Prerequisites:** T035, T091, T121.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 35 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Neuroscience institute (T121).
- **Economic cost:** 380 verified_compute_modules; 285 prototype industrial work.
- **Power:** 60 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Offer hybrid cohorts with specialist parts and medical requirements.
- **Units unlocked:** Cybernetic engineer.
- **Buildings unlocked:** Cybernetics clinic.
- **Technologies enabled:** T134.
- **Science:** Biomedical engineering applied to cybernetic integration. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T126 — Machine Reproduction Standards

Qualify autonomous chassis manufacture and maintenance.

- **Field / plausibility:** Robotics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T090, T093, T113.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 7 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar manufacturing nexus (T113).
- **Economic cost:** 300 verified_compute_modules; 225 prototype industrial work.
- **Power:** 40 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Grow machine cohorts through industrial work rather than food.
- **Units unlocked:** Machine worker cohort.
- **Buildings unlocked:** Machine population foundry.
- **Technologies enabled:** T134, T136, T140, T163.
- **Science:** Robotics applied to machine reproduction standards. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T127 — Reversible Computing Systems

Engineer logically reversible computation with real error handling.

- **Field / plausibility:** Computer science; Experimental. Ruleset: both.
- **Prerequisites:** T059, T114.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 14 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Matrioshka foundation (T114).
- **Economic cost:** 320 verified_compute_modules; 240 prototype industrial work.
- **Power:** 45 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Trade throughput and complexity for lower dissipation on suitable tasks.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Reversible logic foundry.
- **Technologies enabled:** T128, T129, T155, T182, T189.
- **Science:** Computer science applied to reversible computing systems. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.
- **Science boundary references:** [bennett-landauer](https://arxiv.org/abs/physics/0210005).

### T128 — Fault-Tolerant Planetary Compute

Distribute computing with redundancy across independent failure zones.

- **Field / plausibility:** Computer engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T093, T114, T127.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 21 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Matrioshka foundation (T114).
- **Economic cost:** 340 verified_compute_modules; 255 prototype industrial work.
- **Power:** 50 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Provide large reliable compute service with latency costs.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Planetary compute complex.
- **Technologies enabled:** T129, T131, T132, T135, T138, T140, T141, T166.
- **Science:** Computer engineering applied to fault-tolerant planetary compute. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T129 — Cold-Space Computing

Place suitable computation near effective cold radiative sinks.

- **Field / plausibility:** Thermodynamics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T066, T127, T128.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 28 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Planetary compute complex (T128).
- **Economic cost:** 360 verified_compute_modules; 270 prototype industrial work.
- **Power:** 55 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce cooling burden while increasing transport and communication delay.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Cold compute habitat.
- **Technologies enabled:** T138, T148, T170, T189.
- **Science:** Thermodynamics applied to cold-space computing. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T130 — Programmable Materials

Coordinate reconfigurable material assemblies with bounded capabilities.

- **Field / plausibility:** Materials science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T089, T090, T113.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 35 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Molecular assembly works (T090).
- **Economic cost:** 380 verified_compute_modules; 285 prototype industrial work.
- **Power:** 60 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Refit selected structures locally using power and feedstock.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Programmable-material works.
- **Technologies enabled:** T145.
- **Science:** Materials science applied to programmable materials. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T131 — Distributed Identity Protocols

Maintain identity records across separated digital instances.

- **Field / plausibility:** Computer security; Highly speculative. Ruleset: both.
- **Prerequisites:** T123, T124, T128.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 7 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Mind verification facility (T123).
- **Economic cost:** 300 verified_compute_modules; 225 prototype industrial work.
- **Power:** 40 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Make backup and migration policy explicit rather than duplicating free population.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Identity archive.
- **Technologies enabled:** T137, T157.
- **Science:** Neural computation and functional emulation. Assumption: A sufficiently complete emulation preserves relevant cognition and identity. Status: Conscious emulation and continuity of personal identity are unresolved.

### T132 — Civilization Verification Networks

Audit software and industrial standards across autonomous regions.

- **Field / plausibility:** Computer security; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T040, T093, T128.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 14 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Planetary compute complex (T128).
- **Economic cost:** 320 verified_compute_modules; 240 prototype industrial work.
- **Power:** 45 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Limit correlated compromise at a continuing compute cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Verification network hub.
- **Technologies enabled:** T135, T136, T140, T146, T153, T164, T166, T171, T176.
- **Science:** Computer security applied to civilization verification networks. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T133 — Biological Sanctuary Systems

Maintain resilient biological refuges alongside automated societies.

- **Field / plausibility:** Ecology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T058, T091, T117.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 21 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Habitability control station (T117).
- **Economic cost:** 340 verified_compute_modules; 255 prototype industrial work.
- **Power:** 50 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Keep biological civilization viable with lower dependence on one software stack.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Biological sanctuary.
- **Technologies enabled:** T134, T139, T140, T172, T191.
- **Science:** Ecology applied to biological sanctuary systems. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T134 — Hybrid Governance

Represent different population substrates within common institutions.

- **Field / plausibility:** Political systems; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T118, T125, T126, T133.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 28 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar assembly (T118).
- **Economic cost:** 360 verified_compute_modules; 270 prototype industrial work.
- **Power:** 55 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Trade specialized efficiency for diversified resilience.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Hybrid governance forum.
- **Technologies enabled:** T140, T159.
- **Science:** Political systems applied to hybrid governance. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T135 — Self-Redesigning Intelligence

Investigate validated improvement of intelligence architectures.

- **Field / plausibility:** Artificial intelligence; Highly speculative. Ruleset: both.
- **Prerequisites:** T055, T128, T132.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 35 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Planetary compute complex (T128).
- **Economic cost:** 380 verified_compute_modules; 285 prototype industrial work.
- **Power:** 60 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Offer bounded planner efficiency gains with expensive safety verification.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Recursive design laboratory.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Machine learning and automated program design. Assumption: Validated self-modification produces bounded reliable improvements. Status: Open-ended reliable self-improvement is unproved; runaway intelligence is not a physical law.

### T136 — Autonomous Military Ecologies

Coordinate fleets and replacement production through verified local policies.

- **Field / plausibility:** Military science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T093, T115, T126, T132.
- **Research:** 450 theory work + 225 experimental work; 15 specialist capacity, 7 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Machine population foundry (T126).
- **Economic cost:** 300 verified_compute_modules; 225 prototype industrial work.
- **Power:** 40 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Field drone hosts that can sustain themselves only within assigned budgets.
- **Units unlocked:** Distributed drone host.
- **Buildings unlocked:** Autonomous fleet foundry.
- **Technologies enabled:** T163.
- **Science:** Military science applied to autonomous military ecologies. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T137 — Archive Evacuation Doctrine

Plan transfer of digital populations with verified destination capacity.

- **Field / plausibility:** Logistics; Highly speculative. Ruleset: both.
- **Prerequisites:** T095, T124, T131.
- **Research:** 480 theory work + 240 experimental work; 16 specialist capacity, 14 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Digital habitat (T124).
- **Economic cost:** 320 verified_compute_modules; 240 prototype industrial work.
- **Power:** 45 TW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Evacuate minds while consuming bandwidth and reserved compute.
- **Units unlocked:** Archive evacuation ship.
- **Buildings unlocked:** Archive port.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Neural computation and functional emulation. Assumption: A sufficiently complete emulation preserves relevant cognition and identity. Status: Conscious emulation and continuity of personal identity are unresolved.

### T138 — Planetary Memory Substrates

Build durable large-scale storage with repair and redundancy.

- **Field / plausibility:** Materials science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T090, T128, T129.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 21 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Planetary compute complex (T128).
- **Economic cost:** 340 verified_compute_modules; 255 prototype industrial work.
- **Power:** 50 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Increase archive endurance at a material and maintenance cost.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Planetary memory vault.
- **Technologies enabled:** T155, T176, T190.
- **Science:** Materials science applied to planetary memory substrates. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T139 — Ecological Co-Design

Design biological support systems alongside engineered infrastructure.

- **Field / plausibility:** Synthetic biology; Experimental. Ruleset: both.
- **Prerequisites:** T091, T117, T133.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 28 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Biological sanctuary (T133).
- **Economic cost:** 360 verified_compute_modules; 270 prototype industrial work.
- **Power:** 55 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Improve habitat efficiency without making ecosystems maintenance-free.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Ecological design institute.
- **Technologies enabled:** T172, T191.
- **Science:** Synthetic biology applied to ecological co-design. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T140 — Plural Civilization Continuity

Demonstrate resilient continuity across biological and machine institutions.

- **Field / plausibility:** Systems engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T126, T128, T132, T133, T134.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 35 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Hybrid governance forum (T134).
- **Economic cost:** 380 verified_compute_modules; 285 prototype industrial work.
- **Power:** 60 TW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock the next strategic tier without requiring mind uploading.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Continuity council.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Systems engineering applied to plural civilization continuity. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

## Era 8 — Extreme Physics and Spacetime

### T141 — Precision Gravitational Metrology

Measure spacetime curvature and gravitational signals accurately.

- **Field / plausibility:** Gravitation; Experimental. Ruleset: both.
- **Prerequisites:** T073, T094, T128.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Orbital laboratory (T073).
- **Economic cost:** 340 extreme_field_components; 255 prototype industrial work.
- **Power:** 45 PW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Improve navigation and observatory data for extreme-physics research.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Gravitational observatory.
- **Technologies enabled:** T142, T144, T146, T147, T148, T178.
- **Science:** Gravitation applied to precision gravitational metrology. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T142 — Black-Hole Population Surveys

Map natural compact objects and surrounding material.

- **Field / plausibility:** Astrophysics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T094, T141.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 16 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Gravitational observatory (T141).
- **Economic cost:** 360 extreme_field_components; 270 prototype industrial work.
- **Power:** 50 PW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Identify remnant-energy sites with explicit travel and hazard costs.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Black-hole survey array.
- **Technologies enabled:** T143, T161.
- **Science:** Astrophysics applied to black-hole population surveys. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T143 — Accretion Flow Control

Investigate controlled delivery and harvesting around compact objects.

- **Field / plausibility:** Plasma physics; Highly speculative. Ruleset: both.
- **Prerequisites:** T105, T107, T142.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 24 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Black-hole survey array (T142).
- **Economic cost:** 380 extreme_field_components; 285 prototype industrial work.
- **Power:** 55 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Convert delivered feedstock into power with large radiators.
- **Units unlocked:** Accretion service vessel.
- **Buildings unlocked:** Accretion power station.
- **Technologies enabled:** T144, T145, T158, T186.
- **Science:** Accretion energetics and rotational energy extraction. Assumption: Long-lived industrial control of feedstock, fields and waste heat near compact objects. Status: Supporting astrophysics is real; the integrated industrial capability is speculative.

### T144 — Rotational Energy Extraction

Investigate extracting energy from rotating black-hole environments.

- **Field / plausibility:** Relativity; Highly speculative. Ruleset: both.
- **Prerequisites:** T103, T141, T143.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 32 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Accretion power station (T143).
- **Economic cost:** 400 extreme_field_components; 300 prototype industrial work.
- **Power:** 60 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Spend finite rotational reserves through demanding engineered infrastructure.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Spin-extraction facility.
- **Technologies enabled:** T147, T149, T158.
- **Science:** Accretion energetics and rotational energy extraction. Assumption: Long-lived industrial control of feedstock, fields and waste heat near compact objects. Status: Supporting astrophysics is real; the integrated industrial capability is speculative.

### T145 — Extreme-Field Materials

Qualify components for intense radiation and field gradients.

- **Field / plausibility:** Materials science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T102, T130, T143.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 40 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Programmable-material works (T130).
- **Economic cost:** 420 extreme_field_components; 315 prototype industrial work.
- **Power:** 65 PW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Reduce maintenance burden near remnant-energy infrastructure.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Extreme-field test range.
- **Technologies enabled:** T148, T149, T151, T158, T160, T170, T186.
- **Science:** Materials science applied to extreme-field materials. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T146 — Relativistic Industrial Control

Coordinate equipment where light-time and relativistic effects matter.

- **Field / plausibility:** Control engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T092, T132, T141.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 8 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Verification network hub (T132).
- **Economic cost:** 340 extreme_field_components; 255 prototype industrial work.
- **Power:** 45 PW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Enable predictable local operation without instantaneous central commands.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Relativistic control hub.
- **Technologies enabled:** T152, T158, T159, T160, T167.
- **Science:** Control engineering applied to relativistic industrial control. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T147 — Gravitational-Wave Signalling

Investigate modulated gravitational signals with extreme source demands.

- **Field / plausibility:** Communications; Highly speculative. Ruleset: both.
- **Prerequisites:** T141, T144.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 16 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Gravitational observatory (T141).
- **Economic cost:** 360 extreme_field_components; 270 prototype industrial work.
- **Power:** 50 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Offer costly robust signalling that still travels at light speed.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Gravity-wave transmitter.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Gravitational radiation in general relativity. Assumption: Artificial sources and detectors can exchange useful messages economically. Status: Detection exists; practical engineered communication is speculative and not faster than light.

### T148 — Quantum Gravity Experiments

Test hypotheses at the intersection of gravity and quantum theory.

- **Field / plausibility:** Fundamental physics; Experimental. Ruleset: both.
- **Prerequisites:** T059, T129, T141, T145.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 24 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Gravitational observatory (T141).
- **Economic cost:** 380 extreme_field_components; 285 prototype industrial work.
- **Power:** 55 PW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Generate experimental evidence rather than automatically granting new physics.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Quantum-gravity laboratory.
- **Technologies enabled:** T149, T150, T155, T193.
- **Science:** Fundamental physics applied to quantum gravity experiments. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T149 — Artificial Black-Hole Experiments

Explore whether energy concentration can create controllable compact objects.

- **Field / plausibility:** High-energy physics; Highly speculative. Ruleset: both.
- **Prerequisites:** T144, T145, T148.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 32 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Quantum-gravity laboratory (T148).
- **Economic cost:** 400 extreme_field_components; 300 prototype industrial work.
- **Power:** 60 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Open an optional hazardous research programme, not guaranteed power.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Artificial-hole test chamber.
- **Technologies enabled:** T195.
- **Science:** Gravitational collapse under extreme energy concentration. Assumption: A controllable compact object can be created, retained and safely fed. Status: No demonstrated artificial black-hole creation or handling mechanism at useful engineering scale.

### T150 — Exotic-Stress Hypothesis

Study stress-energy configurations relevant to traversable metric models.

- **Field / plausibility:** Theoretical physics; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T148.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 40 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Quantum-gravity laboratory (T148).
- **Economic cost:** 420 extreme_field_components; 315 prototype industrial work.
- **Power:** 65 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Enable a clearly fictional branch only in the speculative ruleset.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Exotic-stress laboratory.
- **Technologies enabled:** T151, T156, T194.
- **Science:** Stress-energy in general relativity and quantum field effects. Assumption: Macroscopic stable negative-energy or equivalent exotic support can be engineered. Status: Known quantum effects do not establish the required controllable macroscopic material.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html).

### T151 — Stable Wormhole Throats

Postulate controllable traversable throats with stable supporting stress.

- **Field / plausibility:** Relativity; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T145, T150.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 8 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Exotic-stress laboratory (T150).
- **Economic cost:** 340 extreme_field_components; 255 prototype industrial work.
- **Power:** 45 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Prototype a gate only under declared unknown-physics assumptions.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Wormhole experiment anchor.
- **Technologies enabled:** T152, T154.
- **Science:** Traversable metric solutions in general relativity. Assumption: Stable traversable throats can be constructed and supported without destructive instabilities. Status: Existence and constructibility are unestablished; the game adds a fictional postulate.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html).

### T152 — Paired Gate Transport

Engineer paired transit endpoints under the fictional gate postulate.

- **Field / plausibility:** Spacetime engineering; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T146, T151.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 16 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Wormhole experiment anchor (T151).
- **Economic cost:** 360 extreme_field_components; 270 prototype industrial work.
- **Power:** 50 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Reduce travel time between conventionally delivered endpoints with finite capacity.
- **Units unlocked:** Gate installation tender.
- **Buildings unlocked:** Paired wormhole gateway.
- **Technologies enabled:** T153, T154, T157.
- **Science:** Traversable metric solutions in general relativity. Assumption: Stable traversable throats can be constructed and supported without destructive instabilities. Status: Existence and constructibility are unestablished; the game adds a fictional postulate.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html).

### T153 — Gate Logistics Arbitration

Schedule transit reservations across capacity-limited fictional gates.

- **Field / plausibility:** Logistics; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T095, T132, T152.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 24 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Paired wormhole gateway (T152).
- **Economic cost:** 380 extreme_field_components; 285 prototype industrial work.
- **Power:** 55 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Prevent cargo duplication and prioritize emergency transfer.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Gate logistics controller.
- **Technologies enabled:** T154, T168.
- **Science:** Traversable metric solutions in general relativity. Assumption: Stable traversable throats can be constructed and supported without destructive instabilities. Status: Existence and constructibility are unestablished; the game adds a fictional postulate.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html).

### T154 — Metric Interdiction

Postulate local disruption of a prepared transit metric.

- **Field / plausibility:** Military science; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T151, T152, T153.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 32 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Paired wormhole gateway (T152).
- **Economic cost:** 400 extreme_field_components; 300 prototype industrial work.
- **Power:** 60 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Deny a gate corridor with advance warning and heavy power cost.
- **Units unlocked:** Gate warden.
- **Buildings unlocked:** Metric interdiction anchor.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Curved spacetime and engineered metric proposals. Assumption: Useful metric configurations can be created and controlled locally. Status: No established engineering mechanism; finite game effects are explicitly fictional.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html).

### T155 — Black-Hole Computing Research

Investigate computation proposals inspired by black-hole information limits.

- **Field / plausibility:** Information physics; Highly speculative. Ruleset: both.
- **Prerequisites:** T127, T138, T148.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 40 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Quantum-gravity laboratory (T148).
- **Economic cost:** 420 extreme_field_components; 315 prototype industrial work.
- **Power:** 65 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Open optional experimental compute projects without promising recoverable outputs.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Horizon information laboratory.
- **Technologies enabled:** T156, T195.
- **Science:** Black-hole entropy and information bounds. Assumption: Information can be controllably encoded, processed and recovered usefully. Status: An information bound does not demonstrate a usable computer.

### T156 — Spacetime Substrate Computing

Postulate controllable information processing in engineered spacetime.

- **Field / plausibility:** Computer science; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T150, T155.
- **Research:** 510 theory work + 255 experimental work; 17 specialist capacity, 8 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Horizon information laboratory (T155).
- **Economic cost:** 340 extreme_field_components; 255 prototype industrial work.
- **Power:** 45 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Enable fictional specialized computation with finite power and stability budgets.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Spacetime compute substrate.
- **Technologies enabled:** T194.
- **Science:** Curved spacetime and engineered metric proposals. Assumption: Useful metric configurations can be created and controlled locally. Status: No established engineering mechanism; finite game effects are explicitly fictional.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html).

### T157 — Matter Transmission Protocols

Postulate transfer of complete state followed by destination reconstruction.

- **Field / plausibility:** Information physics; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T090, T131, T152.
- **Research:** 540 theory work + 270 experimental work; 18 specialist capacity, 16 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Paired wormhole gateway (T152).
- **Economic cost:** 360 extreme_field_components; 270 prototype industrial work.
- **Power:** 50 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Enable fictional cargo transfer that consumes destination matter and destroys source copies.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Matter transmission terminal.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Quantum information and atomically precise fabrication. Assumption: Complete relevant object state can be acquired and reconstructed under fictional transfer rules. Status: Quantum teleportation is not macroscopic matter transport; gameplay needs additional assumptions.

### T158 — Remnant-Energy Networks

Coordinate industrial use of naturally occurring compact-object environments.

- **Field / plausibility:** Energy engineering; Highly speculative. Ruleset: both.
- **Prerequisites:** T143, T144, T145, T146.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 24 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Accretion power station (T143).
- **Economic cost:** 380 extreme_field_components; 285 prototype industrial work.
- **Power:** 55 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Reach era maturity through an extreme-engineering path without gates.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Remnant network exchange.
- **Technologies enabled:** T160, T192.
- **Science:** Accretion energetics and rotational energy extraction. Assumption: Long-lived industrial control of feedstock, fields and waste heat near compact objects. Status: Supporting astrophysics is real; the integrated industrial capability is speculative.

### T159 — Causal Governance Protocols

Delegate authority explicitly across long signal delays.

- **Field / plausibility:** Political systems; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T100, T134, T146.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 32 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Hybrid governance forum (T134).
- **Economic cost:** 400 extreme_field_components; 300 prototype industrial work.
- **Power:** 60 PW requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Keep distant regions playable through local policy and timestamped reports.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Causal governance centre.
- **Technologies enabled:** T160, T162, T166, T167, T177.
- **Science:** Political systems applied to causal governance protocols. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T160 — Extreme-Physics Industrial Charter

Standardize high-energy infrastructure and autonomous stewardship.

- **Field / plausibility:** Systems engineering; Highly speculative. Ruleset: both.
- **Prerequisites:** T145, T146, T158, T159.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 40 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Remnant network exchange (T158).
- **Economic cost:** 420 extreme_field_components; 315 prototype industrial work.
- **Power:** 65 PW requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Unlock galactic organization without requiring speculative transit.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Extreme-physics industrial hub.
- **Technologies enabled:** T161.
- **Science:** Accretion energetics and rotational energy extraction. Assumption: Long-lived industrial control of feedstock, fields and waste heat near compact objects. Status: Supporting astrophysics is real; the integrated industrial capability is speculative.

## Era 9 — Galactic Civilization

### T161 — Galactic Sector Cartography

Map useful stellar regions and feasible routes at sector scale.

- **Field / plausibility:** Astronomy; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T094, T142, T160.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Black-hole survey array (T142).
- **Economic cost:** 380 sector_construction_lots; 285 prototype industrial work.
- **Power:** 50 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Generate a bounded strategic sector graph instead of billions of agents.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Sector observatory.
- **Technologies enabled:** T162, T165, T166, T168, T169, T172, T178.
- **Science:** Astronomy applied to galactic sector cartography. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T162 — Sector Industrial Contracts

Allocate inter-system work and delivery commitments under delay.

- **Field / plausibility:** Economics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T113, T159, T161.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Causal governance centre (T159).
- **Economic cost:** 400 sector_construction_lots; 300 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Plan regional production with explicit local reserves.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Sector industrial exchange.
- **Technologies enabled:** T163, T170, T173.
- **Science:** Economics applied to sector industrial contracts. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T163 — Self-Governing Fleet Foundries

Operate military shipyards under bounded regional budgets.

- **Field / plausibility:** Manufacturing; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T126, T136, T162.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 27 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Autonomous fleet foundry (T136).
- **Economic cost:** 420 sector_construction_lots; 315 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Replenish sector forces without individual factory micromanagement.
- **Units unlocked:** Sector fleet.
- **Buildings unlocked:** Sector fleet foundry.
- **Technologies enabled:** T164, T165, T174, T198.
- **Science:** Manufacturing applied to self-governing fleet foundries. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T164 — Replicator Interdiction

Detect unauthorized reproduction and deny feedstock access.

- **Field / plausibility:** Computer security; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T093, T132, T163.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 36 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Verification network hub (T132).
- **Economic cost:** 440 sector_construction_lots; 330 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Counter runaway expansion through industrial and cyber containment.
- **Units unlocked:** Replicator interdiction group.
- **Buildings unlocked:** Replication firewall station.
- **Technologies enabled:** T171, T175.
- **Science:** Computer security applied to replicator interdiction. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T165 — Relativistic Defence Webs

Layer sensing and intercept installations over strategic approach regions.

- **Field / plausibility:** Military science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T097, T115, T161, T163.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 45 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Megastructure defence hub (T115).
- **Economic cost:** 460 sector_construction_lots; 345 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Defend key routes with disclosed observation and response limits.
- **Units unlocked:** Fortress-system formation.
- **Buildings unlocked:** Relativistic defence web.
- **Technologies enabled:** T175, T179, T198.
- **Science:** Military science applied to relativistic defence webs. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T166 — Distributed Strategic Intelligence

Fuse delayed reports into regional plans with uncertainty estimates.

- **Field / plausibility:** Artificial intelligence; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T128, T132, T159, T161.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Planetary compute complex (T128).
- **Economic cost:** 380 sector_construction_lots; 285 prototype industrial work.
- **Power:** 50 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Coordinate sector responses without omniscient instant reaction.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Strategic intelligence mesh.
- **Technologies enabled:** T171, T174.
- **Science:** Artificial intelligence applied to distributed strategic intelligence. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T167 — Galactic Relay Standards

Maintain compatible light-speed communications across autonomous networks.

- **Field / plausibility:** Communications; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T094, T146, T159.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Causal governance centre (T159).
- **Economic cost:** 400 sector_construction_lots; 300 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Improve reliability and routing without removing physical delay.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Galactic relay station.
- **Technologies enabled:** T168, T173, T178, T190, T197.
- **Science:** Communications applied to galactic relay standards. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T168 — Wormhole Backbone Engineering

Extend the optional fictional gate network across sector anchors.

- **Field / plausibility:** Spacetime engineering; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T153, T161, T167.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 27 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Gate logistics controller (T153).
- **Economic cost:** 420 sector_construction_lots; 315 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Create high-throughput routes whose endpoints remain blockadable.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Sector gate nexus.
- **Technologies enabled:** T199.
- **Science:** Traversable metric solutions in general relativity. Assumption: Stable traversable throats can be constructed and supported without destructive instabilities. Status: Existence and constructibility are unestablished; the game adds a fictional postulate.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html).

### T169 — Stellar Migration Corridors

Coordinate long-term stellar movement and safe approach geometry.

- **Field / plausibility:** Astrodynamics; Highly speculative. Ruleset: both.
- **Prerequisites:** T111, T112, T161.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 36 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Mass-flow stellar engine (T112).
- **Economic cost:** 440 sector_construction_lots; 330 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Reshape future route costs through slow committed projects.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar migration control.
- **Technologies enabled:** T185, T187.
- **Science:** Stellar plasma physics and momentum conservation. Assumption: Controllable sustained stellar mass flows or coordinated stellar motion at useful scale. Status: No demonstrated stellar engineering; extrapolation is constrained by energy and momentum.

### T170 — Galactic Thermal Planning

Budget radiative heat rejection across distributed industry.

- **Field / plausibility:** Thermodynamics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T129, T145, T162.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 45 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Cold compute habitat (T129).
- **Economic cost:** 460 sector_construction_lots; 345 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Limit density and site compute near suitable heat sinks.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Deep-space radiator field.
- **Technologies enabled:** T180, T182.
- **Science:** Thermodynamics applied to galactic thermal planning. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T171 — Civilization-Scale Cyber Defence

Contain attacks across heterogeneous autonomous institutions.

- **Field / plausibility:** Computer security; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T132, T164, T166.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Verification network hub (T132).
- **Economic cost:** 380 sector_construction_lots; 285 prototype industrial work.
- **Power:** 50 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Prevent one compromised node from instantly converting a sector.
- **Units unlocked:** Cyber-defence fleet.
- **Buildings unlocked:** Sector verification citadel.
- **Technologies enabled:** T176, T179.
- **Science:** Computer security applied to civilization-scale cyber defence. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T172 — Interstellar Ecosystem Reserves

Protect distributed habitats from correlated ecological collapse.

- **Field / plausibility:** Ecology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T117, T133, T139, T161.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Biological sanctuary (T133).
- **Economic cost:** 400 sector_construction_lots; 300 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Create biological refuges that diversify civilization risk.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Ecosystem reserve network.
- **Technologies enabled:** T176, T180, T191.
- **Science:** Ecology applied to interstellar ecosystem reserves. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T173 — Galactic Resource Clearing

Reconcile material claims and delivery obligations across sectors.

- **Field / plausibility:** Economics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T118, T162, T167.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 27 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Sector industrial exchange (T162).
- **Economic cost:** 420 sector_construction_lots; 315 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Avoid double-spending strategic inventory while supporting trade.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Galactic clearing house.
- **Technologies enabled:** T179.
- **Science:** Economics applied to galactic resource clearing. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T174 — Autonomous Expedition Armadas

Assemble long-range forces with local logistics and policy authority.

- **Field / plausibility:** Military science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T092, T096, T163, T166.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 36 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Sector fleet foundry (T163).
- **Economic cost:** 440 sector_construction_lots; 330 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Commit fleets with replenishment plans and withdrawal limits.
- **Units unlocked:** Expedition armada.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** T198.
- **Science:** Military science applied to autonomous expedition armadas. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T175 — Megastructure Siege Containment

Isolate hostile industrial nodes before escalating destructive force.

- **Field / plausibility:** Military science; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T115, T116, T164, T165.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 45 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Megastructure defence hub (T115).
- **Economic cost:** 460 sector_construction_lots; 345 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Offer blockade and capture alternatives to destroying valuable infrastructure.
- **Units unlocked:** Siege containment fleet.
- **Buildings unlocked:** None; upgrade or doctrine.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Military science applied to megastructure siege containment. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T176 — Civilization Recovery Templates

Preserve validated industrial and institutional restart packages.

- **Field / plausibility:** Systems engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T093, T132, T138, T171, T172.
- **Research:** 570 theory work + 285 experimental work; 19 specialist capacity, 9 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Verification network hub (T132).
- **Economic cost:** 380 sector_construction_lots; 285 prototype industrial work.
- **Power:** 50 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Rebuild devastated regions from surviving seeds and finite supplies.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Civilization recovery vault.
- **Technologies enabled:** T180, T184, T190.
- **Science:** Systems engineering applied to civilization recovery templates. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T177 — Alien Lineage Diplomacy

Distinguish autonomous alien factions and negotiate verifiable agreements.

- **Field / plausibility:** Political systems; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T098, T099, T118, T159.
- **Research:** 600 theory work + 300 experimental work; 20 specialist capacity, 18 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar assembly (T118).
- **Economic cost:** 400 sector_construction_lots; 300 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Unlock alliances and trade without a single species-wide opinion meter.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Contact assembly.
- **Technologies enabled:** T179.
- **Science:** Political systems applied to alien lineage diplomacy. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T178 — Causal Risk Forecasting

Model long-term access to resources under expansion and travel limits.

- **Field / plausibility:** Cosmology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T141, T161, T167.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 27 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Sector observatory (T161).
- **Economic cost:** 420 sector_construction_lots; 315 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Identify threatened routes and viable refuge domains.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Causal horizon observatory.
- **Technologies enabled:** T180, T181, T185.
- **Science:** Cosmology applied to causal risk forecasting. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.
- **Science boundary references:** [nasa-cosmology](https://imagine.gsfc.nasa.gov/ask_astro/cosmology.html).

### T179 — Galactic Defence Federation

Coordinate independent sectors around enforceable mutual-defence contracts.

- **Field / plausibility:** Political systems; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T165, T171, T173, T177.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 36 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Contact assembly (T177).
- **Economic cost:** 440 sector_construction_lots; 330 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Share reserves subject to delivery time and political limits.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Galactic defence assembly.
- **Technologies enabled:** T180.
- **Science:** Political systems applied to galactic defence federation. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T180 — Galactic Continuity Standard

Demonstrate a resilient civilization spanning multiple autonomous sectors.

- **Field / plausibility:** Systems engineering; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T170, T172, T176, T178, T179.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 45 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Galactic defence assembly (T179).
- **Economic cost:** 460 sector_construction_lots; 345 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Enter cosmic planning after sustained continuity metrics are met.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Galactic continuity centre.
- **Technologies enabled:** T181.
- **Science:** Systems engineering applied to galactic continuity standard. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

## Era 10 — Cosmic Civilization

### T181 — Cosmological Horizon Mapping

Track which regions can remain causally connected under the scenario cosmology.

- **Field / plausibility:** Cosmology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T178, T180.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Causal horizon observatory (T178).
- **Economic cost:** 420 deep_time_infrastructure_lots; 315 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Define reachable endgame objectives instead of promising the entire visible universe.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Cosmological horizon array.
- **Technologies enabled:** T182, T184, T185, T193, T195, T197.
- **Science:** Cosmology applied to cosmological horizon mapping. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.
- **Science boundary references:** [nasa-cosmology](https://imagine.gsfc.nasa.gov/ask_astro/cosmology.html).

### T182 — Deep-Time Energy Accounting

Budget free energy and unavoidable losses over survival horizons.

- **Field / plausibility:** Thermodynamics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T127, T170, T181.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Deep-space radiator field (T170).
- **Economic cost:** 440 deep_time_infrastructure_lots; 330 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Optimize useful work and reserves rather than raw gross power.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Deep-time energy bureau.
- **Technologies enabled:** T183, T186, T189, T200.
- **Science:** Thermodynamics applied to deep-time energy accounting. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T183 — Stellar Lifetime Management

Investigate changing stellar evolution through controlled material handling.

- **Field / plausibility:** Astrophysics; Highly speculative. Ruleset: both.
- **Prerequisites:** T105, T106, T117, T182.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 30 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar dynamics observatory (T105).
- **Economic cost:** 460 deep_time_infrastructure_lots; 345 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Extend selected resource horizons with costly uncertain engineering.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Stellar lifetime works.
- **Technologies enabled:** T187, T188.
- **Science:** Stellar evolution and composition dependence. Assumption: Controlled extraction or mixing can alter evolution without destroying useful habitats. Status: Intervention at this scale is speculative; stellar lifetimes are not arbitrary sliders.

### T184 — Intergalactic Ark Engineering

Design extremely durable independent intergalactic expeditions.

- **Field / plausibility:** Astronautics; Highly speculative. Ruleset: both.
- **Prerequisites:** T067, T085, T088, T176, T181.
- **Research:** 720 theory work + 360 experimental work; 24 specialist capacity, 40 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** O'Neill habitat (T067).
- **Economic cost:** 480 deep_time_infrastructure_lots; 360 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Launch rare arks with immense lead times and finite reachable destinations.
- **Units unlocked:** Intergalactic ark.
- **Buildings unlocked:** Intergalactic ark port.
- **Technologies enabled:** T192.
- **Science:** Relativistic travel and closed ecological or machine systems. Assumption: Independent systems remain viable over intergalactic travel and repair times. Status: No physical faster-than-light assumption, but sustained engineering performance is speculative.

### T185 — Gravitationally Bound Refuges

Concentrate survivable assets within suitable long-lived bound regions.

- **Field / plausibility:** Astrodynamics; Highly speculative. Ruleset: both.
- **Prerequisites:** T169, T178, T181.
- **Research:** 750 theory work + 375 experimental work; 25 specialist capacity, 50 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar migration control (T169).
- **Economic cost:** 500 deep_time_infrastructure_lots; 375 prototype industrial work.
- **Power:** 75 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Build a causal survival network without faster-than-light assumptions.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Refuge cluster anchor.
- **Technologies enabled:** T187, T191, T198, T200.
- **Science:** Stellar plasma physics and momentum conservation. Assumption: Controllable sustained stellar mass flows or coordinated stellar motion at useful scale. Status: No demonstrated stellar engineering; extrapolation is constrained by energy and momentum.

### T186 — Supermassive Accretion Stewardship

Control feedstock and harvesting around supermassive compact objects.

- **Field / plausibility:** Astrophysics; Highly speculative. Ruleset: both.
- **Prerequisites:** T143, T145, T182.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 10 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Accretion power station (T143).
- **Economic cost:** 420 deep_time_infrastructure_lots; 315 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Supply large regional projects with mass and heat constraints.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Supermassive accretion works.
- **Technologies enabled:** T192.
- **Science:** Accretion energetics and rotational energy extraction. Assumption: Long-lived industrial control of feedstock, fields and waste heat near compact objects. Status: Supporting astrophysics is real; the integrated industrial capability is speculative.

### T187 — Galactic Structure Engineering

Coordinate stellar relocation over extremely long intervals.

- **Field / plausibility:** Astrodynamics; Highly speculative. Ruleset: both.
- **Prerequisites:** T169, T183, T185.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 20 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar migration control (T169).
- **Economic cost:** 440 deep_time_infrastructure_lots; 330 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Shape local refuge geometry while preserving committed migration costs.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Galactic engineering directorate.
- **Technologies enabled:** T188, T199.
- **Science:** Stellar plasma physics and momentum conservation. Assumption: Controllable sustained stellar mass flows or coordinated stellar motion at useful scale. Status: No demonstrated stellar engineering; extrapolation is constrained by energy and momentum.

### T188 — Star-Formation Management

Investigate influencing gas conditions in selected star-forming regions.

- **Field / plausibility:** Astrophysics; Highly speculative. Ruleset: both.
- **Prerequisites:** T105, T183, T187.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 30 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Stellar dynamics observatory (T105).
- **Economic cost:** 460 deep_time_infrastructure_lots; 345 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Manage delayed stellar asset creation without instant stars.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Star-formation research complex.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Gravitational collapse of interstellar gas. Assumption: Gas conditions can be changed and controlled across star-formation scales. Status: Star formation is observed; targeted industrial control is speculative.

### T189 — Entropy-Efficient Civilization

Coordinate computation and industry for low dissipation and endurance.

- **Field / plausibility:** Information physics; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T127, T129, T182.
- **Research:** 720 theory work + 360 experimental work; 24 specialist capacity, 40 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Cold compute habitat (T129).
- **Economic cost:** 480 deep_time_infrastructure_lots; 360 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Trade operating speed for longer reserve lifetime.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Entropy management institute.
- **Technologies enabled:** T190, T200.
- **Science:** Information physics applied to entropy-efficient civilization. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.
- **Science boundary references:** [bennett-landauer](https://arxiv.org/abs/physics/0210005).

### T190 — Cosmic Archive Redundancy

Maintain repairable archives across independent causal domains.

- **Field / plausibility:** Information theory; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T138, T167, T176, T189.
- **Research:** 750 theory work + 375 experimental work; 25 specialist capacity, 50 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Planetary memory vault (T138).
- **Economic cost:** 500 deep_time_infrastructure_lots; 375 prototype industrial work.
- **Power:** 75 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Preserve civilization records with delayed reconciliation and finite upkeep.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Cosmic archive vault.
- **Technologies enabled:** T197, T200.
- **Science:** Information theory applied to cosmic archive redundancy. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T191 — Long-Horizon Ecological Continuity

Maintain adaptable biological ecosystems over deep-time changes.

- **Field / plausibility:** Ecology; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T133, T139, T172, T185.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 10 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Biological sanctuary (T133).
- **Economic cost:** 420 deep_time_infrastructure_lots; 315 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Keep biological populations a viable final-era path.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Deep-time biological sanctuary.
- **Technologies enabled:** T200.
- **Science:** Ecology applied to long-horizon ecological continuity. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T192 — Remnant Migration Infrastructure

Move industrial support among accessible remnant-energy sites.

- **Field / plausibility:** Logistics; Highly speculative. Ruleset: both.
- **Prerequisites:** T158, T184, T186.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 20 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Remnant network exchange (T158).
- **Economic cost:** 440 deep_time_infrastructure_lots; 330 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Relocate civilization supply networks at high material and travel cost.
- **Units unlocked:** Remnant migration fleet.
- **Buildings unlocked:** Remnant migration port.
- **Technologies enabled:** T198.
- **Science:** Accretion energetics and rotational energy extraction. Assumption: Long-lived industrial control of feedstock, fields and waste heat near compact objects. Status: Supporting astrophysics is real; the integrated industrial capability is speculative.

### T193 — Vacuum-State Measurement

Investigate vacuum structure without assuming extractable free energy.

- **Field / plausibility:** Quantum field theory; Experimental. Ruleset: both.
- **Prerequisites:** T148, T181.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 30 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Quantum-gravity laboratory (T148).
- **Economic cost:** 460 deep_time_infrastructure_lots; 345 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Generate data for optional endgame hypotheses, not unlimited power.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Vacuum-state observatory.
- **Technologies enabled:** T194, T195.
- **Science:** Quantum field theory applied to vacuum-state measurement. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: Experiments or components exist; required integrated performance is not established.

### T194 — Controlled Vacuum Engineering

Postulate controllable bounded changes to vacuum state.

- **Field / plausibility:** Quantum field theory; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T150, T156, T193.
- **Research:** 720 theory work + 360 experimental work; 24 specialist capacity, 40 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Vacuum-state observatory (T193).
- **Economic cost:** 480 deep_time_infrastructure_lots; 360 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Unlock a fictional high-risk megaproject with finite scenario effects.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Vacuum engineering chamber.
- **Technologies enabled:** T196, T199.
- **Science:** Quantum field vacuum states. Assumption: Vacuum configurations can be changed safely and controllably with useful bounded effects. Status: No established controllable energy source or safe engineering mechanism.

### T195 — Artificial-Universe Hypothesis

Investigate speculative cosmogenesis models and their limitations.

- **Field / plausibility:** Cosmology; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T149, T155, T181, T193.
- **Research:** 750 theory work + 375 experimental work; 25 specialist capacity, 50 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Horizon information laboratory (T155).
- **Economic cost:** 500 deep_time_infrastructure_lots; 375 prototype industrial work.
- **Power:** 75 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Open an optional terminal research path, not a resource source.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Cosmogenesis laboratory.
- **Technologies enabled:** T196.
- **Science:** Speculative inflationary cosmogenesis models. Assumption: A daughter universe can be created, accessed and made compatible with survival. Status: No experimental evidence or established engineering mechanism; explicitly fictional ending.

### T196 — Cosmogenesis Project

Postulate a controlled accessible daughter-universe construction.

- **Field / plausibility:** Cosmology; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T194, T195.
- **Research:** 630 theory work + 315 experimental work; 21 specialist capacity, 10 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Cosmogenesis laboratory (T195).
- **Economic cost:** 420 deep_time_infrastructure_lots; 315 prototype industrial work.
- **Power:** 55 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Offer an explicitly fictional alternate ending after massive investment.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Cosmogenesis chamber.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Speculative inflationary cosmogenesis models. Assumption: A daughter universe can be created, accessed and made compatible with survival. Status: No experimental evidence or established engineering mechanism; explicitly fictional ending.

### T197 — Cosmic Information Network

Connect reachable archives with durable light-speed relays.

- **Field / plausibility:** Communications; Theoretically plausible. Ruleset: both.
- **Prerequisites:** T167, T181, T190.
- **Research:** 660 theory work + 330 experimental work; 22 specialist capacity, 20 compute service; at most 2 parallel experiments. No unique sample required.
- **Infrastructure:** Galactic relay station (T167).
- **Economic cost:** 440 deep_time_infrastructure_lots; 330 prototype industrial work.
- **Power:** 60 stellar_power_unit requested; minimum 50% delivered to operate.
- **Gameplay effect / prototype test:** Coordinate a finite causal domain while showing report age.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Cosmic relay spine.
- **Technologies enabled:** T199, T200.
- **Science:** Communications applied to cosmic information network. Assumption: Reliable integration and sufficient engineering scale; dates and costs are fictional balance choices.. Status: No new physical law is assumed; practical large-scale feasibility remains unproved.

### T198 — Causal-Domain Guardians

Defend migration routes and irreplaceable refuge infrastructure.

- **Field / plausibility:** Military science; Highly speculative. Ruleset: both.
- **Prerequisites:** T163, T165, T174, T185, T192.
- **Research:** 690 theory work + 345 experimental work; 23 specialist capacity, 30 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Sector fleet foundry (T163).
- **Economic cost:** 460 deep_time_infrastructure_lots; 345 prototype industrial work.
- **Power:** 65 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Field survival-focused formations with strict energy reserves.
- **Units unlocked:** Refuge guardian fleet.
- **Buildings unlocked:** Causal-domain bastion.
- **Technologies enabled:** T200.
- **Science:** Accretion energetics and rotational energy extraction. Assumption: Long-lived industrial control of feedstock, fields and waste heat near compact objects. Status: Supporting astrophysics is real; the integrated industrial capability is speculative.

### T199 — Observable-Domain Intervention

Postulate gate reach beyond ordinary causal-access limitations.

- **Field / plausibility:** Spacetime engineering; Unknown physics required. Ruleset: speculative_frontier.
- **Prerequisites:** T168, T187, T194, T197.
- **Research:** 720 theory work + 360 experimental work; 24 specialist capacity, 40 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Sector gate nexus (T168).
- **Economic cost:** 480 deep_time_infrastructure_lots; 360 prototype industrial work.
- **Power:** 70 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Offer a fictional universal-control scenario; never claim current physics permits it.
- **Units unlocked:** Metric containment fleet.
- **Buildings unlocked:** Cosmic intervention lattice.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Causal structure and cosmological expansion. Assumption: Engineered links can reach regions beyond ordinary causal accessibility. Status: The proposed universal reach is not supported by established physics.
- **Science boundary references:** [nasa-wormholes](https://science.gsfc.nasa.gov/attic/cosmicopia.gsfc.nasa.gov/qa_sp_sl.html), [nasa-cosmology](https://imagine.gsfc.nasa.gov/ask_astro/cosmology.html).

### T200 — Continuity Beyond Empire

Demonstrate durable survival of diverse autonomous populations.

- **Field / plausibility:** Systems engineering; Highly speculative. Ruleset: both.
- **Prerequisites:** T182, T185, T189, T190, T191, T197, T198.
- **Research:** 750 theory work + 375 experimental work; 25 specialist capacity, 50 compute service; at most 1 parallel experiments. No unique sample required.
- **Infrastructure:** Cosmic archive vault (T190).
- **Economic cost:** 500 deep_time_infrastructure_lots; 375 prototype industrial work.
- **Power:** 75 stellar_power_unit requested; minimum 80% delivered to operate.
- **Gameplay effect / prototype test:** Complete the causal campaign without vacuum engineering or artificial universes.
- **Units unlocked:** None; systemic capability.
- **Buildings unlocked:** Continuity monument.
- **Technologies enabled:** Terminal capability / campaign objective.
- **Science:** Thermodynamics, ecology and reliable information storage. Assumption: Complex societies and infrastructure can be repaired across enormous future intervals. Status: Long-duration civilization survival is unproved even when no new law is assumed.

