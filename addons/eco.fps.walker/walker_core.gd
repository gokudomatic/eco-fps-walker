extends RigidBody

export(float) var body_radius=0.8
export(float) var body_height=1
export(float) var leg_length=0.3

const UP=Vector3(0,1,0)
export(NodePath) var target setget set_target
export(NodePath) var navigation setget set_navigation
var current_target_ref=null
var navmesh=null

const ANGULAR_SPEED=4
const TARGET_ERROR_DELTA=1.5
const WAYPOINT_ERROR_DELTA=2
const WAYPOINT_MAX_TIMEOUT=5

var going_backward=false
onready var target_ray=get_node("target_ray")
onready var leg_ray=get_node("leg_ray")
var current_direction=Vector3()
var current_waypoint=null
var current_path=null
var no_move=false
var waypoint_timeout=0
var is_temp_waypoint=false
var is_temp_side_right=false
var was_UTurn=false

const action_states=["sleep","move","turn","wait"]
var fsm_action
var current_action={
	move=false,
	follow_target=false
}

# ground sensors -----------------------
onready var ground_sensor_l=get_node("ray_ground_left")
onready var ground_sensor_r=get_node("ray_ground_right")
var old_sensor_status_l=false
var old_sensor_status_r=false

var aim_offset=Vector3(0,1.8,0)

# original -----------
const walk_speed = 3;
const max_accel = 0.02;
const air_accel = 0.05;

# signals -----------------------------------
signal walk_speed_changed(speed)
signal action_changed(name)

func _ready():
	_init_collision_body()
	
	leg_ray.add_exception_rid(get_rid())
	target_ray.add_exception_rid(get_rid())
	_init_fsm()
	set_target(target)
	set_navigation(navigation)

func _init_collision_body():
	var b_shape=get_node("body").get_shape()
	b_shape.set_radius(body_radius)
	b_shape.set_height(body_height)
	get_node("leg").get_shape().set_radius(leg_length)
#	get_node("leg").get_shape().set_extents(Vector3(0.01,leg_length,0.01))
	get_node("leg").set_translation(Vector3(0,leg_length,0))
	
	get_node("body").set_translation(Vector3(0,0.5*body_height+body_radius+leg_length,0))

func _init_fsm():
	fsm_action=preload("fsm.gd").new()
	fsm_action.add_group("main",{follow=false})
	fsm_action.add_state("decide",null,"main")
	fsm_action.add_state("wait",{move=false},"main")
	fsm_action.add_state("turn",{move=false},"main")
	fsm_action.add_state("move",{move=true},"main")
	fsm_action.add_state("sleep",{move=false,follow=false})
	
	fsm_action.add_link("wait","decide","timeout",[0.2])
	fsm_action.add_link("move","decide","timeout",[2])
	fsm_action.add_link("turn","decide","timeout",[1])
	fsm_action.add_link("sleep","decide","timeout",[5])
	
	fsm_action.add_link("main","sleep","condition",[self,"fsm_is_near_target",true])
	fsm_action.add_link("decide","wait","condition",[self,"fsm_has_no_target",true])
	fsm_action.add_link("decide","move","condition",[self,"fsm_has_no_target",false])
	
	fsm_action.set_state("decide")
	
	fsm_action.connect("state_changed",self,"_action_state_changed")

func _integrate_forces(state):
	if get_target():
		var target_transform=target_ray.get_global_transform().looking_at(get_target().get_global_transform().origin+get_target_offset(get_target()),UP).orthonormalized()
		target_ray.set_global_transform(target_transform)
	else:
		target_ray.set_rotation(Vector3(0,0,0))
	
	fsm_action.process(state.get_step())
	
	if current_waypoint!=null:
		if get_translation().distance_to(current_waypoint)<WAYPOINT_ERROR_DELTA or waypoint_timeout<=0:
			calculate_destination()
		else:
			waypoint_timeout-=state.get_step()
	
	do_current_action(state)

func do_current_action(state):
	
