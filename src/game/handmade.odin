package game

import api "../shared"
import "base:runtime"
import "core:fmt"
import "core:math"

Vec2 :: [2]f32

Game_State :: struct {
	player: [2]f32,
}

draw_rectangle :: proc(
	buffer: ^api.Game_Offscreen_Buffer,
	real_min_x, real_min_y, real_max_x, real_max_y: f32,
	r, g, b: f32,
) {

	min_x: i32 = i32(math.round(real_min_x))
	min_y: i32 = i32(math.round(real_min_y))
	max_x: i32 = i32(math.round(real_max_x))
	max_y: i32 = i32(math.round(real_max_y))

	if min_x < 0 do min_x = 0
	if min_y < 0 do min_y = 0
	if max_x > buffer.width do max_x = buffer.width
	if max_y > buffer.height do max_y = buffer.height

	if min_x >= max_x || min_y >= max_y {
		return
	}

	// BIT PATTERN: 0x AA RR GG BB
	color: u32 =
		u32(math.round(r * 255)) << 16 |
		u32(math.round(g * 255)) << 8 |
		u32(math.round(b * 255)) << 0


	row := ([^]u8)(uintptr(buffer.memory) + uintptr(min_y * buffer.pitch))
	for y in min_y ..< max_y {
		pixel := ([^]u32)(row)
		for x in min_x ..< max_x {
			pixel[x] = color
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
	assert(size_of(Game_State) <= memory.permanent_storage_size)

	game_state := cast(^Game_State)memory.permanent_storage

	if !memory.is_initialised {
		game_state.player = Vec2{50, 75}
		// TODO(atruby): Casey says could be more appropraite to do in platform layer?
		memory.is_initialised = true
	}

	for controller in input.controllers {
		if controller.is_analog {
			// Use analog movement tuning

		} else {
			// Use digital movement tuning
			delta_player_x: f32 // pixels/second
			delta_player_y: f32

			if controller.Move_up.ended_down {
				delta_player_y = -1
			}
			if controller.Move_down.ended_down {
				delta_player_y = 1
			}
			if controller.Move_left.ended_down {
				delta_player_x = -1
			}
			if controller.Move_right.ended_down {
				delta_player_x = 1
			}

			delta_player_x *= 160
			delta_player_y *= 160

			game_state.player.x += input.dt_for_frame*delta_player_x
			game_state.player.y += input.dt_for_frame*delta_player_y
		}
	}

	tile_map := [9][17]u32 {
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1},
		{0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0},
		{1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	}


	draw_rectangle(
		offscreen_buffer,
		0,
		0,
		f32(offscreen_buffer.width),
		f32(offscreen_buffer.height),
		1,
		0,
		1,
	)

	upper_left_x: f32 = -30
	upper_left_y: f32 = 0
	tile_width: f32 = 60
	tile_height: f32 = 60

	for row in 0 ..< 9 {
		for col in 0 ..< 17 {
			tile_id := tile_map[row][col]
			gray: f32 = 1.0 if tile_id == 1 else 0.5

			min_x := upper_left_x + (f32(col) * tile_width)
			min_y := upper_left_y + (f32(row) * tile_height)
			max_x := min_x + f32(tile_width)
			max_y := min_y + f32(tile_height)

			draw_rectangle(offscreen_buffer, min_x, min_y, max_x, max_y, gray, gray, gray)
		}
	}


	player_width := tile_width * 0.75
	player_height := tile_height * 0.75
	player_left := game_state.player.x - 0.5
	player_top := game_state.player.y - player_height

	draw_rectangle(
		offscreen_buffer,
		player_left,
		player_top,
		player_left + player_width,
		player_top + player_height,
		1,
		1,
		0,
	)
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
