package platform

import "base:intrinsics"
import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import sdl "vendor:sdl2"
import mix "vendor:sdl2/mixer"
import api "../shared"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

Kilobytes :: #force_inline proc(value: u64) -> u64 {return value * 1024}
Megabytes :: #force_inline proc(value: u64) -> u64 {return Kilobytes(value) * 1024}
Gigabytes :: #force_inline proc(value: u64) -> u64 {return Megabytes(value) * 1024}
Terabytes :: #force_inline proc(value: u64) -> u64 {return Gigabytes(value) * 1024}

@(private = "file")
Config :: struct {
	internal:   bool `args:"name=internal"`,
	slow_build: bool `args:"name=slow-build"`,
}

@(private = "file")
Platform_SDL :: struct {
	running:          bool,
	surface:          ^sdl.Surface,
	window:           ^sdl.Window,
	game_controllers: [4]^sdl.GameController, // added 4 to be the max number of controllers? waste of memory?
	music:            ^mix.Music,
}

global_pause := false

main :: proc() {
	config: Config
	flags.parse_or_exit(&config, os.args)

	p := Platform_SDL{}
	p.running = true

	base_address: uintptr

	if config.internal {
		base_address = cast(uintptr)Terabytes(2)
	} else {
		base_address = 0
	}

	game_memory: api.Game_memory
	game_memory.permanent_storage_size = Megabytes(64)
	game_memory.transient_storage_size = Gigabytes(4)
	game_memory.debug_platform_read_entire_file = debug_platform_read_entire_file
	game_memory.debug_platform_write_entire_file = debug_platform_write_entire_file
	game_memory.debug_platform_free_file_memory = debug_platform_free_file_memory
	total_size: u64 = game_memory.permanent_storage_size + game_memory.transient_storage_size
	reserved_block, err := virtual.reserve(uint(total_size), base_address)
	assert(err == nil, "Virtual reserve error")

	err = virtual.commit(raw_data(reserved_block), uint(total_size))
	assert(err == nil, "Virtual commit error")

	game_memory.permanent_storage = raw_data(reserved_block)
	game_memory.transient_storage = rawptr(
		uintptr(game_memory.permanent_storage) + uintptr(game_memory.permanent_storage_size),
	)

	fmt.printfln(
		"Game memory initialised:\nPerm Storage Address: %p\nTransient Storage: %p",
		game_memory.permanent_storage,
		game_memory.transient_storage,
	)

	game_code_load_counter := 0
	game_code, ok := load_game_code("build/libhandmade.so", "build/libhandmade_temp.so")
	if ok {
		fmt.println("Game code loaded")
	} else {
		fmt.eprintln("Using game-code stub")
	}
	defer unload_game_code(&game_code)

	assert(
		sdl.Init(sdl.INIT_EVERYTHING) == 0,
		fmt.tprintf("Error initialising sdl: %s", sdl.GetError()),
	)

	defer sdl.Quit()

	// TODO(atruby): How do we reliably query refreshrate in SDL?
	monitor_refresh_hz := 60
	game_update_hz := monitor_refresh_hz
	target_seconds_per_frame := 1.0 / cast(f32)game_update_hz

	p.window = sdl.CreateWindow(
		"Handmade Odin",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		sdl.WINDOW_SHOWN | sdl.WINDOW_RESIZABLE,
	)
	assert(p.window != nil, fmt.tprintf("Error creating window: %s", sdl.GetError()))
	defer sdl.DestroyWindow(p.window)

	num_joysticks := sdl.NumJoysticks()
	for i in 0 ..< i32(4) {
		if sdl.IsGameController(i) {
			game_controller := sdl.GameControllerOpen(i)
			// just do first 4?
			p.game_controllers[i] = game_controller
		}
	}

	if mix.OpenAudio(48000, sdl.AUDIO_S16SYS, 2, 1024) < 0 {
		fmt.printfln("Mixer error: %s", mix.GetError())
	}
	defer mix.CloseAudio()

	music := mix.LoadMUS("src/data/wonders_of_the_earth.mp3")
	if music == nil {
		fmt.printfln("Load music error: %s", mix.GetError())
	}
	defer mix.FreeMusic(music)

	mix.PlayMusic(music, -1)

	resize_surface(&p)
	sdl.UpdateWindowSurface(p.window)

	event: sdl.Event

	// pointer swap shit for thee game inputs
	input: [2]api.Game_input = {}
	new_input: ^api.Game_input = &input[0]
	old_input: ^api.Game_input = &input[1]

	perf_count_frequency: u64 = sdl.GetPerformanceFrequency()

	last_counter: u64 = sdl.GetPerformanceCounter()
	last_cycle_count: i64 = intrinsics.read_cycle_counter()

	main_loop: for p.running {
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				p.running = false
			case .WINDOWEVENT:
				if event.window.event == sdl.WindowEventID.RESIZED {
					resize_surface(&p)
				}
			case .KEYDOWN:
				key := event.key.keysym.sym
				#partial switch key {
				case sdl.Keycode.ESCAPE:
					p.running = false
				case sdl.Keycode.P:
					global_pause = !global_pause
					if mix.PausedMusic() == 1 {
						mix.ResumeMusic()
					} else {
						mix.PauseMusic()
					}
				}
			}
		}
		game_code_load_counter += 1
		if game_code_load_counter > 120 {
			unload_game_code(&game_code)
			game_code, ok = load_game_code("build/libhandmade.so", "build/libhandmade_temp.so")
			if ok {
				fmt.println("New Game code loaded")
			} else {
				fmt.eprintln("Failed somewhere, Using game-code stub")
			}
			game_code_load_counter = 0
		}

		if (!global_pause) {

			@(static) frame := 0
			frame += 1


			old_keyboard_controller: ^api.Game_controller_input = api.Get_controller(old_input, 0)
			new_keyboard_controller: ^api.Game_controller_input = api.Get_controller(new_input, 0)
			reset_controller_input(old_keyboard_controller, new_keyboard_controller)
			new_keyboard_controller.is_connected = true

			keys := sdl.GetKeyboardState(nil)
			process_keyboard_input(old_keyboard_controller, new_keyboard_controller, keys)

			for v, i in p.game_controllers {
				if v == nil {
					continue
				}
				// adjusts index so that the 0 index can be the keyboard
				old_controller: ^api.Game_controller_input = api.Get_controller(old_input, i + 1)
				new_controller: ^api.Game_controller_input = api.Get_controller(new_input, i + 1)
				reset_controller_input(old_controller, new_controller)

				if !sdl.GameControllerGetAttached(v) {
					new_controller.is_connected = false
					fmt.println("Game controller disconnected")
					continue
				}

				// the way im trying to copy from casey, this will mean
				// even if controller is plugged in and not being used it will still
				// be considered analog?
				new_controller.is_analog = true
				new_controller.is_connected = true

				LEFT_THUMB_DEADZONE :: 7849

				left_thumb_x := sdl.GameControllerGetAxis(v, sdl.GameControllerAxis.LEFTX)
				new_controller.stick_avg_x = process_controller_axis_value(
					left_thumb_x,
					LEFT_THUMB_DEADZONE,
				)

				left_thumb_y := sdl.GameControllerGetAxis(v, sdl.GameControllerAxis.LEFTY)
				new_controller.stick_avg_y = process_controller_axis_value(
					left_thumb_y,
					LEFT_THUMB_DEADZONE,
				)

				dpad_down := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_DOWN)
				dpad_up := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_UP)
				dpad_left := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_LEFT)
				dpad_right := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_RIGHT)

				if dpad_down == 1 {
					new_controller.stick_avg_y = -1
				}
				if dpad_up == 1 {
					new_controller.stick_avg_y = 1
				}
				if dpad_left == 1 {
					new_controller.stick_avg_x = -1
				}
				if dpad_right == 1 {
					new_controller.stick_avg_x = 1
				}

				threshold: f32 = 0.5
				process_controller_button_press(
					&old_controller.Move_left,
					&new_controller.Move_left,
					new_controller.stick_avg_x < -threshold ? 1 : 0,
				)
				process_controller_button_press(
					&old_controller.Move_right,
					&new_controller.Move_right,
					new_controller.stick_avg_x > threshold ? 1 : 0,
				)
				process_controller_button_press(
					&old_controller.Move_down,
					&new_controller.Move_down,
					new_controller.stick_avg_y < -threshold ? 1 : 0,
				)
				process_controller_button_press(
					&old_controller.Move_up,
					&new_controller.Move_up,
					new_controller.stick_avg_y > threshold ? 1 : 0,
				)

				// returns 1 for pressed, 0 for not
				down := sdl.GameControllerGetButton(v, sdl.GameControllerButton.A)
				process_controller_button_press(
					&old_controller.Action_down,
					&new_controller.Action_down,
					down,
				)

				right := sdl.GameControllerGetButton(v, sdl.GameControllerButton.B)
				process_controller_button_press(
					&old_controller.Action_right,
					&new_controller.Action_right,
					right,
				)

				left := sdl.GameControllerGetButton(v, sdl.GameControllerButton.X)
				process_controller_button_press(
					&old_controller.Action_left,
					&new_controller.Action_left,
					left,
				)

				up := sdl.GameControllerGetButton(v, sdl.GameControllerButton.Y)
				process_controller_button_press(
					&old_controller.Action_up,
					&new_controller.Action_up,
					up,
				)

				start := sdl.GameControllerGetButton(v, sdl.GameControllerButton.START)
				process_controller_button_press(
					&old_controller.Start,
					&new_controller.Start,
					start,
				)

				back := sdl.GameControllerGetButton(v, sdl.GameControllerButton.BACK)
				process_controller_button_press(&old_controller.Back, &new_controller.Back, back)
			}

			buffer := api.Game_offscreen_buffer {
				memory = p.surface.pixels,
				width  = p.surface.w,
				height = p.surface.h,
				pitch  = p.surface.pitch,
			}

			game_code.update_and_render(&game_memory, new_input, &buffer)

			if keys[sdl.SCANCODE_O] == 1 {
				debug_draw_vertical(&buffer, 100, 0, buffer.height, 0xFFFFFFFF)
			}

			// All work done, now measure how long its been
			work_seconds_elapsed: f32 = get_seconds_elapsed(
				last_counter,
				sdl.GetPerformanceCounter(),
				perf_count_frequency,
			)

			// Check if time passed matches target, if not delay for the remainder?
			seconds_elapsed_for_frame: f32 = work_seconds_elapsed
			if seconds_elapsed_for_frame < target_seconds_per_frame {
				sleep_ms := cast(u32)(1000.0 *
					(target_seconds_per_frame - seconds_elapsed_for_frame))
				if sleep_ms > 1 {
					sdl.Delay(sleep_ms - 1)
				}

				// case it under/overshoots, impl own "delay"
				for seconds_elapsed_for_frame < target_seconds_per_frame {
					seconds_elapsed_for_frame = get_seconds_elapsed(
						last_counter,
						sdl.GetPerformanceCounter(),
						perf_count_frequency,
					)
				}
			}

			// input swap
			temp := new_input
			new_input = old_input
			old_input = temp


			// roughly how many cpu cycles how elapsed
			end_cycle_count := intrinsics.read_cycle_counter()
			cycles_elapsed := end_cycle_count - last_cycle_count
			last_cycle_count = end_cycle_count

			// "wall clock" timer from os
			// how much real time passed
			end_counter := sdl.GetPerformanceCounter()
			counter_elapsed := end_counter - last_counter
			last_counter = end_counter

			mega_cycles_per_frame := f32(cycles_elapsed) / (1000 * 1000)
			ms_per_frame := (1000.0 * f32(counter_elapsed)) / f32(perf_count_frequency)
			fps := f32(perf_count_frequency) / f32(counter_elapsed)

			if frame % 60 == 0 {
				fmt.printfln(
					"%.2fms/f, %.2ff/s, %.2fmc/f",
					ms_per_frame,
					fps,
					mega_cycles_per_frame,
				)
			}

			sdl.UpdateWindowSurface(p.window)
			free_all(context.temp_allocator)
		}
	}
}