#	if OS.get_ticks_msec()>3200:
#		print("left:",ground_sensor_l.is_enabled(),"    is colliding:",ground_sensor_l.is_colliding(),"/",check_ground_sensor(ground_sensor_l))
#		print("ground:",leg_ray.is_colliding(),"   left:",check_ground_sensor(ground_sensor_l),"    right:",check_ground_sensor(ground_sensor_r))

	
	var current_t=get_global_transform()
	var current_z=current_t.basis.z
	
	var aim = current_t.basis;
	var direction = Vector3();
	
	# moving
	if current_action.move and not no_move:
		#move forward
		direction -= current_z;
	
	direction = direction.normalized();
	
	# ground collision detection
	if leg_ray.is_colliding():
		# is walking on the ground
		# calculate the impulse vector for horizontal movement. Vertical velocity is kept but not amplified
		var diff = Vector3() + direction * walk_speed - state.get_linear_velocity();
		var vertdiff = aim[1] * diff.dot(aim[1]); # vertical velocity
		diff -= vertdiff; # we remove vertical velocity temporarely for working only with horizontal velocity
		diff = diff.normalized() * clamp(diff.length(), 0, max_accel / state.get_step());
		diff += vertdiff; # vertical velocity is put back
		if not no_move :
			apply_impulse(Vector3(), diff * get_mass())
	else:
		# is falling
		apply_impulse(Vector3(), Vector3() * air_accel * get_mass());
#		apply_impulse(Vector3(), direction * air_accel * get_mass());
	
	# set rotation

	if leg_ray.is_colliding():
		var target_z
		if current_action.follow_target:
			# when attacking, the npc always face the target
			target_z=target_ray.get_global_transform().basis.z
		else:
			if current_waypoint!=null:
				var offset=Vector3(0,0,0)
				if get_target():
					offset=get_target_offset(get_target())
				var tt=current_t.looking_at(current_waypoint+offset,Vector3(0,1,0))
				target_z=tt.basis.z
			else:
				target_z=current_direction
		
		var vx=Vector2(current_z.x,current_z.z).angle_to(Vector2(target_z.x,target_z.z))
		
		if not current_action.follow_target:
			var gs_left=check_ground_sensor(ground_sensor_l)
			var gs_right=check_ground_sensor(ground_sensor_r)
			var is_new_hole_l=gs_left and !old_sensor_status_l
			var is_new_hole_r=gs_right and !old_sensor_status_r
			
			if is_new_hole_l:
				print("new left:",is_new_hole_l)
			
			if gs_left and gs_right and not (is_new_hole_l and is_new_hole_r) and (is_new_hole_r or is_new_hole_l):
				is_new_hole_r=true
				is_new_hole_l=true
			
			old_sensor_status_r=gs_right
			old_sensor_status_l=gs_left
			
			var new_vx=vx
			if is_new_hole_l and is_new_hole_r:
				new_vx=PI
				calculate_destination()
				fsm_action.set_state("turn")
				state.set_linear_velocity(Vector3(0,0,0))
			elif is_new_hole_l or is_new_hole_r:
				if is_new_hole_l:
					new_vx=0+PI/6
				else:
					new_vx=-PI/6
			
			if new_vx!=vx:
				is_temp_waypoint=true
				is_temp_side_right=is_new_hole_r
				vx=new_vx
				var dir=current_z.rotated(UP,new_vx).normalized()*4
				current_waypoint=get_global_transform().origin-dir
		 
		# if not aiming at target, turn at constant speed
		if not (abs(vx)<0.3):
			vx=sign(vx)
		
		state.set_angular_velocity(Vector3(0,vx*ANGULAR_SPEED,0))
	
	state.integrate_forces();
	
	var vel_speed=state.get_linear_velocity().length()/walk_speed;
	var speed=state.get_angular_velocity().length()*0.1+vel_speed;
	emit_signal("walk_speed_changed",speed)


func calculate_destination(force_recalculate=false):
	# reset ground sensors
	if not (old_sensor_status_r and old_sensor_status_l):
		old_sensor_status_r=false
		old_sensor_status_l=false
	
	var offset=Vector3(0,0,0)
	if get_target():
		offset=get_target_offset(get_target())
	
	if get_target() and navmesh!=null:
		var did_reach_wpt=current_waypoint!=null and (current_waypoint-get_translation()).length()<WAYPOINT_ERROR_DELTA
		if force_recalculate or current_waypoint==null or did_reach_wpt or waypoint_timeout<=0:
			_update_waypoint(did_reach_wpt)
	else:
		var curr_pos
		if get_target():
			curr_pos=get_target().get_global_transform().origin
		else:
			 curr_pos=get_waypoint_no_target()
		
		if navmesh!=null:
			current_waypoint=navmesh.get_closest_point(curr_pos)
		else:
			current_waypoint=curr_pos
		waypoint_timeout=WAYPOINT_MAX_TIMEOUT
	
	var old_direction=current_direction
	current_direction=get_global_transform().looking_at(current_waypoint+offset,Vector3(0,1,0)).orthonormalized().basis.z
	if (current_direction+old_direction).length()<1.2:
		fsm_action.set_state("turn")

