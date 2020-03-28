extends KinematicBody2D

# Constants
const ACCELERATION = 500
const MAX_SPEED = 80
const FRICTION = 500
const NETFPS = 0.1

# Onready Variables
onready var amimationPlayer = $AnimationPlayer
onready var animationTree = $AnimationTree
onready var animationState = animationTree.get("parameters/playback")

# Exports
# "ws://echo.websocket.org"
export var websocket_url = "ws://127.0.0.1:9001" 

# Class Variables
var _client = WebSocketClient.new()
var velocity = Vector2.ZERO
var netTime = NETFPS

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

func _closed(was_clean = false):
	# was_clean will tell you if the disconnection was correctly notified
	# by the remote peer before closing the socket.
	print("Closed, clean: ", was_clean)
	set_process(false)

func _connected(proto = ""):
	# This is called on connection, "proto" will be the selected WebSocket
	# sub-protocol (which is optional)
	print("Connected with protocol: ", proto)
	# You MUST always use get_peer(1).put_packet to send data to server,
	# and not put_packet directly when not using the MultiplayerAPI.
	_client.get_peer(1).put_packet("Hello Server!".to_utf8())

func _on_data():
	# Print the received packet, you MUST always use get_peer(1).get_packet
	# to receive data from server, and not get_packet directly when not
	# using the MultiplayerAPI.
	print("Got data from server: ", _client.get_peer(1).get_packet().get_string_from_utf8())

func _send_packet(input_vector):
	# Structure the packet
	var packet = "i%s v%s" % [input_vector, velocity]
	# Put the packet in the queu to send
	_client.get_peer(1).put_packet(packet.to_utf8())
	
# Runs every physics tick
func _physics_process(delta):	
	# Calculate input_vector from user inputs
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	# Normalize the vector to prevent doubled speed at 45 degrees
	input_vector = input_vector.normalized()
	
	if input_vector != Vector2.ZERO:
		# Set the animation blend position to input vector so animations play in right direction
		animationTree.set("parameters/Idle/blend_position", input_vector)
		animationTree.set("parameters/Run/blend_position", input_vector)
		# Since moving Run
		animationState.travel("Run")
		# Calculate velocity for motion
		velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCELERATION * delta)
	else:
		# Standing still so idle and apply friction
		animationState.travel("Idle")
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	
	velocity = move_and_slide(velocity)
	netTime -= delta
	if netTime <= 0:
		netTime = NETFPS
		# Build a packet to send to the server
		_send_packet(input_vector)
	
	# Send / Read packets with the server
	_client.poll()
