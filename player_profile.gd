extends Resource
class_name PlayerProfile

## ===========================================================================
## 🎮 PLAYER PROFILE - Data-driven player configuration
## ===========================================================================

@export_group("Vitality")
## Maximum health points. Determines how many hits the player can take.
@export_range(1, 10000) var max_health: int = 1000
## Movement speed in m/s. Higher = faster movement.
@export_range(0.1, 10.0) var move_speed: float = 5.0
## Jump strength. Higher = higher jumps.
@export_range(0.1, 10.0) var jump_strength: float = 5.0

@export_group("Combat")
## Damage dealt per single attack hit.
@export_range(1, 100) var attack_damage: int = 20
## Delay between consecutive attacks. Higher = slower attack rate.
@export_range(0.1, 5.0) var attack_cooldown: float = 0.3
## Time in seconds it takes for defend to activate.
@export_range(0.1, 2.0) var defend_activation_delay: float = 0.15

@export_group("Mouse Controls")
## Mouse sensitivity for camera rotation.
@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.1
