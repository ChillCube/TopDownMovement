@icon("res://addons/TopDownMovement/icon_move.png")
extends Node
class_name TopDownMovement

signal moving(direction_and_speed : Vector2)
signal stopped_moving

signal started_dashing(direction_and_speed : Vector2)
signal used_a_dash(dashes_left : int, dashes_used : int, max_dashes : int)
signal stopped_dashing

signal knocked_back(direction : Vector2, strength : float)
signal knokockback_stopped

signal moving_up
signal moving_down
signal moving_left
signal moving_right

@export var speed : float = 500 ## Maximum movement speed in pixels/sec
@export_range(0, 1) var acceleration : float = 1 ## Ramp-up rate (1 = instant, 0 = never accelerates)
@export_range(0, 1) var deceleration : float = 0.1 ## Ramp-down rate (1 = instant stop)

@export_group("Dash")
@export var enable_dashing : bool = true ## Allow the dash mechanic
@export var dash_speed : float = 5 ## Speed multiplier during a dash
@export var dash_time : float = 0.5 ## Duration in seconds of each dash
@export_range(0, 1) var dash_falloff : float = 0.3 ## How quickly dash velocity decays after the timer ends
@export var dash_timeout : float = 0.5 ## Cooldown in seconds between dashes
@export var dashes : int = 1 ## Number of dashes available before the timeout resets the counter

@export_group("Knockback")
@export var enable_knockback : bool = true ## Allow knockback to be applied via request_knockback()
@export var knockback_speed : float = 5 ## Speed multiplier for knockback impulse
@export var knockback_time : float = 0.5 ## Duration in seconds the knockback force is applied
@export_range(0, 1) var knockback_falloff : float = 0.3 ## How quickly knockback velocity decays after the timer ends

@export_group("Multiplayer")
@export_range(1.0, 30.0, 0.5) var remote_lerp_speed : float = 15.0 ## Lerp speed used to smooth remote player positions on non-authority clients

# Internal movement vars
var dashes_used : int = 0
var dash_vector : Vector2 = Vector2.ZERO
var knockback_vector : Vector2 = Vector2.ZERO
var speed_vector : Vector2 = Vector2.ZERO
var is_dashing : bool = false
var is_knocked_back : bool = false
var dash_timer_start : float = 0.0
var knockback_timer_start : float = 0.0

# Timers
@onready var dash_timer : SceneTreeTimer = get_tree().create_timer(0)
@onready var dash_timeout_timer : SceneTreeTimer = get_tree().create_timer(0)
@onready var knockback_timer : SceneTreeTimer = get_tree().create_timer(0)

# Public API for movement input (can be called by anyone, but may be rejected)
var _requested_movement_direction : Vector2 = Vector2.ZERO
var _requested_dash_direction : Vector2 = Vector2.ZERO
var _has_dash_request : bool = false

# Parent reference
var parent : CharacterBody2D

# Multiplayer
var _is_network_authority : bool = true
var _net_position : Vector2 = Vector2.ZERO
var _is_in_multiplayer : bool = false

func _ready():
	parent = get_parent() as CharacterBody2D
	if not parent:
		push_error("TopDownMovement must be child of a CharacterBody2D")
		return
	
	_setup_multiplayer()

func _setup_multiplayer():
	_is_in_multiplayer = multiplayer.has_multiplayer_peer()
	_net_position = parent.position
	
	if _is_in_multiplayer:
		# Check if this instance has authority
		if parent.has_method("is_multiplayer_authority"):
			_is_network_authority = parent.is_multiplayer_authority()
		else:
			# Node name should be the peer ID for players
			if parent.name.is_valid_int():
				parent.set_multiplayer_authority(int(parent.name))
			_is_network_authority = (multiplayer.get_unique_id() == parent.get_multiplayer_authority())
		
		# Disable physics on remote instances
		if not _is_network_authority:
			set_physics_process(false)
	else:
		_is_network_authority = true

