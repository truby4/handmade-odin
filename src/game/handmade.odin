package game

import "base:runtime"
import "core:fmt"
import api "../shared"

Game_state :: struct {
	green_offset: i32,
	blue_offset:  i32,

	player_pos: [2]i32
}

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

render_player :: proc(buffer: ^api.Game_Offscreen_Buffer, x, y: i32) {
	PLAYER_SIZE :: 12
	PLAYER_COLOR :: u32(0xFFFFFFFF)

	min_x := x
	min_y := y
	max_x := x + PLAYER_SIZE
	max_y := y + PLAYER_SIZE

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
			pixel[x] = PLAYER_COLOR
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

		file := memory.debug_platform_read_entire_file(thread, "src/data/test.txt")
		if file.contents != nil {
			defer memory.debug_platform_free_file_memory(thread, file.contents)
			memory.debug_platform_write_entire_file(
				thread,
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


	// left_mouse_button := input.mouse.Left_Button
	// just_pressed  := left_mouse_button.ended_down && left_mouse_button.half_transition_count > 0
	// just_released := !left_mouse_button.ended_down && left_mouse_button.half_transition_count > 0
	// is_held       := left_mouse_button.ended_down

	// if just_pressed {
	// 	fmt.printfln("JUST PRESSED")
	// }
	// if just_released {
	// 	fmt.printfln("JUST RELEASED")
	// }
	// if is_held {
	// 	fmt.println("IS HELD")
	// }

	for v in input.controllers {
		if v.is_analog {
			// Use analog movement tuning
			game_state.blue_offset += i32(6.0 * (v.stick_avg_x))
			game_state.green_offset += i32(6.0 * (v.stick_avg_y))
		} else {
			// Use digital movement tuning
			if (v.Move_left.ended_down) {
				game_state.player_pos.x -= 3
			}
			if (v.Move_right.ended_down) {
				game_state.player_pos.x += 3
			}
			if (v.Move_down.ended_down) {
				game_state.player_pos.y += 20
			}
			if (v.Move_up.ended_down) {
				game_state.player_pos.y -= 3
			}
		}

		// Input.AButtonEndedDown;
		// Input.AButtonHalfTransitionCount;
		if v.Action_down.ended_down {
			game_state.green_offset += 4
		}
	}

	render_weird_gradient(offscreen_buffer, game_state.blue_offset, game_state.green_offset)
	render_player(offscreen_buffer, game_state.player_pos.x, game_state.player_pos.y)
	render_player(offscreen_buffer, input.mouse.pos.x, input.mouse.pos.y)
}
