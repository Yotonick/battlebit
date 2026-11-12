class_name Weapons
## Weapon table shared by the player and the bots (team deathmatch).
## Damage is per bullet/pellet at close range; it falls off linearly to
## `falloff_min` of itself between `near` and `far` meters. `power`/`radius`
## are what a hit does to voxels (see VoxMat.PROPS strengths).

enum { RIFLE, SHOTGUN, SNIPER, RPG, GRENADE }

const COUNT := 5

const DEFS := [
	{
		"name": "Штурмовая винтовка", "short": "M4A1", "kind": "hitscan", "mode": "АВТО",
		"damage": 22.0, "head": 2.0, "near": 25.0, "far": 80.0, "falloff_min": 0.62,
		"rpm": 720.0, "auto": true, "mag": 30, "reserve": 150, "reload": 2.1, "equip": 0.45,
		"pellets": 1, "spread": 0.016, "ads_spread": 0.0035, "recoil": 0.010, "range": 260.0,
		"power": 1.7, "radius": 0.09, "noise": 75.0, "sound": "rifle", "volume": 0.0, "ads_fov": 52.0,
	},
	{
		"name": "Дробовик", "short": "M870", "kind": "hitscan", "mode": "ПОМПА",
		"damage": 14.0, "head": 1.5, "near": 7.0, "far": 30.0, "falloff_min": 0.2,
		"rpm": 72.0, "auto": false, "mag": 7, "reserve": 35, "reload": 2.6, "equip": 0.5,
		"pellets": 9, "spread": 0.045, "ads_spread": 0.032, "recoil": 0.045, "range": 70.0,
		"power": 2.4, "radius": 0.14, "noise": 85.0, "sound": "shotgun", "volume": 2.0, "ads_fov": 62.0,
	},
	{
		"name": "Снайперская винтовка", "short": "M40A5", "kind": "hitscan", "mode": "ОДИН.",
		"damage": 92.0, "head": 2.4, "near": 80.0, "far": 250.0, "falloff_min": 0.8,
		"rpm": 44.0, "auto": false, "mag": 5, "reserve": 30, "reload": 3.0, "equip": 0.6,
		"pellets": 1, "spread": 0.045, "ads_spread": 0.0008, "recoil": 0.05, "range": 450.0,
		"power": 3.4, "radius": 0.16, "noise": 120.0, "sound": "sniper", "volume": 4.0, "ads_fov": 20.0,
		"scope": true,
	},
	{
		"name": "Гранатомёт", "short": "SMAW", "kind": "rocket", "mode": "РАКЕТА",
		"rpm": 40.0, "auto": false, "mag": 1, "reserve": 4, "reload": 2.8, "equip": 0.6,
		"spread": 0.012, "ads_spread": 0.004, "recoil": 0.06, "speed": 55.0,
		"blast_radius": 2.3, "blast_power": 7.0, "noise": 130.0, "ads_fov": 55.0,
	},
	{
		"name": "Ручная граната", "short": "M67", "kind": "grenade", "mode": "БРОСОК",
		"rpm": 60.0, "auto": false, "mag": 1, "reserve": 2, "reload": 0.9, "equip": 0.35,
		"spread": 0.0, "ads_spread": 0.0, "recoil": 0.0, "speed": 17.0, "fuse": 2.4,
		"blast_radius": 1.8, "blast_power": 5.6, "noise": 120.0, "ads_fov": 70.0,
	},
]


static func def(w: int) -> Dictionary:
	return DEFS[w]


static func damage_at_range(w: int, dist: float) -> float:
	var d: Dictionary = DEFS[w]
	var k := clampf((dist - d.near) / maxf(d.far - d.near, 0.01), 0.0, 1.0)
	return d.damage * lerpf(1.0, d.falloff_min, k)


static func interval(w: int) -> float:
	return 60.0 / DEFS[w].rpm


## Ammo, reload and switch timers of one soldier.
class Arsenal:
	extends RefCounted
	var mags: Array[int] = []
	var reserves: Array[int] = []
	var current := RIFLE
	var cooldown := 0.0
	var reload_t := 0.0
	var equip_t := 0.0
	## Shots fired in the current burst (recoil and bot spread build up).
	var burst := 0
	var _since_shot := 9.0

	func _init() -> void:
		refill_all()

	func refill_all() -> void:
		mags.clear()
		reserves.clear()
		for d: Dictionary in DEFS:
			mags.append(d.mag)
			reserves.append(d.reserve)
		cooldown = 0.0
		reload_t = 0.0
		equip_t = 0.0

	## Ammo bag: one magazine for every weapon.
	func resupply() -> void:
		for i in COUNT:
			var d: Dictionary = DEFS[i]
			reserves[i] = mini(reserves[i] + d.mag, d.reserve)

	func cur() -> Dictionary:
		return DEFS[current]

	func select(w: int) -> bool:
		if w == current or not has_ammo(w):
			return false
		current = w
		equip_t = DEFS[w].equip
		reload_t = 0.0
		burst = 0
		return true

	func has_ammo(w: int) -> bool:
		return mags[w] + reserves[w] > 0

	func ready() -> bool:
		return equip_t <= 0.0 and reload_t <= 0.0 and cooldown <= 0.0 and mags[current] > 0

	func busy() -> bool:
		return equip_t > 0.0 or reload_t > 0.0

	func consume() -> void:
		mags[current] -= 1
		cooldown = Weapons.interval(current)
		burst += 1
		_since_shot = 0.0

	func start_reload() -> bool:
		var d := cur()
		if reload_t > 0.0 or equip_t > 0.0 or reserves[current] <= 0 or mags[current] >= d.mag:
			return false
		reload_t = d.reload
		return true

	func reloading() -> bool:
		return reload_t > 0.0

	func reload_progress() -> float:
		return 1.0 - reload_t / cur().reload if reload_t > 0.0 else 1.0

	func tick(delta: float) -> void:
		cooldown = maxf(cooldown - delta, 0.0)
		equip_t = maxf(equip_t - delta, 0.0)
		_since_shot += delta
		if _since_shot > 0.25:
			burst = 0
		if reload_t > 0.0:
			reload_t -= delta
			if reload_t <= 0.0:
				reload_t = 0.0
				var need: int = cur().mag - mags[current]
				var take := mini(need, reserves[current])
				mags[current] += take
				reserves[current] -= take
