package game

import api "../shared"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/rand"

Game_State :: struct {
	world_arena:   Memory_Arena,
	world:         ^World,
	player_pos:    Tile_Map_Position,
	pixel_pointer: [^]u32,
	backdrop:      Loaded_Bitmap,
	hero_head:     Loaded_Bitmap,
	hero_cape:     Loaded_Bitmap,
	hero_torso:    Loaded_Bitmap,
}

World :: struct {
	tile_map: ^Tile_Map,
}

Memory_Index :: distinct uintptr

Memory_Arena :: struct {
	size: Memory_Index,
	base: [^]u8,
	used: Memory_Index,
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

Loaded_Bitmap :: struct {
	pixels: [^]u32,
	width:  i32,
	height: i32,
}

draw_bitmap :: proc(
	buffer: ^api.Game_Offscreen_Buffer,
	bitmap: Loaded_Bitmap,
	real_x, real_y: f32,
) {
	min_x := i32(math.round(real_x))
	min_y := i32(math.round(real_y))
	max_x := i32(math.round(real_x + f32(bitmap.width)))
	max_y := i32(math.round(real_y + f32(bitmap.height)))

	if min_x < 0 do min_x = 0
	if min_y < 0 do min_y = 0
	if max_x > buffer.width do max_x = buffer.width
	if max_y > buffer.height do max_y = buffer.height

	if min_x >= max_x || min_y >= max_y {
		return
	}

	source_row := ([^]u32)(
		uintptr(bitmap.pixels) + uintptr(bitmap.width * (bitmap.height - 1)) * size_of(u32),
	)

	dest_row := ([^]u8)(
		uintptr(buffer.memory) + uintptr(min_x) * size_of(u32) + uintptr(min_y * buffer.pitch),
	)

	for y in min_y ..< max_y {
		dest := cast([^]u32)dest_row
		source := source_row

		for x in min_x ..< max_x {
			index := x - min_x
			dest[index] = source[index]
		}

		dest_row = ([^]u8)(uintptr(dest_row) + uintptr(buffer.pitch))

		source_row = ([^]u32)(uintptr(source_row) - uintptr(bitmap.width) * size_of(u32))
	}
}

Bitmap_Header :: struct #packed {
	file_type:        u16,
	file_size:        u32,
	reserved_1:       u16,
	reserved_2:       u16,
	bitmap_offset:    u32,
	size:             u32,
	width:            i32,
	height:           i32,
	planes:           u16,
	bits_per_pixel:   u16,
	compression:      u32,
	size_of_bitmap:   u32,
	horz_resolution:  i32,
	vert_resolution:  i32,
	colors_used:      u32,
	colors_important: u32,
	red_mask:         u32,
	green_mask:       u32,
	blue_mask:        u32,
}

debug_load_bmp :: proc(
	thread_context: ^api.Thread_Context,
	read_entire_file: api.debug_platform_read_entire_file,
	filename: string,
) -> (
	result: Loaded_Bitmap,
) {
	read_result := read_entire_file(thread_context, filename)

	if read_result.size != 0 {
		header := cast(^Bitmap_Header)read_result.contents

		pixels := cast([^]u32)(uintptr(read_result.contents) + uintptr(header.bitmap_offset))

		result.pixels = pixels
		result.width = header.width
		result.height = header.height

		source_dest := pixels

		for y in 0 ..< header.height {
			for x in 0 ..< header.width {
				pixel_index := y * header.width + x
				value := source_dest[pixel_index]

				source_dest[pixel_index] = (value >> 8) | (value << 24)
			}
		}
	}

	return
}

arena_init :: proc(arena: ^Memory_Arena, size: Memory_Index, base: [^]u8) {
	arena.size = size
	arena.base = base
	arena.used = 0
}

push_size_ :: proc(arena: ^Memory_Arena, size: Memory_Index) -> rawptr {
	assert(arena.used + size <= arena.size)

	result := rawptr(uintptr(arena.base) + uintptr(arena.used))

	arena.used += size
	return result
}

push_struct :: proc(arena: ^Memory_Arena, $T: typeid) -> ^T {
	size := Memory_Index(size_of(T))
	return cast(^T)push_size_(arena, size)
}

