package game

import "base:runtime"
import api "../shared"

Game_state :: struct {
	green_offset: i32,
	blue_offset:  i32,
}

render_weird_gradient :: proc(buffer: ^api.Game_offscreen_buffer, blue_offset, green_offset: i32) {
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

@(export)
Game_update_and_render :: proc "c" (
	memory: ^api.Game_memory,
	input: ^api.Game_input,
	offscreen_buffer: ^api.Game_offscreen_buffer,
) {
	context = runtime.default_context()
	assert(size_of(Game_state) <= memory.permanent_storage_size)

	game_state := cast(^Game_state)memory.permanent_storage
	if !memory.is_initialised {

		file := memory.debug_platform_read_entire_file("src/data/test.txt")
		if file.contents != nil {
			defer memory.debug_platform_free_file_memory(file.contents)
			memory.debug_platform_write_entire_file(
				"src/data/test.out",
				file.size,
				file.contents,
			)
		}

		// should already be 0 tbh.
		game_state.blue_offset = 0

		// TODO(atruby): Casey says could be more appropraite to do in platform layer?
		memory.is_initialised = true
	}
	for v in input.Controllers {
		if v.is_analog {
			// Use analog movement tuning
			game_state.blue_offset += i32(6.0 * (v.stick_avg_x))
			game_state.green_offset += i32(6.0 * (v.stick_avg_y))
		} else {
			// Use digital movement tuning
			if (v.Move_left.ended_down) {
				game_state.blue_offset += 4
			}
		}

		// Input.AButtonEndedDown;
		// Input.AButtonHalfTransitionCount;
		if v.Action_down.ended_down {
			game_state.green_offset += 4
		}
	}

	render_weird_gradient(offscreen_buffer, game_state.blue_offset, game_state.green_offset)
}
