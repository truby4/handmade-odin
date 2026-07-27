package game

import api "../shared"
import "base:runtime"
import "core:math"

Game_State :: struct {
	player_pos: Canonical_Pos,
}

Tile_Map :: struct {
	tiles: [^]u32,
}

World :: struct {
	tile_side_in_meters: f32,
	tile_side_in_pixels: i32,
	meters_to_pixels:    f32,
	count_x:             i32,
	count_y:             i32,
	lower_left_x:        f32,
	lower_left_y:        f32,
	tile_map_count_x:    i32,
	tile_map_count_y:    i32,
	tile_maps:           [^]Tile_Map,
}

Canonical_Pos :: struct {
	tile_map: [2]i32,
	tile:     [2]i32,
	tile_rel: [2]f32,
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

recanonicalise_coord :: proc(
	world: ^World,
	tile_count: i32,
	tile_map_coord: ^i32,
	tile_coord: ^i32,
	tile_rel_coord: ^f32,
) {
	tile_side := world.tile_side_in_meters

	offset: i32 = i32(math.floor(tile_rel_coord^ / tile_side))
	tile_coord^ += offset
	tile_rel_coord^ -= f32(offset) * tile_side

	assert(tile_rel_coord^ >= 0)
	assert(tile_rel_coord^ <= tile_side)

	if tile_coord^ < 0 {
		tile_coord^ += tile_count
		tile_map_coord^ -= 1
	}

	if tile_coord^ >= tile_count {
		tile_coord^ -= tile_count
		tile_map_coord^ += 1
	}
}

recanonicalise_pos :: proc(world: ^World, pos: Canonical_Pos) -> (new_pos: Canonical_Pos) {
	new_pos = pos

	recanonicalise_coord(
		world,
		world.count_x,
		&new_pos.tile_map.x,
		&new_pos.tile.x,
		&new_pos.tile_rel.x,
	)
	recanonicalise_coord(
		world,
		world.count_y,
		&new_pos.tile_map.y,
		&new_pos.tile.y,
		&new_pos.tile_rel.y,
	)

	return
}

get_tile_value_unchecked :: proc(world: ^World, tile_map: ^Tile_Map, tile_x, tile_y: i32) -> u32 {
	assert(tile_map != nil)
	assert(tile_x >= 0 && tile_x < world.count_x && tile_y >= 0 && tile_y < world.count_y)
	return tile_map.tiles[tile_y * world.count_x + tile_x]
}

get_tile_map :: proc(world: ^World, tile_map_pos: [2]i32) -> ^Tile_Map {
	if tile_map_pos.x >= 0 &&
	   tile_map_pos.x < world.tile_map_count_x &&
	   tile_map_pos.y >= 0 &&
	   tile_map_pos.y < world.tile_map_count_y {
		return &world.tile_maps[tile_map_pos.y * world.tile_map_count_x + tile_map_pos.x]
	}

	return nil
}

is_tile_map_point_empty :: proc(
	world: ^World,
	tile_map: ^Tile_Map,
	test_tile: [2]i32,
) -> (
	is_empty: bool,
) {

	if tile_map != nil &&
	   test_tile.x >= 0 &&
	   test_tile.x < world.count_x &&
	   test_tile.y >= 0 &&
	   test_tile.y < world.count_y {
		is_empty = get_tile_value_unchecked(world, tile_map, test_tile.x, test_tile.y) == 0
	}

	return
}


is_world_point_empty :: proc(world: ^World, pos: Canonical_Pos) -> (is_empty: bool) {
	tile_map := get_tile_map(world, pos.tile_map)
	is_empty = is_tile_map_point_empty(world, tile_map, pos.tile)
	return
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

	game := cast(^Game_State)memory.permanent_storage

	if !memory.is_initialised {
		game.player_pos.tile_map = {0, 0}
		game.player_pos.tile = {3, 3}
		game.player_pos.tile_rel = {5, 5}

		memory.is_initialised = true
	}

	tile_map_data00 := [9][17]u32 {
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0},
		{1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_map_data01 := [9][17]u32 {
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_map_data10 := [9][17]u32 {
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_map_data11 := [9][17]u32 {
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_maps: [2][2]Tile_Map

	tile_maps[0][0] = Tile_Map {
		tiles = cast([^]u32)&tile_map_data00[0][0],
	}

	tile_maps[0][1].tiles = cast([^]u32)&tile_map_data10[0][0]
	tile_maps[1][0].tiles = cast([^]u32)&tile_map_data01[0][0]
	tile_maps[1][1].tiles = cast([^]u32)&tile_map_data11[0][0]

	world := World {
		tile_side_in_meters = 1.4,
		tile_side_in_pixels = 60,
		meters_to_pixels    = 60 / 1.4,
		count_x             = 17,
		count_y             = 9,
		lower_left_x        = -f32(60 / 2),
		lower_left_y        = f32(offscreen_buffer.height),
		tile_map_count_x    = 2,
		tile_map_count_y    = 2,
	}

	world.tile_maps = cast([^]Tile_Map)&tile_maps

	tile_side := f32(world.tile_side_in_pixels)
	player_height: f32 = 1.4
	player_width := player_height * 0.75

	tile_map := get_tile_map(&world, game.player_pos.tile_map)
	assert(tile_map != nil)

	for controller in input.controllers {
		if controller.is_analog {
			// Use analog movement tuning

		} else {
			// Use digital movement tuning
			delta_player_x: f32 // meters/second
			delta_player_y: f32

			if controller.Move_up.ended_down {
				delta_player_y = 1
			}
			if controller.Move_down.ended_down {
				delta_player_y = -1
			}
			if controller.Move_left.ended_down {
				delta_player_x = -1
			}
			if controller.Move_right.ended_down {
				delta_player_x = 1
			}

			delta_player_x *= 2
			delta_player_y *= 2

			new_player_pos: Canonical_Pos = game.player_pos
			new_player_pos.tile_rel.x =
				game.player_pos.tile_rel.x + input.dt_for_frame * delta_player_x
			new_player_pos.tile_rel.y =
				game.player_pos.tile_rel.y + input.dt_for_frame * delta_player_y
			new_player_pos = recanonicalise_pos(&world, new_player_pos)

			player_left: Canonical_Pos = new_player_pos
			player_left.tile_rel.x -= player_width * 0.5
			player_left = recanonicalise_pos(&world, player_left)

			player_right: Canonical_Pos = new_player_pos
			player_right.tile_rel.x += player_width * 0.5
			player_right = recanonicalise_pos(&world, player_right)

			if is_world_point_empty(&world, new_player_pos) &&
			   is_world_point_empty(&world, player_left) &&
			   is_world_point_empty(&world, player_right) {
				game.player_pos = new_player_pos
			}
		}
	}


	// clear screen
	draw_rectangle(
		offscreen_buffer,
		0,
		0,
		f32(offscreen_buffer.width),
		f32(offscreen_buffer.height),
		1,
		0,
		0.1,
	)

	for row in 0 ..< 9 {
		for col in 0 ..< 17 {
			tile_id := get_tile_value_unchecked(&world, tile_map, i32(col), i32(row))
			gray: f32 = 1.0 if tile_id == 1 else 0.5

			if col == int(game.player_pos.tile.x) && row == int(game.player_pos.tile.y) {
				gray = 0
			}

			min_x := world.lower_left_x + f32(col) * tile_side
			min_y := world.lower_left_y - f32(row) * tile_side
			max_x := min_x + tile_side
			max_y := min_y - tile_side

			// passed min y max y crossed over
			draw_rectangle(offscreen_buffer, min_x, max_y, max_x, min_y, gray, gray, gray)
		}
	}

	player_left :=
		world.lower_left_x +
		tile_side * f32(game.player_pos.tile.x) +
		world.meters_to_pixels * game.player_pos.tile_rel.x -
		0.5 * world.meters_to_pixels * player_width
	player_top :=
		world.lower_left_y -
		tile_side * f32(game.player_pos.tile.y) -
		world.meters_to_pixels * game.player_pos.tile_rel.y -
		world.meters_to_pixels * player_height

	draw_rectangle(
		offscreen_buffer,
		player_left,
		player_top,
		player_left + world.meters_to_pixels * player_width,
		player_top + world.meters_to_pixels * player_height,
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
