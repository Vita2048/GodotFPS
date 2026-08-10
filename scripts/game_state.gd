extends Node
## Global run state shared by HUD, player, and enemies.

signal health_changed(value: int)
signal ammo_changed(mag: int, reserve: int)
signal score_changed(value: int)
signal player_died
signal enemy_killed(remaining: int)
signal level_cleared
signal difficulty_changed(level: int)

enum Difficulty { EASY, NORMAL, HARD }

var difficulty: Difficulty = Difficulty.EASY

var health: int = 100
var max_health: int = 100
var mag: int = 30
var reserve_ammo: int = 90
var mag_size: int = 30
var score: int = 0
var enemies_alive: int = 0
var player_dead: bool = false
var game_started: bool = false

## Tunables per difficulty (read by level gen + enemies + reset)
func enemy_count_cap() -> int:
	match difficulty:
		Difficulty.EASY:
			return 2
		Difficulty.NORMAL:
			return 4
		_:
			return 7


func enemy_damage() -> int:
	match difficulty:
		Difficulty.EASY:
			return 4
		Difficulty.NORMAL:
			return 8
		_:
			return 14


func enemy_max_hp() -> int:
	match difficulty:
		Difficulty.EASY:
			return 45
		Difficulty.NORMAL:
			return 70
		_:
			return 100


func enemy_attack_cooldown() -> float:
	match difficulty:
		Difficulty.EASY:
			return 2.0
		Difficulty.NORMAL:
			return 1.2
		_:
			return 0.75


func enemy_sight_range() -> float:
	match difficulty:
		Difficulty.EASY:
			return 12.0
		Difficulty.NORMAL:
			return 18.0
		_:
			return 26.0


func enemy_attack_range() -> float:
	match difficulty:
		Difficulty.EASY:
			return 8.0
		Difficulty.NORMAL:
			return 11.0
		_:
			return 14.0


func enemy_speed_scale() -> float:
	match difficulty:
		Difficulty.EASY:
			return 0.75
		Difficulty.NORMAL:
			return 1.0
		_:
			return 1.2


func player_max_health() -> int:
	match difficulty:
		Difficulty.EASY:
			return 150
		Difficulty.NORMAL:
			return 100
		_:
			return 80


func player_start_reserve() -> int:
	match difficulty:
		Difficulty.EASY:
			return 120
		Difficulty.NORMAL:
			return 90
		_:
			return 60


func min_spawn_distance_cells() -> float:
	## How far (in map cells) enemies must stay from player spawn
	match difficulty:
		Difficulty.EASY:
			return 5.5
		Difficulty.NORMAL:
			return 3.5
		_:
			return 2.5


func near_spawn_band() -> Vector2:
	## Prefer enemies in this distance band (cells) from player
	match difficulty:
		Difficulty.EASY:
			return Vector2(5.0, 10.0) # farther first contact
		Difficulty.NORMAL:
			return Vector2(3.0, 7.0)
		_:
			return Vector2(2.0, 6.0)


func difficulty_label() -> String:
	match difficulty:
		Difficulty.EASY:
			return "EASY"
		Difficulty.NORMAL:
			return "NORMAL"
		_:
			return "HARD"


func set_difficulty(level: Difficulty) -> void:
	difficulty = level
	difficulty_changed.emit(int(difficulty))
	# Refresh player pool stats if not mid-run death state
	if not game_started or player_dead:
		max_health = player_max_health()
		health = max_health
		reserve_ammo = player_start_reserve()
		health_changed.emit(health)
		ammo_changed.emit(mag, reserve_ammo)


func cycle_difficulty() -> void:
	set_difficulty(((int(difficulty) + 1) % 3) as Difficulty)


func reset(reset_enemy_count: bool = true) -> void:
	max_health = player_max_health()
	health = max_health
	mag = mag_size
	reserve_ammo = player_start_reserve()
	score = 0
	if reset_enemy_count:
		enemies_alive = 0
	player_dead = false
	game_started = false
	health_changed.emit(health)
	ammo_changed.emit(mag, reserve_ammo)
	score_changed.emit(score)


func apply_damage(amount: int) -> void:
	if player_dead:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health)
	if health <= 0:
		player_dead = true
		player_died.emit()


func heal(amount: int) -> void:
	if player_dead:
		return
	health = mini(max_health, health + amount)
	health_changed.emit(health)


func add_ammo(amount: int) -> void:
	reserve_ammo += amount
	ammo_changed.emit(mag, reserve_ammo)


func try_consume_shot() -> bool:
	if mag <= 0:
		return false
	mag -= 1
	ammo_changed.emit(mag, reserve_ammo)
	return true


func try_reload() -> bool:
	if mag >= mag_size or reserve_ammo <= 0:
		return false
	var need := mag_size - mag
	var take := mini(need, reserve_ammo)
	mag += take
	reserve_ammo -= take
	ammo_changed.emit(mag, reserve_ammo)
	return true


func add_score(amount: int) -> void:
	# Slight score bonus on higher difficulty
	var mult := 1.0
	match difficulty:
		Difficulty.EASY:
			mult = 0.75
		Difficulty.NORMAL:
			mult = 1.0
		Difficulty.HARD:
			mult = 1.5
	score += int(round(amount * mult))
	score_changed.emit(score)


func register_enemy() -> void:
	enemies_alive += 1


func unregister_enemy() -> void:
	enemies_alive = maxi(0, enemies_alive - 1)
	enemy_killed.emit(enemies_alive)
	if enemies_alive == 0 and game_started:
		level_cleared.emit()