push_array :: proc(arena: ^Memory_Arena, count: Memory_Index, $T: typeid) -> [^]T {
	size := count * Memory_Index(size_of(T))
	return cast([^]T)push_size_(arena, size)
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

	player_height: f32 = 1.4
	player_width := player_height * 0.75


	game := cast(^Game_State)memory.permanent_storage

	if !memory.is_initialised {
		game.backdrop = debug_load_bmp(
			thread,
			memory.debug_platform_read_entire_file,
			"src/data/test/test_background.bmp",
		)
		game.hero_head = debug_load_bmp(
			thread,
			memory.debug_platform_read_entire_file,
			"src/data/test/test_hero_front_head.bmp",
		)
		game.hero_cape = debug_load_bmp(
			thread,
			memory.debug_platform_read_entire_file,
			"src/data/test/test_hero_front_cape.bmp",
		)
		game.hero_torso = debug_load_bmp(
			thread,
			memory.debug_platform_read_entire_file,
			"src/data/test/test_hero_front_torso.bmp",
		)

		game.player_pos.abs_tile.x = 3
		game.player_pos.abs_tile.y = 3
		game.player_pos.offsets.x = 5.0
		game.player_pos.offsets.y = 5.0

		game_state_size := size_of(Game_State)

		arena_init(
			&game.world_arena,
			Memory_Index(memory.permanent_storage_size - u64(game_state_size)),
			([^]u8)(uintptr(memory.permanent_storage) + uintptr(game_state_size)),
		)

		game.world = push_struct(&game.world_arena, World)
		world: ^World = game.world

		world.tile_map = push_struct(&game.world_arena, Tile_Map)
		tile_map: ^Tile_Map = world.tile_map

		tile_map.chunk_shift = u32(4)
		tile_map.chunk_mask = (u32(1) << tile_map.chunk_shift) - 1
		tile_map.chunk_dim = u32(1) << tile_map.chunk_shift

		tile_map.tile_side_in_meters = 1.4

		tile_map.tile_chunk_count_x = 128
		tile_map.tile_chunk_count_y = 128
		tile_map.tile_chunk_count_z = 2

		tile_chunk: Tile_Chunk
		// tile_chunk.tiles = cast([^]u32)&temp_tiles
		tile_map.tile_chunks = push_array(
			&game.world_arena,
			Memory_Index(
				tile_map.tile_chunk_count_x *
				tile_map.tile_chunk_count_y *
				tile_map.tile_chunk_count_z,
			),
			Tile_Chunk,
		)

		tiles_per_width := 17
		tiles_per_height := 9
		screen_x := 0
		screen_y := 0
		abs_tile_z := 0

		door_left: bool
		door_right: bool
		door_top: bool
		door_bottom: bool
		door_up: bool
		door_down: bool

		for screen_index in 0 ..< 100 {
			rand_choice: u32
			if door_up || door_down {
				rand_choice = rand.uint32_range(0, 2)
			} else {
				rand_choice = rand.uint32_range(0, 3)
			}
			created_z_door: bool

			if rand_choice == 2 {
				created_z_door = true
				if abs_tile_z == 0 {
					door_up = true
				} else {
					door_down = true
				}
			} else if rand_choice == 1 {
				door_right = true
			} else {
				door_top = true
			}

			for tile_y in 0 ..< tiles_per_height {
				for tile_x in 0 ..< tiles_per_width {
					abs_tile_x := screen_x * tiles_per_width + tile_x
					abs_tile_y := screen_y * tiles_per_height + tile_y

					tile_value: u32 = 1
					if tile_x == 0 && (!door_left || tile_y != (tiles_per_height / 2)) {
						tile_value = 2
					}

					if tile_x == (tiles_per_width - 1) &&
					   (!door_right || tile_y != (tiles_per_height / 2)) {
						tile_value = 2
					}

					if tile_y == 0 && (!door_bottom || tile_x != (tiles_per_width / 2)) {
						tile_value = 2
					}

					if tile_y == (tiles_per_height - 1) &&
					   (!door_top || (tile_x != tiles_per_width / 2)) {
						tile_value = 2
					}

					if tile_x == 10 && tile_y == 6 {
						if door_up {
							tile_value = 3
						}
						if door_down {
							tile_value = 4
						}
					}

					set_tile_value(
						&game.world_arena,
						tile_map,
						Abs_Tile_Pos{u32(abs_tile_x), u32(abs_tile_y), u32(abs_tile_z)},
						tile_value,
					)
				}
			}

			door_left = door_right
			door_bottom = door_top

			if created_z_door {
				door_down = !door_down
				door_up = !door_up
			} else {
				door_up = false
				door_down = false
			}

			door_right = false
			door_top = false

			if rand_choice == 2 {
				if abs_tile_z == 0 {
					abs_tile_z = 1
				} else {
					abs_tile_z = 0
				}
			} else if rand_choice == 1 {
				screen_x += 1
			} else {
				screen_y += 1
			}
		}

		memory.is_initialised = true
	}

	world := game.world
	tile_map := world.tile_map

	tile_side_in_pixels: i32 = 60
	meters_to_pixels: f32 = f32(tile_side_in_pixels) / f32(tile_map.tile_side_in_meters)
	lower_left_x: f32 = -f32(tile_side_in_pixels / 2.0)
	lower_left_y: f32 = f32(offscreen_buffer.height)

	player_speed: f32 = 2.0

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
			if controller.Action_up.ended_down {
				player_speed = 10
			}

			delta_player_x *= player_speed
			delta_player_y *= player_speed

			new_player_pos: Tile_Map_Position = game.player_pos
			new_player_pos.offsets.x =
				game.player_pos.offsets.x + input.dt_for_frame * delta_player_x
			new_player_pos.offsets.y =
				game.player_pos.offsets.y + input.dt_for_frame * delta_player_y
			new_player_pos = recanonicalise_pos(tile_map, new_player_pos)

			player_left: Tile_Map_Position = new_player_pos
			player_left.offsets.x -= player_width * 0.5
			player_left = recanonicalise_pos(tile_map, player_left)

			player_right: Tile_Map_Position = new_player_pos
			player_right.offsets.x += player_width * 0.5
			player_right = recanonicalise_pos(tile_map, player_right)

			if is_tilemap_point_empty(tile_map, new_player_pos) &&
			   is_tilemap_point_empty(tile_map, player_left) &&
			   is_tilemap_point_empty(tile_map, player_right) {
				if !are_on_same_tile(game.player_pos, new_player_pos) {
					new_tile_value := get_tile_value_from_tile_map_pos(tile_map, new_player_pos)
					if new_tile_value == 3 {
						new_player_pos.abs_tile.z += 1
					} else if new_tile_value == 4 {
						new_player_pos.abs_tile.z -= 1
					}
				}
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

			tile_id: u32 = get_tile_value_from_abs(
				tile_map,
				{column, row, game.player_pos.abs_tile.z},
			)

			if tile_id > 0 {
				gray: f32 = 0.5
				if tile_id == 2 {
					gray = 1.0
				}

				if tile_id > 2 {
					gray = 0.25
				}

				if column == game.player_pos.abs_tile.x && row == game.player_pos.abs_tile.y {
					gray = 0.0
				}

				cen_x: f32 =
					screen_center_x -
					meters_to_pixels * game.player_pos.offsets.x +
					f32(i32(rel_column) * tile_side_in_pixels)
				cen_y: f32 =
					screen_center_y +
					meters_to_pixels * game.player_pos.offsets.y -
					f32(i32(rel_row) * tile_side_in_pixels)


				min_x: f32 = cen_x - 0.5 * f32(tile_side_in_pixels)
				min_y: f32 = cen_y - 0.5 * f32(tile_side_in_pixels)
				max_x: f32 = cen_x + 0.5 * f32(tile_side_in_pixels)
				max_y: f32 = cen_y + 0.5 * f32(tile_side_in_pixels)

				// passed min y max y crossed over
				draw_rectangle(offscreen_buffer, min_x, min_y, max_x, max_y, gray, gray, gray)
			}
		}
	}

	player_left: f32 = screen_center_x + -0.5 * meters_to_pixels * player_width
	player_top: f32 = screen_center_y - meters_to_pixels * player_height

	draw_rectangle(
		offscreen_buffer,
		player_left,
		player_top,
		player_left + meters_to_pixels * player_width,
		player_top + meters_to_pixels * player_height,
		1,
		1,
		0,
	)

	draw_bitmap(offscreen_buffer, game.backdrop, 0, 0)
}
