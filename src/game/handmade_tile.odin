package game

import "core:math"

Abs_Tile_Pos :: [3]u32
Tile_Chunk_Pos :: [3]u32

Tile_Map_Position :: struct {
	// NOTE(casey): These are fixed point tile locations (abs_tile).  The high
	// bits are the tile chunk index, and the low bits are the tile
	// index in the chunk.
	abs_tile: Abs_Tile_Pos,
	offsets:  [2]f32, // these are the offsets from the tile center
}

Tile_Chunk :: struct {
	tiles: [^]u32,
}

Tile_Chunk_Position :: struct {
	chunk:    Tile_Chunk_Pos,
	rel_tile: [2]u32,
}

Tile_Map :: struct {
	chunk_shift:         u32,
	chunk_mask:          u32,
	tile_side_in_meters: f32,
	chunk_dim:           u32,
	tile_chunk_count_x:  u32,
	tile_chunk_count_y:  u32,
	tile_chunk_count_z:  u32,
	tile_chunks:         [^]Tile_Chunk,
}

Tile_Map_Difference :: [3]f32

subtract :: proc(
	tile_map: ^Tile_Map,
	a, b: Tile_Map_Position,
) -> Tile_Map_Difference {
	a_tiles := [3]f32 {
		f32(a.abs_tile.x),
		f32(a.abs_tile.y),
		f32(a.abs_tile.z),
	}
	b_tiles := [3]f32 {
		f32(b.abs_tile.x),
		f32(b.abs_tile.y),
		f32(b.abs_tile.z),
	}

	result := tile_map.tile_side_in_meters * (a_tiles - b_tiles)
	result.x += a.offsets.x - b.offsets.x
	result.y += a.offsets.y - b.offsets.y

	return result
}


recanonicalise_coord :: proc(tile_map: ^Tile_Map, tile_coord: ^u32, tile_rel_coord: ^f32) {
	// TODO(casey): Need to do something that doesn't use the divide/multiply method
	// for recanonicalizing because this can end up rounding back on to the tile
	// you just came from.

	// NOTE(casey): World is assumed to be toroidal topology, if you
	// step off one end you come back on the other!

	// e.g. tile 3 tilerel 0.5m
	// movement was 0.2m so its now tile 3 relative 0.7m
	//
	// offset = floor(0.7 / 1.4m) = 0
	offset: i32 = i32(math.round(tile_rel_coord^ / tile_map.tile_side_in_meters))

	// so nothing would change with tile_coord
	tile_coord^ += u32(offset)

	// so new tile_rel_coord would subtract 0 if offset is 0,
	// say offset was 1 which indicates rel_coord was over tile_side in meters
	// that means it would be tile_rel_coord (1.5m) - 1.4m would leave tile_rel_coord as 0.1m
	tile_rel_coord^ -= f32(offset) * tile_map.tile_side_in_meters

	// ensuring its not took too much off or not enough
	assert(tile_rel_coord^ >= -0.5 * tile_map.tile_side_in_meters)
	assert(tile_rel_coord^ <= 0.5 * tile_map.tile_side_in_meters)
}

recanonicalise_pos :: proc(
	tile_map: ^Tile_Map,
	pos: Tile_Map_Position,
) -> (
	result: Tile_Map_Position,
) {
	result = pos

	recanonicalise_coord(tile_map, &result.abs_tile.x, &result.offsets.x)
	recanonicalise_coord(tile_map, &result.abs_tile.y, &result.offsets.y)

	return
}


get_tile_chunk :: proc(world: ^Tile_Map, tile_chunk_pos: Tile_Chunk_Pos) -> ^Tile_Chunk {
	if tile_chunk_pos.x >= 0 &&
	   tile_chunk_pos.x < world.tile_chunk_count_x &&
	   tile_chunk_pos.y >= 0 &&
	   tile_chunk_pos.y < world.tile_chunk_count_y &&
	   tile_chunk_pos.z >= 0 &&
	   tile_chunk_pos.z < world.tile_chunk_count_z {
		return(
			&world.tile_chunks[tile_chunk_pos.z * world.tile_chunk_count_y * world.tile_chunk_count_x + tile_chunk_pos.y * world.tile_chunk_count_x + tile_chunk_pos.x] \
		)
	}

	return nil
}


get_tile_value_unchecked :: proc(
	tile_map: ^Tile_Map,
	tile_chunk: ^Tile_Chunk,
	tile_pos: [2]u32,
) -> u32 {
	assert(tile_chunk != nil)
	assert(tile_pos.x < tile_map.chunk_dim)
	assert(tile_pos.y < tile_map.chunk_dim)
	return tile_chunk.tiles[tile_pos.y * tile_map.chunk_dim + tile_pos.x]
}


