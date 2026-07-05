package handmade

import "core:fmt"

Game_offscreen_buffer :: struct {
	memory:               rawptr,
	width, height, pitch: i32,
}

Game_button_state :: struct {
	half_transition_count: int,
	ended_down:            bool,
}

Game_controller_input :: struct {
	is_analog: bool,
	start_x:   f32,
	start_y:   f32,
	min_x:     f32,
	min_y:     f32,
	max_x:     f32,
	max_y:     f32,
	end_x:     f32,
	end_y:     f32,
	using _:   struct #raw_union {
		Buttons: [6]Game_button_state,
		using _: struct {
			Up:             Game_button_state,
			Down:           Game_button_state,
			Left:           Game_button_state,
			Right:          Game_button_state,
			Left_Shoulder:  Game_button_state,
			Right_Shoulder: Game_button_state,
		},
	},
}

Game_input :: struct {
	Controllers: [4]Game_controller_input,
}

Game_memory :: struct {
	is_initialised:         bool,
	permanent_storage_size: u64,
	permanent_storage:      rawptr,
	transient_storage_size: u64,
	transient_storage:      rawptr,
}

Game_state :: struct {
	green_offset: i32,
	blue_offset:  i32,
}

Debug_read_file_result :: struct {
	size:     u32,
	contents: rawptr,
}

render_weird_gradient :: proc(buffer: ^Game_offscreen_buffer, blue_offset, green_offset: i32) {
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
		}

		row = ([^]u8)(uintptr(row) + uintptr(pitch))
	}
}

game_update_and_render :: proc(
	memory: ^Game_memory,
	input: ^Game_input,
	offscreen_buffer: ^Game_offscreen_buffer,
) {
	assert(size_of(Game_state) <= memory.permanent_storage_size)

	game_state := cast(^Game_state)memory.permanent_storage
	if !memory.is_initialised {

		filename := "src/data/test.txt"

		file, ok := debug_platform_read_entire_file(filename)
		if ok {
			defer debug_platform_free_file_memory(file.contents)
			debug_platform_write_entire_file("src/data/test.out", file.size, file.contents)
		}

		// should already be 0 tbh.
		game_state.blue_offset = 0
		// TODO(atruby): Casey says could be more appropraite to do in platform layer?
		memory.is_initialised = true
	}

	input0: ^Game_controller_input = &input.Controllers[0]

	if input0.is_analog {
		// Use analog movement tuning
		game_state.blue_offset += i32(4.0 * (input0.end_x))
	} else {
		// Use digital movement tuning
	}

	// Input.AButtonEndedDown;
	// Input.AButtonHalfTransitionCount;
	if input0.Down.ended_down {
		game_state.green_offset += 1
	}

	render_weird_gradient(offscreen_buffer, game_state.blue_offset, game_state.green_offset)
}
