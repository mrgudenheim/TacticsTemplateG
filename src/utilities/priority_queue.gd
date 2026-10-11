class_name PriorityQueue
extends RefCounted
## High-performance Binary Min-Heap Priority Queue
## Items with smaller priority values are popped first.

var _priorities: Array[float] = []
var _values: Array = []


## Pushes an item with the given priority into the heap
func push(value: Variant, priority: float) -> void:
	_values.append(value)
	_priorities.append(priority)
	_sift_up(_values.size() - 1)


## Pops and returns the item with the smallest priority
func pop() -> Variant:
	if _values.is_empty():
		push_error("Cannot pop from an empty PriorityQueue")
		return null
	var min_val: Variant = _values[0]
	var last_idx: int = _values.size() - 1
	if last_idx == 0:
		_values.clear()
		_priorities.clear()
		return min_val
	_values[0] = _values[last_idx]
	_priorities[0] = _priorities[last_idx]
	_values.pop_back()
	_priorities.pop_back()
	_sift_down(0)
	return min_val


## Pops and returns [value, priority]
func pop_with_priority() -> Array:
	if _values.is_empty():
		push_error("Cannot pop from an empty PriorityQueue")
		return [null, INF]
	var min_val: Variant = _values[0]
	var min_p: float = _priorities[0]
	var last_idx: int = _values.size() - 1
	if last_idx == 0:
		_values.clear()
		_priorities.clear()
		return [min_val, min_p]
	_values[0] = _values[last_idx]
	_priorities[0] = _priorities[last_idx]
	_values.pop_back()
	_priorities.pop_back()
	_sift_down(0)
	return [min_val, min_p]


## Returns the item with the smallest priority without removing it
func peek() -> Variant:
	if _values.is_empty():
		return null
	return _values[0]


## Returns the minimum priority without removing the item
func peek_priority() -> float:
	if _priorities.is_empty():
		return INF
	return _priorities[0]


func is_empty() -> bool:
	return _values.is_empty()


func size() -> int:
	return _values.size()


func clear() -> void:
	_values.clear()
	_priorities.clear()


## Ensures the min-heap property by moving an element upward from 'idx' toward the root
func _sift_up(idx: int) -> void:
	while idx > 0:
		var parent_idx: int = (idx - 1) >> 1 # (idx - 1) / 2
		if _priorities[idx] < _priorities[parent_idx]: # ensure every parent's priority must be <= its children's priorities.
			_swap(idx, parent_idx)
			idx = parent_idx
		else:
			break


## Ensures the min-heap property by moving an element downward from 'idx' toward the leaves.
func _sift_down(idx: int) -> void:
	var count: int = _values.size()
	while true:
		var left_child: int = (idx << 1) + 1 # (idx * 2) + 1
		var right_child: int = left_child + 1
		var smallest: int = idx
		# Identify the smallest priority among current, left_child, right_child
		if left_child < count and _priorities[left_child] < _priorities[smallest]:
			smallest = left_child
		if right_child < count and _priorities[right_child] < _priorities[smallest]:
			smallest = right_child
		if smallest != idx: # if the smallest priority is one of the children
			_swap(idx, smallest)
			idx = smallest
		else: # if the current node is already <= both children
			break


func _swap(i: int, j: int) -> void:
	var temp_val: Variant = _values[i]
	_values[i] = _values[j]
	_values[j] = temp_val
	var temp_p: float = _priorities[i]
	_priorities[i] = _priorities[j]
	_priorities[j] = temp_p
