package game

import api "../shared"
import "base:runtime"
import "core:fmt"
import "core:math"

Game_State :: struct {
	player_pos: World_Position,
}

Tile_Chunk :: struct {
	tiles: [^]u32,
}

Tile_Chunk_Position :: struct {
	chunk:    [2]u32,
	rel_tile: [2]u32,
}

World :: struct {
	chunk_shift:         u32,
	chunk_mask:          u32,
	tile_side_in_meters: f32,
	tile_side_in_pixels: i32,
	meters_to_pixels:    f32,
	chunk_dim:           u32,
	tile_chunk_count_x:  u32,
	tile_chunk_count_y:  u32,
	tile_chunks:         [^]Tile_Chunk,
}

World_Position :: struct {
	// NOTE(casey): These are fixed point tile locations.  The high
	// bits are the tile chunk index, and the low bits are the tile
	// index in the chunk.
	abs_tile: [2]u32,
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

get_tile_chunk :: proc(world: ^World, tile_chunk_pos: [2]u32) -> ^Tile_Chunk {
	if tile_chunk_pos.x >= 0 &&
	   tile_chunk_pos.x < world.tile_chunk_count_x &&
	   tile_chunk_pos.y >= 0 &&
	   tile_chunk_pos.y < world.tile_chunk_count_y {
		return &world.tile_chunks[tile_chunk_pos.y * world.tile_chunk_count_x + tile_chunk_pos.x]
	}

	return nil
}


get_tile_value_unchecked :: proc(world: ^World, tile_chunk: ^Tile_Chunk, tile_pos: [2]u32) -> u32 {
	assert(tile_chunk != nil)
	assert(tile_pos.x < world.chunk_dim)
	assert(tile_pos.y < world.chunk_dim)
	return tile_chunk.tiles[tile_pos.y * world.chunk_dim + tile_pos.x]
}


get_tile_value :: proc(
	world: ^World,
	tile_chunk: ^Tile_Chunk,
	tile_pos: [2]u32,
) -> (
	tile_chunk_value: u32,
) {
	if tile_chunk != nil {
		tile_chunk_value = get_tile_value_unchecked(world, tile_chunk, tile_pos)
	}
	return
}


recanonicalise_coord :: proc(world: ^World, tile_coord: ^u32, tile_rel_coord: ^f32) {
	// TODO(casey): Need to do something that doesn't use the divide/multiply method
	// for recanonicalizing because this can end up rounding back on to the tile
	// you just came from.

	// NOTE(casey): World is assumed to be toroidal topology, if you
	// step off one end you come back on the other!

	// e.g. tile 3 tilerel 0.5m
	// movement was 0.2m so its now tile 3 relative 0.7m
	//
	// offset = floor(0.7 / 1.4m) = 0
	offset: i32 = i32(math.round(tile_rel_coord^ / world.tile_side_in_meters))

	// so nothing would change with tile_coord
	tile_coord^ += u32(offset)

	// so new tile_rel_coord would subtract 0 if offset is 0,
	// say offset was 1 which indicates rel_coord was over tile_side in meters
	// that means it would be tile_rel_coord (1.5m) - 1.4m would leave tile_rel_coord as 0.1m
	tile_rel_coord^ -= f32(offset) * world.tile_side_in_meters

	// ensuring its not took too much off or not enough
	assert(tile_rel_coord^ >= -0.5 * world.tile_side_in_meters)
	assert(tile_rel_coord^ <= 0.5 * world.tile_side_in_meters)
}

recanonicalise_pos :: proc(world: ^World, pos: World_Position) -> (result: World_Position) {
	result = pos

	recanonicalise_coord(world, &result.abs_tile.x, &result.tile_rel.x)
	recanonicalise_coord(world, &result.abs_tile.y, &result.tile_rel.y)

	return
}


get_chunk_position_for :: proc(
	world: ^World,
	abs_tile_pos: [2]u32,
) -> (
	result: Tile_Chunk_Position,
) {
	// shifts down the absolute tile pos
	// so say its 1300..
	// 1300 >> 8:
	// Before: 00000000 00000000 00000101 00010100 = 1300
	// After:  00000000 00000000 00000000 00000101 = 5
	result.chunk.x = abs_tile_pos.x >> world.chunk_shift
	result.chunk.y = abs_tile_pos.y >> world.chunk_shift

	// Absolute X:  [00000000 00000000 00000101] [00010100]
	// Mask:        [00000000 00000000 00000000] [11111111] == 0xFF ==  255
	// Result:      [00000000 00000000 00000000] [00010100]
	// The upper bits are erased because they are ANDed with zero:
	// 1 & 0 = 0
	// The lower eight bits are preserved because they are ANDed with one:
	// 0 & 1 = 0
	// 1 & 1 = 1
	result.rel_tile.x = abs_tile_pos.x & world.chunk_mask
	result.rel_tile.y = abs_tile_pos.y & world.chunk_mask
	return
}

get_tile_value_from_abs :: proc(world: ^World, abs_tile_pos: [2]u32) -> u32 {
	chunk_pos := get_chunk_position_for(world, abs_tile_pos)
	tile_chunk := get_tile_chunk(world, chunk_pos.chunk)
	tile_chunk_value := get_tile_value(world, tile_chunk, chunk_pos.rel_tile)
	return tile_chunk_value
}

is_world_point_empty :: proc(world: ^World, pos: World_Position) -> (is_empty: bool) {
	tile_chunk_value: u32 = get_tile_value_from_abs(world, pos.abs_tile)
	is_empty = (tile_chunk_value == 0)
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

	TILE_MAP_COUNT_X :: 256
	TILE_MAP_COUNT_Y :: 256

	temp_tiles: [TILE_MAP_COUNT_Y][TILE_MAP_COUNT_X]u32 = generate_map()

	world: World
	world.chunk_shift = u32(8)
	world.chunk_mask = (u32(1) << world.chunk_shift) - 1
	world.chunk_dim = u32(1) << world.chunk_shift
	world.tile_side_in_meters = 1.4
	world.tile_side_in_pixels = 60
	world.meters_to_pixels = 60 / 1.4
	world.tile_chunk_count_x = 1
	world.tile_chunk_count_y = 1

	tile_chunk: Tile_Chunk
	tile_chunk.tiles = cast([^]u32)&temp_tiles
	world.tile_chunks = &tile_chunk

	player_height: f32 = 1.4
	player_width := player_height * 0.75

	lower_left_x: f32 = -f32(world.tile_side_in_pixels / 2.0)
	lower_left_y: f32 = f32(offscreen_buffer.height)

	game := cast(^Game_State)memory.permanent_storage

	if !memory.is_initialised {
		game.player_pos.abs_tile.x = 3
		game.player_pos.abs_tile.y = 3
		game.player_pos.tile_rel.x = 5.0
		game.player_pos.tile_rel.y = 5.0

		memory.is_initialised = true
	}

	tile_side_in_pixels := f32(world.tile_side_in_pixels)

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

			new_player_pos: World_Position = game.player_pos
			new_player_pos.tile_rel.x =
				game.player_pos.tile_rel.x + input.dt_for_frame * delta_player_x
			new_player_pos.tile_rel.y =
				game.player_pos.tile_rel.y + input.dt_for_frame * delta_player_y
			new_player_pos = recanonicalise_pos(&world, new_player_pos)

			player_left: World_Position = new_player_pos
			player_left.tile_rel.x -= player_width * 0.5
			player_left = recanonicalise_pos(&world, player_left)

			player_right: World_Position = new_player_pos
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

	screen_center_x: f32 = 0.5 * f32(offscreen_buffer.width)
	screen_center_y: f32 = 0.5 * f32(offscreen_buffer.height)

	// `rel_column = 0`, `rel_row = 0` means the tile containing the player
	// hence relative
	for rel_row in -10 ..< 10 {
		for rel_column in -20 ..< 20 {
			// these convert the relative to absolute based on player pos
			// for e.g. if the player is on {10,15}
			// rel_column = -2  → column = 8
			// rel_row    =  3  → row    = 18
			column: u32 = game.player_pos.abs_tile.x + u32(rel_column)
			row: u32 = game.player_pos.abs_tile.y + u32(rel_row)

			tile_id: u32 = get_tile_value_from_abs(&world, {column, row})

			gray: f32 = 0.5
			if tile_id == 1 {
				gray = 1.0
			}

			if column == game.player_pos.abs_tile.x && row == game.player_pos.abs_tile.y {
				gray = 0.0
			}

			cen_x: f32 =
				screen_center_x -
				world.meters_to_pixels * game.player_pos.tile_rel.x +
				f32(i32(rel_column) * world.tile_side_in_pixels)
			cen_y: f32 =
				screen_center_y +
				world.meters_to_pixels * game.player_pos.tile_rel.y -
				f32(i32(rel_row) * world.tile_side_in_pixels)


			min_x: f32 = cen_x - 0.5 * f32(world.tile_side_in_pixels)
			min_y: f32 = cen_y - 0.5 * f32(world.tile_side_in_pixels)
			max_x: f32 = cen_x + 0.5 * f32(world.tile_side_in_pixels)
			max_y: f32 = cen_y + 0.5 * f32(world.tile_side_in_pixels)

			// passed min y max y crossed over
			draw_rectangle(offscreen_buffer, min_x, min_y, max_x, max_y, gray, gray, gray)
		}
	}

	player_left: f32 = screen_center_x + -0.5 * world.meters_to_pixels * player_width
	player_top: f32 = screen_center_y - world.meters_to_pixels * player_height

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
