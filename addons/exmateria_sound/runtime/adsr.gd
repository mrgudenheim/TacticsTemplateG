class_name ADSR
## PSX SPU ADSR envelope generator.
## State machine: Attack -> Decay -> Sustain -> Release -> Stopped
## Called once per output sample (44100 Hz), returns envelope volume 0-1023.

enum State { ATTACK, DECAY, SUSTAIN, RELEASE, STOPPED }

# Pre-computed envelope tables (from PCSX-Redux adsr.cc)
static var _denominator: PackedInt32Array
static var _num_inc: PackedInt32Array
static var _num_dec: PackedInt32Array
static var _tables_built := false

static func _build_tables() -> void:
	if _tables_built:
		return
	_denominator.resize(128)
	_num_inc.resize(128)
	_num_dec.resize(128)
	for rate in range(128):
		_denominator[rate] = 1 if rate < 48 else (1 << ((rate >> 2) - 11))
		if rate < 48:
			var shift: int = 11 - (rate >> 2)
			_num_inc[rate] = (7 - (rate & 3)) << shift
			# GDScript can't << negative numbers; compute manually
			_num_dec[rate] = (-8 + (rate & 3)) * (1 << shift)
		else:
			_num_inc[rate] = 7 - (rate & 3)
			_num_dec[rate] = -8 + (rate & 3)
	_tables_built = true


var state: State = State.STOPPED
var envelope_vol: int = 0        # 0-32767 (15-bit internal)
var envelope_vol_f: int = 0      # Fractional counter

var attack_rate: int = 0         # 0-127
var attack_mode_exp: int = 0     # 0=linear, 1=exponential
var decay_rate: int = 0          # 0-15
var sustain_level: int = 0       # 0-15
var sustain_rate: int = 0        # 0-127
var sustain_mode_exp: int = 0
var sustain_increase: int = 0    # 0=decrease, 1=increase
var release_rate: int = 0        # 0-31
var release_mode_exp: int = 0


func _init() -> void:
	ADSR._build_tables()


func start() -> void:
	state = State.ATTACK
	envelope_vol = 0
	envelope_vol_f = 0


func key_off() -> void:
	if state != State.STOPPED:
		state = State.RELEASE


func set_from_regs(adsr1: int, adsr2: int) -> void:
	sustain_level = adsr1 & 0xF
	decay_rate = (adsr1 >> 4) & 0xF
	attack_rate = (adsr1 >> 8) & 0x7F
	attack_mode_exp = (adsr1 >> 15) & 1
	release_rate = adsr2 & 0x1F
	release_mode_exp = (adsr2 >> 5) & 1
	sustain_rate = (adsr2 >> 6) & 0x7F
	sustain_mode_exp = (adsr2 >> 15) & 1
	sustain_increase = 1 - ((adsr2 >> 14) & 1)


func mix() -> int:
	## Process one sample. Returns volume 0-1023.
	match state:
		State.ATTACK:
			return _attack()
		State.DECAY:
			return _decay()
		State.SUSTAIN:
			return _sustain()
		State.RELEASE:
			return _release()
	return 0


func _attack() -> int:
	var rate := attack_rate
	if attack_mode_exp and envelope_vol >= 0x6000:
		rate += 8
	rate = mini(rate, 127)

	envelope_vol_f += 1
	if envelope_vol_f >= _denominator[rate]:
		envelope_vol_f = 0
		envelope_vol += _num_inc[rate]

	if envelope_vol >= 32767:
		envelope_vol = 32767
		state = State.DECAY

	return envelope_vol >> 5


func _decay() -> int:
	var rate := mini(decay_rate * 4, 127)

	envelope_vol_f += 1
	if envelope_vol_f >= _denominator[rate]:
		envelope_vol_f = 0
		if release_mode_exp:
			envelope_vol += (_num_dec[rate] * envelope_vol) / 32768
		else:
			envelope_vol += _num_dec[rate]

	if envelope_vol < 0:
		envelope_vol = 0

	if ((envelope_vol >> 11) & 0xF) <= sustain_level:
		state = State.SUSTAIN

	return envelope_vol >> 5


func _sustain() -> int:
	var rate := sustain_rate

	if sustain_increase:
		if sustain_mode_exp and envelope_vol >= 0x6000:
			rate += 8
		rate = mini(rate, 127)
		envelope_vol_f += 1
		if envelope_vol_f >= _denominator[rate]:
			envelope_vol_f = 0
			envelope_vol += _num_inc[rate]
		if envelope_vol > 32767:
			envelope_vol = 32767
	else:
		rate = mini(rate, 127)
		envelope_vol_f += 1
		if envelope_vol_f >= _denominator[rate]:
			envelope_vol_f = 0
			if sustain_mode_exp:
				envelope_vol += (_num_dec[rate] * envelope_vol) / 32768
			else:
				envelope_vol += _num_dec[rate]
		if envelope_vol < 0:
			envelope_vol = 0

	return envelope_vol >> 5


func _release() -> int:
	var rate := mini(release_rate * 4, 127)

	envelope_vol_f += 1
	if envelope_vol_f >= _denominator[rate]:
		envelope_vol_f = 0
		if release_mode_exp:
			# Product is negative; use arithmetic right shift
			var product: int = _num_dec[rate] * envelope_vol
			envelope_vol += floori(float(product) / 32768.0)
		else:
			envelope_vol += _num_dec[rate]

	if envelope_vol < 0:
		state = State.STOPPED
		envelope_vol = 0
		return 0

	return envelope_vol >> 5