get_wall_clock :: proc() -> u64 {
	return sdl.GetPerformanceCounter()
}

get_seconds_elapsed :: proc(start, end, perf_count_frequency: u64) -> f32 {
	counter_elapsed := end - start
	result := ((f32(counter_elapsed)) / f32(perf_count_frequency))
	return result
}

process_controller_axis_value :: proc(v, deadzone: i16) -> (result: f32) {
	value := f32(v)
	deadzone_f := f32(deadzone)

	if v < -deadzone {
		result = (value + deadzone_f) / (32768.0 - deadzone_f)
	} else if v > deadzone {
		result = (value - deadzone_f) / (32767.0 - deadzone_f)
	}

	return
}


reset_controller_input :: proc(old_controller, new_controller: ^api.Game_controller_input) {
	previous_buttons := old_controller.Buttons

	new_controller^ = {}

	new_controller.is_connected = old_controller.is_connected

	for button, index in previous_buttons {
		new_controller.Buttons[index].ended_down = button.ended_down
	}
}

// @(private = "file") // this tag blocks from being found in zed (ctrl+t)
process_controller_button_press :: proc(
	old_state: ^api.Game_button_state,
	new_state: ^api.Game_button_state,
	pressed: u8,
) {
	new_state.ended_down = pressed == 1
	new_state.half_transition_count = old_state.ended_down != new_state.ended_down ? 1 : 0
}

