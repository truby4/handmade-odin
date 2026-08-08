package game

import api "../shared"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/rand"

Game_State :: struct {
	world_arena:           Memory_Arena,
	world:                 ^World,
	camera_pos:            Tile_Map_Position,
	player_pos:            Tile_Map_Position,
	backdrop:              Loaded_Bitmap,
	hero_facing_direction: u32,
	hero_bitmaps:          [4]Hero_Bitmaps,
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
	real_min, real_max: [2]f32,
	r, g, b: f32,
) {

	min_x: i32 = i32(math.round(real_min.x))
	min_y: i32 = i32(math.round(real_min.y))
	max_x: i32 = i32(math.round(real_max.x))
	max_y: i32 = i32(math.round(real_max.y))

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

Bit_Scan_Result :: struct {
	found: bool,
	index: u32,
}

Hero_Bitmaps :: struct {
	align_x: i32,
	align_y: i32,
	head:    Loaded_Bitmap,
	cape:    Loaded_Bitmap,
	torso:   Loaded_Bitmap,
}

find_least_significant_set_bit :: proc(value: u32) -> (result: Bit_Scan_Result) {
	for test: u32 = 0; test < 32; test += 1 {
		if value & (u32(1) << test) != 0 {
			result.index = test
			result.found = true
			break
		}
	}

	return
}

draw_bitmap :: proc(
	buffer: ^api.Game_Offscreen_Buffer,
	bitmap: Loaded_Bitmap,
	real_x, real_y: f32,
	align_x, align_y: i32,
) {
	real_x_new := real_x - f32(align_x)
	real_y_new := real_y - f32(align_y)

	min_x := i32(math.round(real_x_new))
	min_y := i32(math.round(real_y_new))
	max_x := i32(math.round(real_x_new + f32(bitmap.width)))
	max_y := i32(math.round(real_y_new + f32(bitmap.height)))

	source_offset_x: i32
	if min_x < 0 {
		source_offset_x = -min_x
		min_x = 0
	}

	source_offset_y: i32
	if min_y < 0 {
		source_offset_y = -min_y
		min_y = 0
	}

	if max_x > buffer.width do max_x = buffer.width
	if max_y > buffer.height do max_y = buffer.height

	if min_x >= max_x || min_y >= max_y {
		return
	}

	source_row_index :=
		bitmap.width * (bitmap.height - 1) - source_offset_y * bitmap.width + source_offset_x
	source_row := ([^]u32)(uintptr(bitmap.pixels) + uintptr(source_row_index) * size_of(u32))

	dest_row := ([^]u8)(
		uintptr(buffer.memory) + uintptr(min_x) * size_of(u32) + uintptr(min_y * buffer.pitch),
	)

	for y in min_y ..< max_y {
		dest := cast([^]u32)dest_row
		source := source_row

		for x in min_x ..< max_x {
			index := x - min_x
			source_color := source[index]
			a := f32((source_color >> 24) & 0xff) / 255.0
			source_r := f32((source_color >> 16) & 0xff)
			source_g := f32((source_color >> 8) & 0xff)
			source_b := f32((source_color >> 0) & 0xff)

			dest_color := dest[index]
			dest_r := f32((dest_color >> 16) & 0xff)
			dest_g := f32((dest_color >> 8) & 0xff)
			dest_b := f32((dest_color >> 0) & 0xff)

			r := (1.0 - a) * dest_r + a * source_r
			g := (1.0 - a) * dest_g + a * source_g
			b := (1.0 - a) * dest_b + a * source_b

			dest[index] = u32(r + 0.5) << 16 | u32(g + 0.5) << 8 | u32(b + 0.5) << 0
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

		assert(header.compression == 3)

		red_mask := header.red_mask
		green_mask := header.green_mask
		blue_mask := header.blue_mask
		alpha_mask := ~(red_mask | green_mask | blue_mask)

		red_shift := find_least_significant_set_bit(red_mask)
		green_shift := find_least_significant_set_bit(green_mask)
		blue_shift := find_least_significant_set_bit(blue_mask)
		alpha_shift := find_least_significant_set_bit(alpha_mask)

		assert(red_shift.found)
		assert(green_shift.found)
		assert(blue_shift.found)
		assert(alpha_shift.found)

		source_dest := pixels

		for y in 0 ..< header.height {
			for x in 0 ..< header.width {
				pixel_index := y * header.width + x
				color := source_dest[pixel_index]

				source_dest[pixel_index] =
					((color >> alpha_shift.index) & 0xff) << 24 |
					((color >> red_shift.index) & 0xff) << 16 |
					((color >> green_shift.index) & 0xff) << 8 |
					((color >> blue_shift.index) & 0xff) << 0
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
		hero_directions := [4]string{"right", "back", "left", "front"}
		for direction, index in hero_directions {
			hero := &game.hero_bitmaps[index]
			hero.align_x = 72
			hero.align_y = 182

			hero.head = debug_load_bmp(
				thread,
				memory.debug_platform_read_entire_file,
				fmt.tprintf("src/data/test/test_hero_%s_head.bmp", direction),
			)
			hero.cape = debug_load_bmp(
				thread,
				memory.debug_platform_read_entire_file,
				fmt.tprintf("src/data/test/test_hero_%s_cape.bmp", direction),
			)
			hero.torso = debug_load_bmp(
				thread,
				memory.debug_platform_read_entire_file,
				fmt.tprintf("src/data/test/test_hero_%s_torso.bmp", direction),
			)
		}

		game.camera_pos.abs_tile.x = 17 / 2
		game.camera_pos.abs_tile.y = 9 / 2

		game.player_pos.abs_tile.x = 1
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

		tiles_per_width: i32 = 17
		tiles_per_height: i32 = 9
		screen_pos: [2]i32
		abs_tile: Abs_Tile_Pos

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
				if abs_tile.z == 0 {
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
					abs_tile.x = u32(screen_pos.x * tiles_per_width + tile_x)
					abs_tile.y = u32(screen_pos.y * tiles_per_height + tile_y)

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

					set_tile_value(&game.world_arena, tile_map, abs_tile, tile_value)
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
				if abs_tile.z == 0 {
					abs_tile.z = 1
				} else {
					abs_tile.z = 0
				}
			} else if rand_choice == 1 {
				screen_pos.x += 1
			} else {
				screen_pos.y += 1
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

	for controller in input.controllers {
		if controller.is_analog {
			// Use analog movement tuning

		} else {
			delta_player_pos: [2]f32

			if controller.Move_up.ended_down {
				game.hero_facing_direction = 1
				delta_player_pos.y = 1
			}
			if controller.Move_down.ended_down {
				game.hero_facing_direction = 3
				delta_player_pos.y = -1
			}
			if controller.Move_left.ended_down {
				game.hero_facing_direction = 2
				delta_player_pos.x = -1
			}
			if controller.Move_right.ended_down {
				game.hero_facing_direction = 0
				delta_player_pos.x = 1
			}
			// Adjusting for diagonal movement
			ONE_OVER_SQRT_TWO :: 0.70710678
			if delta_player_pos.x != 0 && delta_player_pos.y != 0 {
				delta_player_pos *= ONE_OVER_SQRT_TWO
			}

			player_speed: f32 = 2.0
			if controller.Action_up.ended_down {
				player_speed = 10
			}
			delta_player_pos *= player_speed

			new_player_pos: Tile_Map_Position = game.player_pos
			new_player_pos.offsets =
				game.player_pos.offsets + input.dt_for_frame * delta_player_pos
			new_player_pos = recanonicalise_pos(tile_map, new_player_pos)

			player_left: Tile_Map_Position = new_player_pos
			player_left.offsets -= [2]f32{player_width * 0.5, 0}
			player_left = recanonicalise_pos(tile_map, player_left)

			player_right: Tile_Map_Position = new_player_pos
			player_right.offsets += [2]f32{player_width * 0.5, 0}
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

			game.camera_pos.abs_tile.z = game.player_pos.abs_tile.z

			camera_diff := subtract(tile_map, game.player_pos, game.camera_pos)
			if camera_diff.x > 9.0 * tile_map.tile_side_in_meters {
				game.camera_pos.abs_tile.x += 17
			}
			if camera_diff.x < -9.0 * tile_map.tile_side_in_meters {
				game.camera_pos.abs_tile.x -= 17
			}
			if camera_diff.y > 5.0 * tile_map.tile_side_in_meters {
				game.camera_pos.abs_tile.y += 9
			}
			if camera_diff.y < -5.0 * tile_map.tile_side_in_meters {
				game.camera_pos.abs_tile.y -= 9
			}
		}
	}


	// clear screen
	draw_rectangle(
		offscreen_buffer,
		{0, 0},
		{f32(offscreen_buffer.width), f32(offscreen_buffer.height)},
		1,
		0,
		0.1,
	)

	draw_bitmap(offscreen_buffer, game.backdrop, 0, 0, 0, 0)

	screen_center := 0.5 * [2]f32 {
		f32(offscreen_buffer.width),
		f32(offscreen_buffer.height),
	}

	// `rel_column = 0`, `rel_row = 0` means the tile containing the player
	// hence relative
	for rel_row in -10 ..< 10 {
		for rel_column in -20 ..< 20 {
			// these convert the relative to absolute based on player pos
			// for e.g. if the player is on {10,15}
			// rel_column = -2  → column = 8
			// rel_row    =  3  → row    = 18
			column: u32 = game.camera_pos.abs_tile.x + u32(rel_column)
			row: u32 = game.camera_pos.abs_tile.y + u32(rel_row)

			tile_id: u32 = get_tile_value_from_abs(
				tile_map,
				{column, row, game.camera_pos.abs_tile.z},
			)

			if tile_id > 1 {
				gray: f32 = 0.5
				if tile_id == 2 {
					gray = 1.0
				}

				if tile_id > 2 {
					gray = 0.25
				}

				if column == game.camera_pos.abs_tile.x && row == game.camera_pos.abs_tile.y {
					gray = 0.0
				}

				center := screen_center + [2]f32 {
					-meters_to_pixels * game.camera_pos.offsets.x +
						f32(i32(rel_column) * tile_side_in_pixels),
					meters_to_pixels * game.camera_pos.offsets.y -
						f32(i32(rel_row) * tile_side_in_pixels),
				}
				tile_radius := 0.5 * [2]f32{f32(tile_side_in_pixels), f32(tile_side_in_pixels)}
				min := center - tile_radius
				max := center + tile_radius

				// passed min y max y crossed over
				draw_rectangle(offscreen_buffer, min, max, gray, gray, gray)
			}
		}
	}
	diff: Tile_Map_Difference = subtract(tile_map, game.player_pos, game.camera_pos)
	player_ground_point := screen_center + meters_to_pixels * [2]f32{diff.x, -diff.y}
	player_dim := meters_to_pixels * [2]f32{player_width, player_height}
	player_min := player_ground_point - [2]f32{0.5 * player_dim.x, player_dim.y}
	player_max := player_min + player_dim

	draw_rectangle(
		offscreen_buffer,
		player_min,
		player_max,
		1,
		1,
		0,
	)

	hero_bitmaps := game.hero_bitmaps[game.hero_facing_direction]
	draw_bitmap(
		offscreen_buffer,
		hero_bitmaps.torso,
		player_ground_point.x,
		player_ground_point.y,
		hero_bitmaps.align_x,
		hero_bitmaps.align_y,
	)
	draw_bitmap(
		offscreen_buffer,
		hero_bitmaps.cape,
		player_ground_point.x,
		player_ground_point.y,
		hero_bitmaps.align_x,
		hero_bitmaps.align_y,
	)
	draw_bitmap(
		offscreen_buffer,
		hero_bitmaps.head,
		player_ground_point.x,
		player_ground_point.y,
		hero_bitmaps.align_x,
		hero_bitmaps.align_y,
	)
}
