package handmade

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

game_update_and_render :: proc(input: ^Game_input, offscreen_buffer: ^Game_offscreen_buffer) {
	@(static) blue_offset: i32 = 0
	@(static) green_offset: i32 = 0

	input0: ^Game_controller_input = &input.Controllers[0]

	if input0.is_analog {
		// Use analog movement tuning
		blue_offset += i32(4.0 * (input0.end_x))
	} else {
		// Use digital movement tuning
	}

	// Input.AButtonEndedDown;
	// Input.AButtonHalfTransitionCount;
	if input0.Down.ended_down {
		green_offset += 1
	}

	render_weird_gradient(offscreen_buffer, blue_offset, green_offset)
}