func get_waypoint_no_target():
	return get_global_transform().origin

func _update_waypoint(reached_wpt):
	var current_t=get_global_transform()
	var cur_dir=current_t.basis.z
	
	#convert start and end points to local
	var navt=navmesh.get_global_transform()
	var local_begin=navt.xform_inv(current_t.origin)
	var local_end=navt.xform_inv(get_target().get_global_transform().origin)
	
	#calculate path
	var begin=navmesh.get_closest_point(local_begin)
	var end=navmesh.get_closest_point(local_end)
	var p=navmesh.get_simple_path(begin,end, true)
	
	#process path
	var path=Array(p)
	
	var was_temp_waypoint=is_temp_waypoint
	is_temp_waypoint=false
	
	if current_path==null or current_path.size()<3 or was_temp_waypoint:
		current_path=path
		if current_path.size()==0:
			current_waypoint=navt.xform(end)
		else:
			current_waypoint=navt.xform(path[1])
			
		if not was_UTurn and was_temp_waypoint and cur_dir.dot(current_t.looking_at(current_waypoint,UP).basis.z)<-0.4:
			was_UTurn=true
			var factor=1
			if is_temp_side_right:
				factor=-1
			current_waypoint=current_t.origin+cur_dir.rotated(UP,factor*PI*0.5)*4
			is_temp_waypoint=true
		else:
			was_UTurn=false
	else:
		#remove begin and end
		path.pop_back()
		path.pop_front()
		path.invert()
		var found=false
		while not path.empty() and not found:
			var wpt=path[0]
			path.pop_front()
			for wpt_ref in current_path:
				if wpt_ref.distance_to(wpt)==0:
					found=true
					break
		
		if found:
			if reached_wpt:
				current_path.pop_front()
			current_waypoint=navt.xform(current_path[1])
		else:
			current_path=Array(p)
			if(current_path.size()>=2):
				current_waypoint=navt.xform(current_path[1])
		
		# check if doing U-Turn
		
		var wpt_dir=current_t.looking_at(current_waypoint,UP).basis.z
		var a=cur_dir.dot(wpt_dir)
		
		if not was_UTurn and cur_dir.dot(wpt_dir)<-0.4:
			was_UTurn=true
			
			current_waypoint=current_t.origin-cur_dir.rotated(UP,PI/16*-sign(current_t.basis.x.dot(wpt_dir)))*6
		else:
			was_UTurn=false
	
	
	waypoint_timeout=WAYPOINT_MAX_TIMEOUT
	# reset ground sensors
	old_sensor_status_r=false
	old_sensor_status_l=false

func check_ground_sensor(sensor):
	if sensor.is_colliding():
		var dot=abs(UP.dot(sensor.get_collision_normal()))
		var len=sensor.get_global_transform().origin.distance_to(sensor.get_collision_point())
		return dot < 0.4 or (dot==1 and len>4)
	else:
		return true

func _action_state_changed(state_from,state_to,params):
	
	if state_to=="move":
		calculate_destination()
	
	if action_states.has(state_to):
		current_action.move=params.move
		current_action.follow_target=params.follow
	
	emit_signal("action_changed",state_to)

func get_target_offset(target):
	return Vector3(0,0,0)

func fsm_has_no_target():
	return !get_target()

func fsm_is_near_target():
	if !get_target():
		return false
	else:
		return get_target().get_global_transform().origin.distance_to(get_global_transform().origin)<TARGET_ERROR_DELTA

func set_target(t):
	target=t
	if target==null:
		current_target_ref=null
	else:
		if typeof(t)==TYPE_STRING or typeof(t)==TYPE_NODE_PATH:
			current_target_ref=weakref(get_node(t))
		else:
			current_target_ref=weakref(t)

func get_target():
	var result
	if current_target_ref==null:
		result=false
	else:
		result=current_target_ref.get_ref()
	
	if !result and current_waypoint!=null:
		current_waypoint=null
	return result

func set_navigation(n):
	navigation=n
	if navigation==null:
		navmesh=null
	else:
		navmesh=get_node(n)