func _process(delta: float):
	# Remote interpolation - only for non-authority instances
	if _is_in_multiplayer and not _is_network_authority:
		parent.position = parent.position.lerp(_net_position, delta * remote_lerp_speed)

func _physics_process(delta: float):
	# Only the authority processes movement
	if _is_in_multiplayer and not _is_network_authority:
		return

	# Process dash request if any
	if _has_dash_request and enable_dashing:
		_try_dash_internal(_requested_dash_direction)
		_has_dash_request = false
		_requested_dash_direction = Vector2.ZERO
	
	# Process movement
	var max_speed = speed
	var input_vector = _requested_movement_direction if _requested_movement_direction != Vector2.ZERO else Vector2.ZERO
	
	# Process dash state
	_process_dash(delta)
	
	# Movement calculation
	var max_speed_vector = input_vector * max_speed 
	var deceleration_vector = (Vector2.ZERO - speed_vector) * deceleration
	var acceleration_vector : Vector2
	
	if input_vector.length() > 0:
		acceleration_vector = ((max_speed_vector - speed_vector) * acceleration) + (input_vector * deceleration_vector.length())
	else:
		acceleration_vector = Vector2.ZERO
		if speed_vector.length() < max_speed * 0.1:
			emit_signal("stopped_moving")
	
	speed_vector += acceleration_vector + deceleration_vector
	
	var final_velocity = speed_vector + dash_vector + knockback_vector
	
	parent.velocity = final_velocity
	parent.move_and_slide()
	
	if final_velocity.length() > 0:
		emit_signal("moving", final_velocity)
		_emit_direction_signals(final_velocity)
	
	_process_knockback(delta)
	
	# Broadcast position to remote instances
	if _is_in_multiplayer and _is_network_authority:
		_update_remote_position.rpc(parent.position)

# Public API - These can be called from anywhere (PlayerInput, AI, StateMachine)
func request_movement(direction: Vector2): ## Public API: submit a movement direction; routes to authority via RPC in multiplayer
	if not _is_network_authority:
		# Send to authority if we're not it
		if _is_in_multiplayer:
			rpc_id(parent.get_multiplayer_authority(), "_remote_request_movement", direction)
		return
	
	# Authority processes movement directly
	_requested_movement_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO

func request_dash(direction: Vector2): ## Public API: trigger a dash in the given direction; routes to authority via RPC in multiplayer
	if not enable_dashing:
		return
	
	if not _is_network_authority:
		# Send to authority if we're not it
		if _is_in_multiplayer:
			rpc_id(parent.get_multiplayer_authority(), "_remote_request_dash", direction)
		return
	
	# Authority processes dash directly
	_requested_dash_direction = direction
	_has_dash_request = true

func request_knockback(direction: Vector2, strength: float): ## Public API: apply a knockback impulse; routes to authority via RPC in multiplayer
	if not enable_knockback:
		return
	
	if not _is_network_authority:
		# Send to authority if we're not it
		if _is_in_multiplayer:
			rpc_id(parent.get_multiplayer_authority(), "_remote_request_knockback", direction, strength)
		return
	
	# Authority processes knockback directly
	_try_knockback_internal(direction, strength)

# Internal processing methods (authority only)
func _try_dash_internal(direction: Vector2):
	if dash_timeout_timer.time_left < 0.1:
		dashes_used = 0
	
	if dashes_used < dashes:
		emit_signal("started_dashing", direction)
		emit_signal("used_a_dash", dashes - dashes_used, dashes_used, dashes)
		
		dash_vector = direction.normalized() * dash_speed * 200
		is_dashing = true
		dash_timer_start = Time.get_ticks_msec() / 1000.0
		dash_timer = get_tree().create_timer(dash_time)
		dash_timeout_timer = get_tree().create_timer(dash_timeout)
		dashes_used += 1
		
		# Sync dash state to remote instances
		if _is_in_multiplayer:
			_sync_dash_state.rpc(dash_vector, true, dashes_used, dash_timer_start)

