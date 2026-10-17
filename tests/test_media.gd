extends SceneTree

const Actor = preload("res://scripts/creature_actor.gd")
const Effect = preload("res://scripts/move_effect.gd")
var checks: int = 0
var failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/animations.json"))
	_expect(parsed is Dictionary, "Character animation manifest loads")
	if not parsed is Dictionary:
		quit(1)
		return
	var animations: Dictionary = parsed.get("animations", {})
	_expect(animations.size() == 37, "All 37 original animated forms are mapped")
	var actor: Actor = Actor.new()
	root.add_child(actor)
	actor.size = Vector2(320, 280)
	actor.set_process(false)
	var completions: Dictionary = {"count": 0, "state": ""}
	actor.animation_finished.connect(func(state: String) -> void:
		completions["count"] = int(completions["count"]) + 1
		completions["state"] = state
	)
	var total: int = 0
	var frames: int = 0
	for id: String in animations:
		var states: Dictionary = animations[id]
		_expect(states.size() == 5, "Five original states exist for species " + id)
		actor.setup(int(id))
		var stable_position: Vector2 = actor.image.position
		var stable_size: Vector2 = actor.image.size
		for state: String in ["idle", "attack", "hit", "ko", "victory"]:
			_expect(states.has(state), id + " maps " + state)
			if not states.has(state):
				continue
			var definition: Dictionary = states[state]
			var path: String = str(definition.get("texture", ""))
			_expect(ResourceLoader.exists(path), path + " exists")
			var duration: float = actor.play_state(state)
			_expect(actor.atlas != null, id + "/" + state + " uses its original atlas")
			if actor.atlas == null:
				continue
			var cell := Vector2(float(definition.cell_size[0]), float(definition.cell_size[1]))
			var expected_size := Vector2(float(definition.columns) * cell.x, float(definition.rows) * cell.y)
			_expect(actor.atlas.atlas.get_size() == expected_size, "Atlas dimensions match " + path)
			_expect(is_equal_approx(float(definition.fps), 24.0), "Original 24 FPS preserved")
			_expect(int(definition.frame_count) <= int(definition.columns) * int(definition.rows), "Frames fit atlas")
			_expect(is_equal_approx(duration, float(definition.frame_count) / float(definition.fps)), "Duration follows every original frame")
			_expect(actor.image.position.is_equal_approx(stable_position) and actor.image.size.is_equal_approx(stable_size), "Logical pivot and scale remain stable across actions for " + id)
			_expect(not actor.clip_contents and actor.atlas.region.size == cell, "Full frame renders without viewport crop")
			var before: int = int(completions["count"])
			if state == "idle":
				actor._process(duration * 2.0 + 0.01)
				_expect(actor.current_state == "idle" and not actor.state_complete, "Idle loops")
				_expect(int(completions["count"]) == before, "Idle does not signal one-shot completion")
			else:
				actor._process(duration - 0.5 / float(definition.fps))
				_expect(actor.current_frame == int(definition.frame_count) - 1, "Final source frame is shown before completion")
				actor._process(1.0 / float(definition.fps))
				_expect(int(completions["count"]) == before + 1 and completions["state"] == state, "One completion event per original one-shot")
				var terminal: bool = state in ["ko", "victory"]
				_expect(actor.current_state == state if terminal else actor.current_state == "idle", "Only attack and hit return to idle")
				if terminal:
					_expect(actor.state_complete and actor.current_frame == int(definition.frame_count) - 1, "KO/victory retain their final frame")
				actor._process(duration * 2.0)
				_expect(int(completions["count"]) == before + 1, "Completed actions cannot emit twice")
			total += 1
			frames += int(definition.frame_count)
	_expect(total == 185, "All 185 action sheets are played and checked")
	_expect(frames == 17754, "Every original source frame is mapped")
	actor.setup(1, true)
	_expect(actor.image.flip_h, "Enemy facing mirrors the full cell")
	actor.playback_speed = 2.0
	var quick_duration: float = actor.play_state("attack")
	_expect(is_equal_approx(quick_duration, 2.0), "Double speed returns half the original duration")
	actor._process(quick_duration)
	_expect(actor.current_state == "idle", "Double speed completes without changing frame order")
	actor.playback_speed = 1.0
	actor.setup(1, false, false)
	_expect(actor.atlas == null and actor.image.texture != null, "Reduced motion uses the original static portrait")
	actor.setup(110)
	_expect(actor.atlas == null and actor.image.texture != null, "Unanimated species retain static fallback")
	actor.queue_free()
	_test_effects()
	await process_frame
	print("MEDIA_TESTS ", checks, " checks; ", failures, " failures; ", total, " sheets / ", frames, " frames")
	quit(0 if failures == 0 else 1)


func _test_effects() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx.json"))
	_expect(parsed is Dictionary, "VFX manifest loads")
	if not parsed is Dictionary:
		return
	var types: Dictionary = parsed.get("types", {})
	_expect(types.size() == 8, "All eight game types have original effects")
	var moves: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/mosse.json"))
	if moves is Array:
		for move: Dictionary in moves:
			_expect(parsed.get("moves", {}).has(str(int(move.id))), "Move ID has a type effect mapping")
	for kind: String in types:
		var effect: Effect = Effect.new()
		root.add_child(effect)
		effect.set_process(false)
		var result: Dictionary = {"finished": 0}
		effect.finished.connect(func() -> void: result["finished"] = int(result["finished"]) + 1)
		var definition: Dictionary = types[kind]
		var target := Rect2(30, 40, 240, 200)
		var duration: float = effect.setup(int(definition.source_move_id), kind, target)
		_expect(duration > 0.0 and effect.atlas != null, "Original type VFX loads: " + kind)
		_expect(effect.position == target.position and effect.size == target.size, "VFX targets the arena rectangle")
		if effect.atlas != null:
			var expected := Vector2(float(definition.columns) * float(definition.cell_size[0]), float(definition.rows) * float(definition.cell_size[1]))
			_expect(effect.atlas.atlas.get_size() == expected, "VFX dimensions match its manifest")
			effect._process(duration - 0.5 / float(definition.fps))
			_expect(effect.current_frame == int(definition.frame_count) - 1, "VFX displays its last original frame")
			effect._process(1.0 / float(definition.fps))
			effect._process(duration)
			_expect(effect.completed and effect.is_queued_for_deletion() and int(result["finished"]) == 1, "VFX finishes once and cleans up")
	var fallback: Effect = Effect.new()
	root.add_child(fallback)
	fallback.set_process(false)
	fallback.playback_speed = 3.0
	var quick_duration: float = fallback.setup(-1, "Acqua")
	_expect(quick_duration > 0.0, "An unknown move uses its declared type")
	_expect(is_equal_approx(quick_duration * 3.0, float(fallback.animation.frame_count) / float(fallback.animation.fps)), "VFX speed scales duration consistently")
	fallback._process(quick_duration)
	_expect(fallback.completed, "VFX speed scales playback consistently")
	fallback.queue_free()


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
