package handmade

import "base:intrinsics"
import "core:fmt"
import sdl "vendor:sdl2"
import mix "vendor:sdl2/mixer"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

@(private = "file")
Platform_SDL :: struct {
	running:          bool,
	surface:          ^sdl.Surface,
	window:           ^sdl.Window,
	game_controllers: [4]^sdl.GameController, // added 4 to be the max number of controllers? waste of memory?
	music:            ^mix.Music,
}

@(private = "file")
resize_surface :: proc(p: ^Platform_SDL) {
	p.surface = sdl.GetWindowSurface(p.window)
	if p.surface == nil {
		panic(fmt.tprintf("Error creating surface: %s", sdl.GetError()))
	}
}

main :: proc() {
	p := Platform_SDL{}
	p.running = true

	assert(
		sdl.Init(sdl.INIT_EVERYTHING) == 0,
		fmt.tprintf("Error initialising sdl: %s", sdl.GetError()),
	)
	defer sdl.Quit()

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
			break
		}
	}

	// defer {
	// 	if p.game_controller != nil {
	// 		sdl.GameControllerClose(p.game_controller)
	// 	}
	// }


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
	input: [2]Game_input = {}
	new_input: ^Game_input = &input[0]
	old_input: ^Game_input = &input[1]

	perf_count_frequency: u64 = sdl.GetPerformanceFrequency()

	last_counter: u64 = sdl.GetPerformanceCounter()
	last_cycle_count: i64 = intrinsics.read_cycle_counter()
	fmt.printfln("%d", last_counter)

	main_loop: for p.running {

		@(static) frame := 0
		frame += 1

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
				case sdl.Keycode.SPACE:
					fmt.printfln("Frame: %d, space button", frame)
					if mix.PausedMusic() == 1 {
						mix.ResumeMusic()
					} else {
						mix.PauseMusic()
					}
				}
			}
		}

		// keys := sdl.GetKeyboardState(nil)

		// if keys[int(sdl.SCANCODE_W)] != 0 {
		// 	fmt.printfln("Frame: %d, code: %d", frame, sdl.SCANCODE_W)
		// 	// y_offset += 2
		// }
		// if keys[int(sdl.SCANCODE_S)] != 0 {
		// 	// y_offset -= 2
		// }
		// if keys[int(sdl.SCANCODE_A)] != 0 {
		// 	// x_offset += 2
		// }
		// if keys[int(sdl.SCANCODE_D)] != 0 {
		// 	// x_offset -= 2
		// }

		for v, i in p.game_controllers {

			old_controller: ^Game_controller_input = &old_input.Controllers[i]
			new_controller: ^Game_controller_input = &new_input.Controllers[i]

			// the way im trying to copy from casey, this will mean
			// even if controller is plugged in and not being used it will still
			// be considered analog?
			new_controller.is_analog = true
			new_controller.start_x = old_controller.end_x
			new_controller.start_y = old_controller.end_y

			left_thumb_x := sdl.GameControllerGetAxis(v, sdl.GameControllerAxis.LEFTX)
			x: f32
			if left_thumb_x > 0 {
				x = cast(f32)left_thumb_x / 32768
			} else {
				x = cast(f32)left_thumb_x / 32767
			}
			new_controller.min_x = x
			new_controller.max_x = x
			new_controller.end_x = x


			left_thumb_y := sdl.GameControllerGetAxis(v, sdl.GameControllerAxis.LEFTY)
			y: f32
			if left_thumb_y > 0 {
				y = cast(f32)left_thumb_x / 32768
			} else {
				y = cast(f32)left_thumb_y / 32767
			}
			new_controller.min_y = y
			new_controller.max_y = y
			new_controller.end_y = y

			// returns 1 for pressed, 0 for not
			down := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_DOWN)
			process_button_press(&old_controller.Down, &new_controller.Down, down)
		}

		buffer := Game_offscreen_buffer {
			memory = p.surface.pixels,
			width  = p.surface.w,
			height = p.surface.h,
			pitch  = p.surface.pitch,
		}

		game_update_and_render(new_input, &buffer)

		sdl.UpdateWindowSurface(p.window)

		end_cycle_count := intrinsics.read_cycle_counter()
		end_counter := sdl.GetPerformanceCounter()

		cycles_elapsed: i64 = end_cycle_count - last_cycle_count
		counter_elapsed: u64 = end_counter - last_counter

		ms_per_frame: f32 = (1000.0 * f32(counter_elapsed)) / f32(perf_count_frequency)
		fps: f32 = f32(perf_count_frequency) / f32(counter_elapsed)

		mega_cycles_per_frame := cast(f32)cycles_elapsed / (1000 * 1000)

		last_counter = end_counter
		last_cycle_count = end_cycle_count

		temp := new_input
		new_input = old_input
		old_input = temp

		free_all(context.temp_allocator)
	}

}

@(private = "file")
process_button_press :: proc(
	old_state: ^Game_button_state,
	new_state: ^Game_button_state,
	pressed: u8,
) {
	new_state.ended_down = pressed == 1
	new_state.half_transition_count = old_state.ended_down != new_state.ended_down ? 1 : 0
}
