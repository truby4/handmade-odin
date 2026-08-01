package shared

MOUSE_BUTTON_LEFT :: u32(1 << 0)
MOUSE_BUTTON_MIDDLE :: u32(1 << 1)
MOUSE_BUTTON_RIGHT :: u32(1 << 2)
MOUSE_BUTTON_X1 :: u32(1 << 3)
MOUSE_BUTTON_X2 :: u32(1 << 4)

Thread_Context :: struct {
	placeholder: int,
}

Game_Offscreen_Buffer :: struct {
	memory:               rawptr,
	width, height, pitch: i32,
}

Game_Button_State :: struct {
	half_transition_count: i32,
	ended_down:            bool,
}

Game_Controller_Input :: struct {
	is_connected: bool,
	is_analog:    bool,
	stick_avg_x:  f32,
	stick_avg_y:  f32,
	using _:      struct #raw_union {
		Buttons: [12]Game_Button_State,
		using _: struct {
			Move_up:        Game_Button_State,
			Move_down:      Game_Button_State,
			Move_left:      Game_Button_State,
			Move_right:     Game_Button_State,
			Action_up:      Game_Button_State,
			Action_down:    Game_Button_State,
			Action_left:    Game_Button_State,
			Action_right:   Game_Button_State,
			Left_Shoulder:  Game_Button_State,
			Right_Shoulder: Game_Button_State,
			Start:          Game_Button_State,
			Back:           Game_Button_State,
		},
	},
}

Game_Input :: struct {
	dt_for_frame: f32,
	mouse: Mouse,
	controllers:   [5]Game_Controller_Input,
}

Mouse :: struct {
	pos:     [3]i32,
	using _: struct #raw_union {
		Buttons: [5]Game_Button_State,
		using _: struct {
			Left_Button:   Game_Button_State,
			Middle_Button: Game_Button_State,
			Right_Button:  Game_Button_State,
			X1_Button:     Game_Button_State,
			X2_Button:     Game_Button_State,
		},
	},
}


// To make sure dont access indexes which dont exist?
// better to gracefully handle it?
get_controller :: proc(input: ^Game_Input, index: int) -> ^Game_Controller_Input {
	assert(index < len(input.controllers))
	return &input.controllers[index]
}

Game_Memory :: struct {
	is_initialised:                   bool,
	permanent_storage_size:           u64,
	permanent_storage:                rawptr,
	transient_storage_size:           u64,
	transient_storage:                rawptr,
	debug_platform_read_entire_file:  debug_platform_read_entire_file,
	debug_platform_write_entire_file: debug_platform_write_entire_file,
	debug_platform_free_file_memory:  debug_platform_free_file_memory,
}

Debug_Read_File_Result :: struct {
	size:     u32,
	contents: rawptr,
}

debug_platform_read_entire_file :: proc "c" (
	thread: ^Thread_Context,
	path: string,
) -> Debug_Read_File_Result
debug_platform_write_entire_file :: proc "c" (
	thread: ^Thread_Context,
	dst: string,
	filesize: u32,
	contents: rawptr,
)
debug_platform_free_file_memory :: proc "c" (thread: ^Thread_Context, memory: rawptr)


game_update_and_render :: proc "c" (
	thread: ^Thread_Context,
	memory: ^Game_Memory,
	input: ^Game_Input,
	offscreen_buffer: ^Game_Offscreen_Buffer,
)
