package game

import api "../shared"
import "base:runtime"
import "core:fmt"
import "core:math"

Vec2 :: [2]f32

Game_State :: struct {
	player_tilemap_pos: [2]i32,
	player:             [2]f32,
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

Tile_Map :: struct {
	tiles: [^]u32,
}

World :: struct {
	count_x:          i32,
	count_y:          i32,
	upper_left_x:     f32,
	upper_left_y:     f32,
	tile_width:       f32,
	tile_height:      f32,
	tile_map_count_x: i32,
	tile_map_count_y: i32,
	tile_maps:        [^]Tile_Map,
}

Canonical_Pos :: struct {
	tile_map: [2]i32,
	tile:     [2]i32,
	tile_rel: [2]f32,
}

Raw_Pos :: struct {
	tile_map: [2]i32,
	pos:      [2]f32,
}

get_canonical_pos :: proc(world: ^World, pos: Raw_Pos) -> (new_pos: Canonical_Pos) {
	new_pos.tile_map = pos.tile_map

	x := pos.pos.x - world.upper_left_x
	y := pos.pos.y - world.upper_left_y
	new_pos.tile.x = i32(math.floor(x / world.tile_width))
	new_pos.tile.y = i32(math.floor(y / world.tile_height))

	new_pos.tile_rel.x = x - f32(new_pos.tile.x) * world.tile_width
	new_pos.tile_rel.y = y - f32(new_pos.tile.y) * world.tile_height

	assert(new_pos.tile_rel.x >= 0 && new_pos.tile_rel.x < world.tile_width)
	assert(new_pos.tile_rel.y >= 0 && new_pos.tile_rel.y < world.tile_height)

	if new_pos.tile.x < 0 {
		new_pos.tile.x = world.count_x + new_pos.tile.x
		new_pos.tile_map.x -= 1
	}

	if new_pos.tile.y < 0 {
		new_pos.tile.y = world.count_y + new_pos.tile.y
		new_pos.tile_map.y -= 1
	}

	if new_pos.tile.x >= world.count_x {
		new_pos.tile.x -= world.count_x
		new_pos.tile_map.x += 1
	}

	if new_pos.tile.y >= world.count_y {
		new_pos.tile.y -= world.count_y
		new_pos.tile_map.y += 1
	}

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


is_world_point_empty :: proc(world: ^World, pos: Raw_Pos) -> (is_empty: bool) {
	world_pos := get_canonical_pos(world, pos)

	tile_map := get_tile_map(world, world_pos.tile_map)

	is_empty = is_tile_map_point_empty(world, tile_map, world_pos.tile)

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
		game.player = Vec2{120, 150}
		game.player_tilemap_pos = {0, 0}
		// TODO(atruby): Casey says could be more appropraite to do in platform layer?
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
		{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
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
		{1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1},
		{0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_map_data11 := [9][17]u32 {
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
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
		count_x          = 17,
		count_y          = 9,
		upper_left_x     = -30,
		upper_left_y     = 0,
		tile_width       = 60,
		tile_height      = 60,
		tile_map_count_x = 2,
		tile_map_count_y = 2,
	}

	world.tile_maps = cast([^]Tile_Map)&tile_maps

	player_width := world.tile_width * 0.75
	player_height := world.tile_height
	player_left := game.player.x - (player_width / 2)
	player_top := game.player.y - player_height

	tile_map := get_tile_map(&world, game.player_tilemap_pos)
	assert(tile_map != nil)

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

			delta_player_x *= 64
			delta_player_y *= 64

			new_player_x := game.player.x + input.dt_for_frame * delta_player_x
			new_player_y := game.player.y + input.dt_for_frame * delta_player_y

			player_pos := Raw_Pos {
				tile_map = game.player_tilemap_pos,
				pos      = {new_player_x, new_player_y},
			}
			player_left := player_pos
			player_left.pos.x -= player_width * 0.5
			player_right := player_pos
			player_right.pos.x += player_width * 0.5

			if is_world_point_empty(&world, player_pos) &&
			   is_world_point_empty(&world, player_left) &&
			   is_world_point_empty(&world, player_right) {
				canonical_pos := get_canonical_pos(&world, player_pos)

				game.player_tilemap_pos = canonical_pos.tile_map
				game.player.x =
					world.upper_left_x +
					world.tile_width * f32(canonical_pos.tile.x) +
					canonical_pos.tile_rel.x
				game.player.y =
					world.upper_left_y +
					world.tile_height * f32(canonical_pos.tile.y) +
					canonical_pos.tile_rel.y
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
		1,
	)

	for row in 0 ..< 9 {
		for col in 0 ..< 17 {
			tile_id := get_tile_value_unchecked(&world, tile_map, i32(col), i32(row))
			gray: f32 = 1.0 if tile_id == 1 else 0.5

			min_x := world.upper_left_x + (f32(col) * world.tile_width)
			min_y := world.upper_left_y + (f32(row) * world.tile_height)
			max_x := min_x + f32(world.tile_width)
			max_y := min_y + f32(world.tile_height)

			draw_rectangle(offscreen_buffer, min_x, min_y, max_x, max_y, gray, gray, gray)
		}
	}

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