func _try_knockback_internal(direction: Vector2, strength: float):
	emit_signal("knocked_back", direction, strength)
	knockback_vector = direction.normalized() * knockback_speed * 200 * strength
	is_knocked_back = true
	knockback_timer_start = Time.get_ticks_msec() / 1000.0
	knockback_timer = get_tree().create_timer(knockback_time)
	
	if _is_in_multiplayer:
		_sync_knockback_state.rpc(knockback_vector, true)

# Remote RPC calls (for non-authority instances to send requests)
@rpc("any_peer", "reliable", "call_local")
func _remote_request_movement(direction: Vector2):
	if not _is_network_authority:
		return
	if _is_in_multiplayer and multiplayer.get_remote_sender_id() != parent.get_multiplayer_authority():
		return
	request_movement(direction)

@rpc("any_peer", "reliable", "call_local")
func _remote_request_dash(direction: Vector2):
	if not _is_network_authority:
		return
	if _is_in_multiplayer and multiplayer.get_remote_sender_id() != parent.get_multiplayer_authority():
		return
	request_dash(direction)

@rpc("any_peer", "reliable", "call_local")
func _remote_request_knockback(direction: Vector2, strength: float):
	if not _is_network_authority:
		return
	if _is_in_multiplayer and multiplayer.get_remote_sender_id() != parent.get_multiplayer_authority():
		return
	request_knockback(direction, strength)

# Sync functions (authority broadcasts to remotes)
@rpc("authority", "reliable", "call_local")
func _sync_dash_state(d_vec: Vector2, is_dashing_state: bool, d_used: int, start_time: float):
	if _is_network_authority:
		return
	dash_vector = d_vec
	is_dashing = is_dashing_state
	dashes_used = d_used
	dash_timer_start = start_time

@rpc("authority", "reliable", "call_local")
func _sync_knockback_state(kb_vector: Vector2, is_kb: bool):
	if _is_network_authority:
		return
	knockback_vector = kb_vector
	is_knocked_back = is_kb
	if is_kb:
		knockback_timer_start = Time.get_ticks_msec() / 1000.0

@rpc("authority", "reliable")
func _update_remote_position(new_position: Vector2):
	if _is_network_authority:
		return
	_net_position = new_position

func _emit_direction_signals(velocity: Vector2):
	if velocity.length() == 0:
		return
	
	var angle = velocity.angle()
	
	if angle >= -PI/4 and angle < PI/4:
		emit_signal("moving_right")
	elif angle >= PI/4 and angle < 3 * PI/4:
		emit_signal("moving_down")
	elif angle >= 3 * PI/4 or angle < -3 * PI/4:
		emit_signal("moving_left")
	else:
		emit_signal("moving_up")

func _process_dash(delta: float):
	if not is_dashing:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - dash_timer_start >= dash_time:
		is_dashing = false
		dash_vector += (Vector2.ZERO - dash_vector) * dash_falloff
		if dash_vector.length() < 1:
			emit_signal("stopped_dashing")
			if _is_in_multiplayer and _is_network_authority:
				_sync_stop_dashing.rpc()

func _process_knockback(delta: float):
	if not is_knocked_back:
		return
	
	if knockback_timer.time_left < 0.01:
		knockback_vector += (Vector2.ZERO - knockback_vector) * knockback_falloff
		if knockback_vector.length() < 0.1:
			is_knocked_back = false
			emit_signal("knockback_stopped")
			if _is_in_multiplayer and _is_network_authority:
				_sync_knockback_state.rpc(Vector2.ZERO, false)

@rpc("authority", "reliable", "call_local")
func _sync_stop_dashing():
	if _is_network_authority:
		return
	is_dashing = false
	emit_signal("stopped_dashing")