process_keyboard_input :: proc(
	old_controller: ^api.Game_controller_input,
	new_controller: ^api.Game_controller_input,
	keys: [^]u8,
) {
	process_controller_button_press(
		&old_controller.Move_down,
		&new_controller.Move_down,
		keys[sdl.SCANCODE_S],
	)

	process_controller_button_press(
		&old_controller.Move_up,
		&new_controller.Move_up,
		keys[sdl.SCANCODE_W],
	)

	process_controller_button_press(
		&old_controller.Move_left,
		&new_controller.Move_left,
		keys[sdl.SCANCODE_A],
	)

	process_controller_button_press(
		&old_controller.Move_right,
		&new_controller.Move_right,
		keys[sdl.SCANCODE_D],
	)

	process_controller_button_press(
		&old_controller.Action_down,
		&new_controller.Action_down,
		keys[sdl.SCANCODE_DOWN],
	)

	process_controller_button_press(
		&old_controller.Action_up,
		&new_controller.Action_up,
		keys[sdl.SCANCODE_UP],
	)

	process_controller_button_press(
		&old_controller.Action_left,
		&new_controller.Action_left,
		keys[sdl.SCANCODE_LEFT],
	)

	process_controller_button_press(
		&old_controller.Action_right,
		&new_controller.Action_right,
		keys[sdl.SCANCODE_RIGHT],
	)

	process_controller_button_press(
		&old_controller.Left_Shoulder,
		&new_controller.Left_Shoulder,
		keys[sdl.SCANCODE_Q],
	)

	process_controller_button_press(
		&old_controller.Right_Shoulder,
		&new_controller.Right_Shoulder,
		keys[sdl.SCANCODE_E],
	)
}

