extends "walker_core.gd"

const TARGET_DISTANCE=2
const SHOOT_RECHARGE_TIME=1
const MAX_LIFE=100

var hit_invincibility=false
var aiming_at_target=false
var can_see_target=false
var current_direction=Vector3()
var distance_to_collision=0

var current_action={
	move=false,
	follow_target=false,
	attack=false
}
const action_states=["sleep","move","turn","wait","attack"]

func _init_fsm():
	fsm_action=preload("fsm.gd").new()
	fsm_action.add_group("main",{move=false,attack=false,follow=false})
	
	fsm_action.add_state("decide",null,"main")
	fsm_action.add_state("wait",{},"main")
	fsm_action.add_state("turn",{},"main")
	fsm_action.add_state("move",{move=true},"main")
	fsm_action.add_state("attack",{follow=true,attack=true},"main")
	fsm_action.add_state("sleep",{move=false,follow=false,attack=false})
	
	fsm_action.add_state_link("wait","decide","timeout",[0.2])
	fsm_action.add_state_link("move","decide","timeout",[2])
	fsm_action.add_state_link("turn","decide","timeout",[1])
	fsm_action.add_state_link("sleep","decide","timeout",[5])
	fsm_action.add_state_link("attack","decide","timeout",[10])
	
	fsm_action.add_group_link("main","sleep","condition",[self,"fsm_is_near_target",true])
	fsm_action.add_state_link("decide","attack","condition",[self,"fsm_can_attack",true])
	fsm_action.add_state_link("decide","wait","condition",[self,"fsm_has_no_target",true])
	fsm_action.add_state_link("decide","move","condition",[self,"fsm_has_no_target",false])
	
	fsm_action.set_state("decide")
	
	fsm_action.connect("state_changed",self,"_action_state_changed")

func _integrate_forces(state):
	if not alive:
		return
	
	if target_ray.is_colliding() and current_target!=null and target_ray.get_collider()==current_target:
			distance_to_collision=(target_ray.get_collision_point()-target_ray.get_global_transform().origin).length()
		
			if current_action.name!="attack" and distance_to_collision<=TARGET_DISTANCE:
				create_attack_target_action()
	else:
		distance_to_collision=-1
	
	var yaw_t=get_global_transform()
	if current_target!=null:
		# target ray
		if target_ray.is_colliding() and target_ray.get_collider()==current_target:
			# target in sight
			can_see_target=true
		else:
			can_see_target=false
		
		var target_transform=target_ray.get_global_transform().looking_at(current_target.get_global_transform().origin+current_target.aim_offset,Vector3(0,1,0)).orthonormalized()
		target_ray.set_global_transform(target_transform)
		if not current_target.alive:
			current_target=player
	else:
		can_see_target=false
		var target_transform=yaw_t.looking_at(player.get_global_transform().origin+player.aim_offset,Vector3(0,1,0)).orthonormalized()
		target_ray.set_rotation(Vector3(0,0,0))
		var v=target_transform.basis.z-yaw_t.basis.z
		if v.length()<0.53:
			current_target=player
	
	
	do_current_action(state)

func sfm_can_attack():
	return current_target!=null and can_see_target and get_global_transform().origin.distance_to(current_target.get_global_transform().origin)<TARGET_DISTANCE

func _action_state_changed(state_from,state_to,params):
	if state_to=="move":
		calculate_destination()
	
	if action_states.has(state_to):
		current_action.move=params.move
		current_action.follow_target=params.follow
		current_action.attack=params.attack
	
	if state_to=="attack":
		attack()

func die():
	set_mode(MODE_STATIC) # set ragdoll mode
	set_use_custom_integrator(false)
	set_layer_mask(1024)
	alive=false
	model.die()
	.die()

func attack():
	pass

func end_attack():
	calculate_destination(true)

func _get_hurt():
	model.hit()