package shared

Game_offscreen_buffer :: struct {
	memory:               rawptr,
	width, height, pitch: i32,
}

Game_button_state :: struct {
	half_transition_count: i32,
	ended_down:            bool,
}

Game_controller_input :: struct {
	is_connected: bool,
	is_analog:    bool,
	stick_avg_x:  f32,
	stick_avg_y:  f32,
	using _:      struct #raw_union {
		Buttons: [12]Game_button_state,
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
get_controller :: proc(input: ^Game_input, index: int) -> ^Game_controller_input {
	assert(index < len(input.Controllers))
	return &input.Controllers[index]
}

Game_memory :: struct {
	is_initialised:                  bool,
	permanent_storage_size:          u64,
	permanent_storage:               rawptr,
	transient_storage_size:          u64,
	transient_storage:               rawptr,
	debug_platform_read_entire_file: debug_platform_read_entire_file,
	debug_platform_write_entire_file: debug_platform_write_entire_file,
	debug_platform_free_file_memory: debug_platform_free_file_memory,
}

Debug_read_file_result :: struct {
	size:     u32,
	contents: rawptr,
}

debug_platform_read_entire_file :: proc "c" (path: cstring) -> Debug_read_file_result
debug_platform_write_entire_file :: proc "c" (dst: cstring, filesize: u32, contents: rawptr)
debug_platform_free_file_memory :: proc "c" (memory: rawptr)


game_update_and_render :: proc "c" (
	memory: ^Game_memory,
	input: ^Game_input,
	offscreen_buffer: ^Game_offscreen_buffer,
)
