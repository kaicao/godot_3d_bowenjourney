extends Resource
class_name EnemyProfile

## ===========================================================================
## 📖 ENEMY PROFILE DOCUMENTATION GUIDE
## ===========================================================================
## This resource defines the "Identity" of an enemy. 
## To add new metadata:
## 1. Define a new @export variable below in the appropriate group.
## 2. Use ## comments to describe the variable's impact on gameplay.
## 3. Update the EnemyAI script to utilize this new variable.
## ===========================================================================

@export_group("Vitality")
## Maximum health points. Determines how many hits the enemy can take.
@export_range(1, 10000) var max_health: int = 100
## Movement speed in m/s. Higher = faster chase/patrol.
@export_range(0.1, 10.0) var move_speed: float = 2.2
## Damage dealt per single attack hit.
@export_range(1, 100) var attack_damage: int = 10

@export_group("Perception")
## Distance in units the enemy can detect the player.
@export_range(1.0, 50.0) var vision_range: float = 10.0
## Field of view in degrees. 360 = all around, 90 = narrow cone.
@export_range(1.0, 360.0) var vision_fov: float = 105.0
## Time in seconds it takes for the enemy to react to a spotted player.
@export_range(0.01, 2.0) var reaction_time: float = 0.5

@export_group("Combat Logic")
## Delay between consecutive attacks. Higher = slower attack rate.
@export_range(0.1, 5.0) var attack_delay: float = 0.5
## Probability (0.0 to 1.0) that the enemy will attempt a dodge.
@export_range(0.0, 1.0) var dodge_chance: float = 0.15
## Time in seconds between dodge attempts. Lower = can dodge more frequently.
@export_range(0.5, 5.0) var dodge_cooldown_time: float = 2.0
## Probability (0.0 to 1.0) that the enemy will defend instead of dodge.
@export_range(0.0, 1.0) var defend_chance: float = 0.10
## Minimum time (seconds) the enemy must stay in the ATTACK state.
@export_range(0.1, 5.0) var min_attack_duration: float = 1.5
## Minimum time (seconds) the enemy must stay in the CHASE state.
@export_range(0.1, 5.0) var min_chase_duration: float = 0.5
## Cooldown between state transitions to prevent "jittery" AI behavior.
@export_range(0.0, 1.0) var state_change_cooldown: float = 0.3

@export_group("🏃 Escape Behavior")
## ⭐ Can this enemy type escape? (false for bosses, berserkers)
@export var can_escape: bool = true
## ⭐ Health % threshold to trigger escape (e.g., 30.0 = 30%)
@export_range(0.0, 100.0) var escape_health_threshold: float = 30.0
## ⭐ Minimum distance (meters) to run when escaping
@export_range(5.0, 50.0) var escape_distance_min: float = 10.0
## ⭐ Maximum distance (meters) to run when escaping
@export_range(5.0, 50.0) var escape_distance_max: float = 20.0
## ⭐ Speed multiplier when escaping (1.3 = 30% faster)
@export_range(1.0, 3.0) var escape_speed_multiplier: float = 1.3

@export_group("AI Personality")
## Intelligence level (0-100). Affects reaction speed and awareness.
@export_range(0, 100) var iq_level: int = 50
## HP threshold (0.0-1.0) at which enemy tries to escape.
@export_range(0.0, 1.0) var escape_threshold: float = 0.3

## ---------------------------------------------------------------------------
## 🎬 ANIMATION CONFIGURATION BY STATE
## Organized by FSM states for clarity and extensibility
## ---------------------------------------------------------------------------

@export_group("🎬 Model & Paths")
@export var model_path: String = "Skeleton_Warrior"
@export var animation_player_path: String = "AnimationPlayer"

@export_group("⚔️ ATTACK State Animations")
@export var attack_animations: String = "1H_Melee_Attack_Chop,1H_Melee_Attack_Stab,1H_Melee_Attack_Slice_Diagonal"

@export_group("🔄 DODGE State Animations")
@export var dodge_animations: String = "Dodge_Backward,Dodge_Forward,Dodge_Left,Dodge_Right"

@export_group("💀 DEATH Event (Non-State)")
@export var death_animations: String = "Death_A,Death_B,Death_C_Skeletons"

@export_group("🎯 Other State Animations")
@export var idle_animations: String = "Idle,Idle_Combat"
@export var movement_animations: String = "Running_A,Running_B"
@export var hit_animations: String = "Hit_A,Hit_B"
@export var escape_animations: String = "Running_B"
