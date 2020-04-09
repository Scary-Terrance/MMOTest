extends KinematicBody2D

# Constants
const ACCELERATION = 500
const MAX_SPEED = 80
const FRICTION = 500
const NETFPS = 0.05

# State Machine
enum {
	PASSIVE,
	ATTACK
}

# Class Variables
var _client = WebSocketClient.new()
var velocity = Vector2.ZERO
var netTime = NETFPS
var state = PASSIVE
var netState = PASSIVE
var lastPacket = {}

# Onready Variables
onready var amimationPlayer = $AnimationPlayer
onready var animationTree = $AnimationTree
onready var animationState = animationTree.get("parameters/playback")

# Exports
# "ws://echo.websocket.org"
export var websocket_url = "ws://127.0.0.1:9001" 
	
# Runs once on entity initialization
func _ready():
	# Connect base signals to get notified of connection open, close, and errors.
	_client.connect("connection_closed", self, "_closed")
	_client.connect("connection_error", self, "_closed")
	_client.connect("connection_established", self, "_connected")
	# This signal is emitted when not using the Multiplayer API every time
	# a full packet is received.
	# Alternatively, you could check get_peer(1).get_available_packets() in a loop.
	_client.connect("data_received", self, "_on_data")

	# Initiate connection to the given URL.
	var err = _client.connect_to_url(websocket_url)
	if err != OK:
		print("Unable to connect")
		set_physics_process(false)

# Runs if the connection closes
func _closed(was_clean = false):
	# was_clean will tell you if the disconnection was correctly notified
	# by the remote peer before closing the socket.
	print("Closed, clean: ", was_clean)
	set_physics_process(false)

# Runs once when connected
func _connected(_proto = ""):
	# You MUST always use get_peer(1).put_packet to send data to server,
	# and not put_packet directly when not using the MultiplayerAPI.
	_send_packet(Vector2(0.0, 0.0))

func _on_data():
	# Print the received packet, you MUST always use get_peer(1).get_packet
	# to receive data from server, and not get_packet directly when not
	# using the MultiplayerAPI.
	print("Got data from server: ", _client.get_peer(1).get_packet().get_string_from_utf8())

func _update_last_packet(input_vector):
	lastPacket["i"] = input_vector
	lastPacket["v"] = velocity
	lastPacket["p"] = self.position
	lastPacket["s"] = netState

func _prep_packet(input_vector):
	var packet = ""
	if lastPacket.empty():
		_update_last_packet(input_vector)
		packet += "i%.2f %.2f " % [input_vector.x, input_vector.y]
		packet += "v%.2f %.2f " % [velocity.x, velocity.y]
		packet += "p%.2f %.2f " % [self.position.x, self.position.y]
		packet += "s%d " % [netState]
	if lastPacket["i"] != input_vector:
		packet += "i%.2f %.2f " % [input_vector.x, input_vector.y]
	if lastPacket["v"] != velocity:
		packet += "v%.2f %.2f " % [velocity.x, velocity.y]
	if lastPacket["p"] != self.position:
		packet += "p%.2f %.2f " % [self.position.x, self.position.y]
	if lastPacket["s"] != netState:
		packet += "s%d " % [netState]
	_update_last_packet(input_vector)
	if netState != PASSIVE:
		netState = PASSIVE
	packet = packet.trim_suffix(" ")
	return packet
	
func _send_packet(input_vector):
	# Structure the packet
	var packet = _prep_packet(input_vector)
	# Put the packet in the queu to send
	if packet != "":
		_client.get_peer(1).put_packet(packet.to_utf8())

func _poll_net(delta, input_vector):
#	if !_client.get_peer(1).is_connected_to_host():
#		print("Error: Connection to Server Closed")
#		set_physics_process(false)
	netTime -= delta
	if netTime <= 0:
		netTime = NETFPS
		# Build a packet to send to the server
		_send_packet(input_vector)
	
	# Send / Read packets with the server
	_client.poll()
	
func _get_input_vector():
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	# Normalize the vector to prevent doubled speed at 45 degrees
	return input_vector.normalized()
	
func _move(delta, input_vector):
	if input_vector != Vector2.ZERO:
		# Set the animation blend position to input vector so animations play in right direction
		animationTree.set("parameters/idle/blend_position", input_vector)
		animationTree.set("parameters/run/blend_position", input_vector)
		if animationState.get_current_node() != "attack":
			animationTree.set("parameters/attack/blend_position", input_vector)
		# Since moving Run
		animationState.travel("run")
		# Calculate velocity for motion
		velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCELERATION * delta)
	else:
		# Standing still so idle and apply friction
		animationState.travel("idle")
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	
func passive_state():
	if Input.is_action_just_pressed("ui_attack"):
		state = ATTACK
		netState = state
	
func attack_state():
	animationState.travel("attack")
	state = PASSIVE
	
func _handle_state():
	match state:
		ATTACK:
			attack_state()
		PASSIVE:
			passive_state()
			
# Runs every physics tick
func _physics_process(delta):	
	# Calculate input_vector from user inputs
	var input_vector = _get_input_vector()
	# Calculate current state for State Machine and Animation Tree
	_move(delta, input_vector)
	_handle_state()
	# Calculate current position
	velocity = move_and_slide(velocity)
	# Poll the server
	_poll_net(delta, input_vector)

# Called when entity despawned
func _exit_tree():
	_client.disconnect_from_host()