resize_surface :: proc(p: ^Platform_SDL) {
	p.surface = sdl.GetWindowSurface(p.window)
	if p.surface == nil {
		panic(fmt.tprintf("Error creating surface: %s", sdl.GetError()))
	}
}

debug_platform_read_entire_file :: proc "c" (path: cstring) -> api.Debug_read_file_result {
	context = runtime.default_context()
	result: api.Debug_read_file_result
	path_string := string(path)

	if data, data_err := os.read_entire_file(path_string, context.allocator); data_err == nil {
		result.size = cast(u32)len(data)
		result.contents = raw_data(data)
	} else {
		fmt.eprintfln("Failed reading from '%s'. Error: %v", path_string, data_err)
	}

	return result
}

debug_platform_write_entire_file :: proc "c" (dst: cstring, filesize: u32, contents: rawptr) {
	context = runtime.default_context()
	bytes := ([^]byte)(contents)[:filesize]
	dst_string := string(dst)

	write_err := os.write_entire_file(dst_string, bytes)

	if write_err != nil {
		fmt.eprintfln("Failed writing '%s'. Error: %v", dst_string, write_err)
	}
}

debug_platform_free_file_memory :: proc "c" (memory: rawptr) {
	context = runtime.default_context()
	free(memory)
}


debug_draw_vertical :: proc(buffer: ^api.Game_offscreen_buffer, x, top, bottom: i32, color: u32) {
	if x < 0 || x >= buffer.width {
		return
	}

	top_clamped := top
	bottom_clamped := bottom

	if top_clamped < 0 {
		top_clamped = 0
	}

	if bottom_clamped > buffer.height {
		bottom_clamped = buffer.height
	}

	pixel := ([^]u8)(buffer.memory)
	fmt.printfln("%v", pixel)
	// next pixel
	// +1 byte  = next color aka. part of the same pixel
	// +4 bytes = next whole pixel (assuming start from the beginning of pixel)
	addr := ([^]u8)(uintptr(pixel) + 4)
	value := (^u32)(addr)^
	fmt.printfln("addr: %p, pixel: 0x%08X", addr, value)
	fmt.printfln("color: 0x%08X", color)
	pixel = ([^]u8)(uintptr(pixel) + uintptr(x * 4 + top_clamped * buffer.pitch))

	for y in top_clamped ..< bottom_clamped {
		(^u32)(pixel)^ = color
		pixel = ([^]u8)(uintptr(pixel) + uintptr(buffer.pitch))

	}
}
