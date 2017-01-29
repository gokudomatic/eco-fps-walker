extends "basic_bot.gd"

export(String) var target_group
export(float) var vision_angle=0.53
export(int) var vision_range=0

const action_states=["sleep","move","turn","wait","attack","scan"]

func _init_fsm_states():
	._init_fsm_states()
	fsm_action.add_state("scan",{move=false,follow=false,attack=false})

func _init_fsm_move():
	fsm_action.add_link("wait","decide","timeout",[0.2])
	fsm_action.add_link("move","decide","timeout",[2])
	fsm_action.add_link("turn","decide","timeout",[1])
	fsm_action.add_link("sleep","decide","timeout",[3])
	fsm_action.add_link("decide","scan","condition",[self,"fsm_has_no_target",true])
	fsm_action.add_link("decide","move","condition",[self,"fsm_has_no_target",false])
	fsm_action.add_link("scan","decide","condition",[self,"fsm_has_no_target",false])
	fsm_action.add_link("scan","sleep","timeout",[1])

func do_current_action(state):
	if not get_target():
		scan_for_target()
	
	.do_current_action(state)

func _action_state_changed(state_from,state_to,params):
	if state_to=="scan":
		calculate_destination()
		
	._action_state_changed(state_from,state_to,params)

func get_waypoint_no_target():
	var curr_pos=get_global_transform().origin
	if not current_action.move:
		# if not moving, look around
		var a=(randf()*2-1)*PI
		var candidate_dir=Vector3(0,0,-2).rotated(UP,a)
		return curr_pos+candidate_dir
	else:
		return curr_pos

func scan_for_target():
	if target_group==null:
		return
	
	var target_dist=null
	
	var ray_origin=target_ray.get_global_transform().origin
	
	var trans=get_global_transform()
	for candidate in get_tree().get_nodes_in_group(target_group):
		var candidate_origin
		if candidate.has_method("get_global_origin"):
			candidate_origin=candidate.get_global_origin()
		else:
			candidate_origin=candidate.get_global_transform().origin
		var candidate_dist=trans.origin.distance_to(candidate_origin)
		
		# skip if candidate is too far
		if vision_range>0 and candidate_dist>vision_range:
			continue
		
		# check if target is closer than actual one
		if target_dist!=null and candidate_dist>=target_dist:
			continue # if not, skip it
		
		# check if target is in sight
		var target_trans=trans.looking_at(candidate_origin,UP).orthonormalized()
		if (target_trans.basis.z-trans.basis.z).length()<vision_angle:
			var r=get_world().get_direct_space_state().intersect_ray(ray_origin,candidate_origin,[candidate,self])
			if r.empty():
				set_target(candidate)
				target_dist=candidate_dist
	
	if target_dist!=null:
		calculate_destination(true)