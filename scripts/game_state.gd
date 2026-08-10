extends Node
## Global run state shared by HUD, player, and enemies.

signal health_changed(value: int)
signal ammo_changed(mag: int, reserve: int)
signal score_changed(value: int)
signal player_died
signal enemy_killed(remaining: int)
signal level_cleared

var health: int = 100
var max_health: int = 100
var mag: int = 30
var reserve_ammo: int = 90
var mag_size: int = 30
var score: int = 0
var enemies_alive: int = 0
var player_dead: bool = false
var game_started: bool = false

func reset(reset_enemy_count: bool = true) -> void:
	health = max_health
	mag = mag_size
	reserve_ammo = 90
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
	score += amount
	score_changed.emit(score)

func register_enemy() -> void:
	enemies_alive += 1

func unregister_enemy() -> void:
	enemies_alive = maxi(0, enemies_alive - 1)
	enemy_killed.emit(enemies_alive)
	if enemies_alive == 0 and game_started:
		level_cleared.emit()
