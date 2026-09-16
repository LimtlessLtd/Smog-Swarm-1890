class_name ChunkBuildQueue
extends RefCounted

## Runs the data half of a streamed chunk build on WorkerThreadPool, one task
## per chunk address, and hands finished results back to the main thread.
##
## TerrainMeshView and TerrainDetailView used to build CHUNKS_BUILT_PER_FRAME
## = 1 chunk synchronously in _process(), so each chunk landed whole inside
## one frame: mean 61.7 ms, worst 359 ms on a cold file read
## (bench_chunk_build.gd, 2026-09-07). File read, decode, scatter and mesh
## array construction touch no scene tree and no RenderingServer resource, so
## they run here; node, ArrayMesh and MultiMesh creation stays with the view.
##
## `prepare` must be safe to run on a worker thread: no Node access, no
## resource loading, and no lazily-initialised static a main-thread caller
## could be creating at the same moment.
##
## WorkerThreadPool has no cancel. A task whose address leaves the wanted set
## while it runs finishes anyway and its result is dropped at hand-back. A
## prepare is deterministic per address, so an address that comes back into
## view before its task finishes keeps that task rather than queuing a second.

var _prepare: Callable  ## (address: Vector2i) -> Variant. Called on a worker thread.
var _max_in_flight: int
var _pending: Array[Vector2i] = []
var _in_flight: Dictionary = {}  ## Vector2i -> [task_id: int, holder: Array]. holder[0] is written once, by the worker, before its task completes.
var _wanted: Dictionary = {}  ## Vector2i -> true, as of the last retain_only()/request().


## `max_in_flight` bounds how many worker threads one view occupies at once.
func _init(prepare: Callable, max_in_flight: int) -> void:
	_prepare = prepare
	_max_in_flight = maxi(max_in_flight, 1)


## True while `address` is queued or its task is still running.
func is_requested(address: Vector2i) -> bool:
	return _in_flight.has(address) or _pending.has(address)


func request(address: Vector2i) -> void:
	_wanted[address] = true
	if not is_requested(address):
		_pending.append(address)


## Replaces the wanted set. Pending addresses outside it are dropped without
## running; running ones are dropped when they finish.
func retain_only(wanted: Dictionary) -> void:
	_wanted = wanted
	# Rebuilt element by element, not via Array.filter() -- that returns an
	# untyped Array, and assigning one to an Array[Vector2i] is a runtime error.
	var still_wanted: Array[Vector2i] = []
	for address in _pending:
		if wanted.has(address):
			still_wanted.append(address)
	_pending = still_wanted


## Starts pending builds up to the in-flight bound. Call once per frame.
func pump() -> void:
	while _in_flight.size() < _max_in_flight and not _pending.is_empty():
		var address: Vector2i = _pending.pop_front()
		var holder: Array = [null]
		var task_id := WorkerThreadPool.add_task(_run.bind(address, holder), false, "ChunkBuildQueue")
		_in_flight[address] = [task_id, holder]


## One finished, still-wanted build as [address, result], or [] if none is
## ready. Finished builds that are no longer wanted are released on the way.
func take_finished() -> Array:
	for address: Vector2i in _in_flight.keys():
		var entry: Array = _in_flight[address]
		if not WorkerThreadPool.is_task_completed(entry[0]):
			continue
		# Required even for a completed task: it is what releases the task id.
		WorkerThreadPool.wait_for_task_completion(entry[0])
		_in_flight.erase(address)
		if _wanted.has(address):
			return [address, (entry[1] as Array)[0]]
	return []


## Nothing queued or running.
func is_idle() -> bool:
	return _pending.is_empty() and _in_flight.is_empty()


## Drops everything. Running tasks still finish; their results are discarded.
func clear() -> void:
	_pending.clear()
	_wanted = {}


## Blocks until every running task has finished and discards the results.
## Owners call this from _exit_tree(), so no task outlives the view whose
## `prepare` it is running.
func wait_all() -> void:
	_pending.clear()
	_wanted = {}
	for address: Vector2i in _in_flight.keys():
		WorkerThreadPool.wait_for_task_completion((_in_flight[address] as Array)[0])
	_in_flight.clear()


func _run(address: Vector2i, holder: Array) -> void:
	holder[0] = _prepare.call(address)
