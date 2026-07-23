package game

import api "../shared"
import "base:runtime"
import "core:fmt"

Game_state :: struct {}

render_weird_gradient :: proc(buffer: ^api.Game_Offscreen_Buffer, blue_offset, green_offset: i32) {
	width := buffer.width
	height := buffer.height
	pitch := buffer.pitch

	row := ([^]u8)(buffer.memory)

	for y in 0 ..< height {
		pixel := ([^]u32)(row)

		for x in 0 ..< width {
			blue := u8(x + blue_offset)
			green := u8(y + green_offset)

			pixel[x] = (u32(green) << 8) | u32(blue)
			// pixel[x] = 0x00FF00FF

		}

		row = ([^]u8)(uintptr(row) + uintptr(pitch))
	}
}

round_f32_to_i32 :: proc(f: f32) -> i32 {
	return i32(f + 0.5)
}


draw_rectangle :: proc(
	buffer: ^api.Game_Offscreen_Buffer,
	real_min_x, real_min_y, real_max_x, real_max_y: f32,
) {
	COLOR :: u32(0xFFFFFFFF)

	min_x: i32 = round_f32_to_i32(real_min_x)
	min_y: i32 = round_f32_to_i32(real_min_y)
	max_x: i32 = round_f32_to_i32(real_max_x)
	max_y: i32 = round_f32_to_i32(real_max_y)

	if min_x < 0 do min_x = 0
	if min_y < 0 do min_y = 0
	if max_x > buffer.width do max_x = buffer.width
	if max_y > buffer.height do max_y = buffer.height

	if min_x >= max_x || min_y >= max_y {
		return
	}

	row := ([^]u8)(uintptr(buffer.memory) + uintptr(min_y * buffer.pitch))
	for y in min_y ..< max_y {
		pixel := ([^]u32)(row)
		for x in min_x ..< max_x {
			pixel[x] = COLOR
		}
		row = ([^]u8)(uintptr(row) + uintptr(buffer.pitch))
	}
}

@(export)
game_update_and_render :: proc "c" (
	thread: ^api.Thread_Context,
	memory: ^api.Game_Memory,
	input: ^api.Game_Input,
	offscreen_buffer: ^api.Game_Offscreen_Buffer,
) {
	context = runtime.default_context()
	assert(size_of(Game_state) <= memory.permanent_storage_size)

	game_state := cast(^Game_state)memory.permanent_storage
	if !memory.is_initialised {

		// TODO(atruby): Casey says could be more appropraite to do in platform layer?
		memory.is_initialised = true
	}

	for v in input.controllers {
		if v.is_analog {
			// Use analog movement tuning

		} else {
			// Use digital movement tuning

		}
	}

	draw_rectangle(offscreen_buffer, 50, 50, 100, 100)
	draw_rectangle(offscreen_buffer, -50, 200, 100, 300)
}