get_tile_value :: proc(
	tile_map: ^Tile_Map,
	tile_chunk: ^Tile_Chunk,
	tile_pos: [2]u32,
) -> (
	tile_chunk_value: u32,
) {
	if tile_chunk != nil && tile_chunk.tiles != nil {
		tile_chunk_value = get_tile_value_unchecked(tile_map, tile_chunk, tile_pos)
	}
	return
}


get_chunk_position_for :: proc(
	tile_map: ^Tile_Map,
	abs_tile_pos: Abs_Tile_Pos,
) -> (
	result: Tile_Chunk_Position,
) {
	// shifts down the absolute tile pos
	// so say its 1300..
	// 1300 >> 8:
	// Before: 00000000 00000000 00000101 00010100 = 1300
	// After:  00000000 00000000 00000000 00000101 = 5
	result.chunk.x = abs_tile_pos.x >> tile_map.chunk_shift
	result.chunk.y = abs_tile_pos.y >> tile_map.chunk_shift
	result.chunk.z = abs_tile_pos.z

	// Absolute X:  [00000000 00000000 00000101] [00010100]
	// Mask:        [00000000 00000000 00000000] [11111111] == 0xFF ==  255
	// Result:      [00000000 00000000 00000000] [00010100]
	// The upper bits are erased because they are ANDed with zero:
	// 1 & 0 = 0
	// The lower eight bits are preserved because they are ANDed with one:
	// 0 & 1 = 0
	// 1 & 1 = 1
	result.rel_tile.x = abs_tile_pos.x & tile_map.chunk_mask
	result.rel_tile.y = abs_tile_pos.y & tile_map.chunk_mask
	return
}

get_tile_value_from_abs :: proc(tile_map: ^Tile_Map, abs_tile_pos: Abs_Tile_Pos) -> u32 {
	chunk_pos := get_chunk_position_for(tile_map, abs_tile_pos)
	tile_chunk := get_tile_chunk(tile_map, chunk_pos.chunk)
	tile_chunk_value := get_tile_value(tile_map, tile_chunk, chunk_pos.rel_tile)
	return tile_chunk_value
}

get_tile_value_from_tile_map_pos :: proc(
	tile_map: ^Tile_Map,
	tile_map_pos: Tile_Map_Position,
) -> u32 {
	tile_chunk_value := get_tile_value_from_abs(tile_map, tile_map_pos.abs_tile)
	return tile_chunk_value
}

is_tilemap_point_empty :: proc(tile_map: ^Tile_Map, pos: Tile_Map_Position) -> (is_empty: bool) {
	tile_chunk_value: u32 = get_tile_value_from_abs(tile_map, pos.abs_tile)
	is_empty = (tile_chunk_value == 1) || (tile_chunk_value == 3) || (tile_chunk_value == 4)
	return
}

set_tile_value_unchecked :: proc(
	tile_map: ^Tile_Map,
	tile_chunk: ^Tile_Chunk,
	tile_pos: [2]u32,
	value: u32,
) {
	assert(tile_chunk != nil)
	assert(tile_pos.x < tile_map.chunk_dim)
	assert(tile_pos.y < tile_map.chunk_dim)

	tile_chunk.tiles[tile_pos.y * tile_map.chunk_dim + tile_pos.x] = value
}

set_tile_value_absolute :: proc(
	arena: ^Memory_Arena,
	tile_map: ^Tile_Map,
	abs_pos: Abs_Tile_Pos,
	value: u32,
) {
	chunk_pos := get_chunk_position_for(tile_map, abs_pos)
	chunk := get_tile_chunk(tile_map, chunk_pos.chunk)

	assert(chunk != nil)

	if chunk.tiles == nil {
		tile_count: u32 = tile_map.chunk_dim * tile_map.chunk_dim
		chunk.tiles = push_array(arena, Memory_Index(tile_count), u32)
		for tile_index in 0 ..< tile_count {
			chunk.tiles[tile_index] = 1
		}
	}

	set_tile_value(tile_map, chunk, chunk_pos.rel_tile, value)
}

set_tile_value_chunk :: proc(
	tile_map: ^Tile_Map,
	chunk: ^Tile_Chunk,
	rel_pos: [2]u32,
	value: u32,
) {
	if chunk != nil && chunk.tiles != nil {
		set_tile_value_unchecked(tile_map, chunk, rel_pos, value)
	}
}

set_tile_value :: proc {
	set_tile_value_absolute,
	set_tile_value_chunk,
}

are_on_same_tile :: proc(a, b: Tile_Map_Position) -> bool {
	return a.abs_tile == b.abs_tile
}
