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
	is_connected: bool,
	is_analog:    bool,
	stick_avg_x:  f32,
	stick_avg_y:  f32,
	using _:      struct #raw_union {
		Buttons: [10]Game_button_state,
		using _: struct {
			Move_up:        Game_button_state,
			Move_down:      Game_button_state,
			Move_left:      Game_button_state,
			Move_right:     Game_button_state,
			Action_up:      Game_button_state,
			Action_down:    Game_button_state,
			Action_left:    Game_button_state,
			Action_right:   Game_button_state,
			Left_Shoulder:  Game_button_state,
			Right_Shoulder: Game_button_state,
			Start:          Game_button_state,
			Back:           Game_button_state,
		},
	},
}

Game_input :: struct {
	Controllers: [5]Game_controller_input,
}

// To make sure dont access indexes which dont exist?
// better to gracefully handle it?
Get_controller :: proc(input: ^Game_input, index: int) -> ^Game_controller_input {
	assert(index < len(input.Controllers))
	return &input.Controllers[index]
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
