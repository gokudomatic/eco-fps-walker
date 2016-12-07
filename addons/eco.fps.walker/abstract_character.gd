
extends RigidBody

const MAX_LIFE=100
const ELEMENTAL_MAX_FREQUENCY=0.5
const UP=Vector3(0,1,0)

onready var life=MAX_LIFE
var alive=true
var current_target=null
var hit_quotas=Dictionary()
var buff=Dictionary()
var elemental_timeout=0
var elemental_frequency=0
var hit_invincibility=false
onready var invincibility_timer=Timer.new()
var navmesh=null

func _ready():
	invincibility_timer=Timer.new()
	add_child(invincibility_timer)
	invincibility_timer.connect("timeout",self,"_stop_invincibility")

func _set_invincibility_hit():
	hit_invincibility=true
	invincibility_timer.set_wait_time(0.5)
	invincibility_timer.start()

func _stop_invincibility():
	hit_invincibility=false

func hit(source,special=false):
	
	if hit_invincibility:
		return
	_set_invincibility_hit()
	
	if alive:
		life=life-source.power
		if life<=0:
			# die
			die()
		else:
			# hurt
			#change quota
			create_sleep_action()
			_get_hurt()
			
		change_target(source)
		hit_special(source,special)

func _get_hurt():
	pass

func change_target(source):
	var culprit=source.owner
	if culprit!=current_target:
		if culprit in hit_quotas:
			hit_quotas[culprit]+=source.power
			if hit_quotas[culprit]>MAX_LIFE/4:
				current_target=culprit
				hit_quotas.clear()
		else:
			if current_target==null:
				current_target=culprit
			else:
				hit_quotas[culprit]=source.power

func trigger_explosion():
	return true

func create_sleep_action():
	pass

func dec_life(amount):
	if alive:
		life=life-amount
		if life<=0:
			# die
			die()