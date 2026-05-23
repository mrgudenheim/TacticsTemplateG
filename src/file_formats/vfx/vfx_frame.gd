class_name VfxFrame
extends Resource

var vram_bytes: PackedByteArray = []
@export var palette_id: int = 0
@export var semi_transparency_mode: int = 0
@export var image_color_depth: int = 0 # 0 = 4bpp, 1 = 8bpp
@export var semi_transparency_on: bool = true
@export var frame_width_signed: bool = false
@export var frame_height_signed: bool = false
var texture_page: int = 0

@export var top_left_uv: Vector2i = Vector2i.ZERO
@export var uv_width: int = 0
@export var uv_height: int = 0
@export var top_left_xy: Vector2i = Vector2i.ZERO
@export var top_right_xy: Vector2i = Vector2i.ZERO
@export var bottom_left_xy: Vector2i = Vector2i.ZERO
@export var bottom_right_xy: Vector2i = Vector2i.ZERO
@export var quad_vertices: PackedVector3Array = []
@export var quad_uvs_pixels: PackedVector2Array = []
@export var quad_uvs: PackedVector2Array = []


func parse_vram_bytes(frame_bytes: PackedByteArray) -> void:
	vram_bytes = frame_bytes.slice(0, 4)
	palette_id = vram_bytes[0] & 0x0f
	semi_transparency_mode = (vram_bytes[0] & 0x60) >> 5
	image_color_depth = 4 + ((vram_bytes[0] & 0x80) >> 5)
	semi_transparency_on = (vram_bytes[1] & 0x02) == 0x02
	frame_width_signed = (vram_bytes[1] & 0x10) == 0x10
	frame_height_signed = (vram_bytes[1] & 0x20) == 0x20
	texture_page = vram_bytes.decode_u16(2)


func parse_geometry_bytes(frame_bytes: PackedByteArray, v_offset: int = 0) -> void:
	var u: int = frame_bytes.decode_u8(4)
	var v: int = frame_bytes.decode_u8(5) - v_offset
	top_left_uv = Vector2i(u, v)

	if frame_width_signed:
		uv_width = frame_bytes.decode_s8(6)
	else:
		uv_width = frame_bytes.decode_u8(6)
	if frame_height_signed:
		uv_height = frame_bytes.decode_s8(7)
	else:
		uv_height = frame_bytes.decode_u8(7)

	top_left_xy = Vector2i(frame_bytes.decode_s16(8), frame_bytes.decode_s16(0xa))
	top_right_xy = Vector2i(frame_bytes.decode_s16(0xc), frame_bytes.decode_s16(0xe))
	bottom_left_xy = Vector2i(frame_bytes.decode_s16(0x10), frame_bytes.decode_s16(0x12))
	bottom_right_xy = Vector2i(frame_bytes.decode_s16(0x14), frame_bytes.decode_s16(0x16))

	quad_uvs_pixels = PackedVector2Array(
		[
			Vector2(u, v),
			Vector2(u + uv_width, v),
			Vector2(u, v + uv_height),
			Vector2(u + uv_width, v + uv_height),
		],
	)

	var vertices_xy: PackedVector2Array = [
		Vector2(top_left_xy),
		Vector2(top_right_xy),
		Vector2(bottom_left_xy),
		Vector2(bottom_right_xy),
	]
	for vert: Vector2 in vertices_xy:
		quad_vertices.append(Vector3(vert.x, -vert.y, 0) * FftMapData.SCALE)
