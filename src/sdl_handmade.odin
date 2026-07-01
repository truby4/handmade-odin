package handmade

import "base:intrinsics"
import "core:fmt"
import sdl "vendor:sdl2"
import mix "vendor:sdl2/mixer"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

SDL_Platform :: struct {
	running:         bool,
	surface:         ^sdl.Surface,
	window:          ^sdl.Window,
	game_controller: ^sdl.GameController,
	music:           ^mix.Music,
}

resize_surface :: proc(s: ^SDL_Platform) {
	s.surface = sdl.GetWindowSurface(s.window)
	if s.surface == nil {
		panic(fmt.tprintf("Error creating surface: %s", sdl.GetError()))
	}
}

update_window :: proc(s: ^SDL_Platform) {
	sdl.UpdateWindowSurface(s.window)
}


main :: proc() {
	s := SDL_Platform{}
	s.running = true

	assert(
		sdl.Init(sdl.INIT_EVERYTHING) == 0,
		fmt.tprintf("Error initialising sdl: %s", sdl.GetError()),
	)
	defer sdl.Quit()

	s.window = sdl.CreateWindow(
		"Handmade Odin",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		sdl.WINDOW_SHOWN | sdl.WINDOW_RESIZABLE,
	)
	assert(s.window != nil, fmt.tprintf("Error creating window: %s", sdl.GetError()))
	defer sdl.DestroyWindow(s.window)

	num_joysticks := sdl.NumJoysticks()
	for i in 0 ..< sdl.NumJoysticks() {
		if sdl.IsGameController(i) {
			game_controller := sdl.GameControllerOpen(i)
			s.game_controller = game_controller
			break
		}
	}

	defer {
		if s.game_controller != nil {
			sdl.GameControllerClose(s.game_controller)
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

	resize_surface(&s)
	update_window(&s)

	event: sdl.Event
	x_offset: i32 = 0
	y_offset: i32 = 0

	perf_count_frequency: u64 = sdl.GetPerformanceFrequency()

	last_counter: u64 = sdl.GetPerformanceCounter()
	last_cycle_count: i64 = intrinsics.read_cycle_counter()
	fmt.printfln("%d", last_counter)

	main_loop: for s.running {
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				s.running = false
			case .WINDOWEVENT:
				if event.window.event == sdl.WindowEventID.RESIZED {
					resize_surface(&s)

				}
			case .KEYDOWN:
				key := event.key.keysym.sym
				#partial switch key {
				case sdl.Keycode.ESCAPE:
					s.running = false
				case sdl.Keycode.SPACE:
					if mix.PausedMusic() == 1 {
						mix.ResumeMusic()
					} else {
						mix.PauseMusic()
					}
				}
			}
		}

		keys := sdl.GetKeyboardState(nil)

		if keys[int(sdl.SCANCODE_W)] != 0 {
			y_offset += 2
		}
		if keys[int(sdl.SCANCODE_S)] != 0 {
			y_offset -= 2
		}
		if keys[int(sdl.SCANCODE_A)] != 0 {
			x_offset += 2
		}
		if keys[int(sdl.SCANCODE_D)] != 0 {
			x_offset -= 2
		}

		if s.game_controller != nil {
			stick_x := sdl.GameControllerGetAxis(s.game_controller, sdl.GameControllerAxis.LEFTX)
			stick_y := sdl.GameControllerGetAxis(s.game_controller, sdl.GameControllerAxis.LEFTY)

			x_offset += i32(stick_x) / 4096
			y_offset += i32(stick_y) / 4096
		}

		buffer := Game_offscreen_buffer {
			memory = s.surface.pixels,
			width  = s.surface.w,
			height = s.surface.h,
			pitch  = s.surface.pitch,
		}

		game_update_and_render(&buffer, x_offset, y_offset)

		update_window(&s)

		end_cycle_count := intrinsics.read_cycle_counter()
		end_counter := sdl.GetPerformanceCounter()

		cycles_elapsed: i64 = end_cycle_count - last_cycle_count
		counter_elapsed: u64 = end_counter - last_counter

		ms_per_frame: f32 = (1000.0 * f32(counter_elapsed)) / f32(perf_count_frequency)
		fps: f32 = f32(perf_count_frequency) / f32(counter_elapsed)

		mega_cycles_per_frame := cast(f32)cycles_elapsed / (1000 * 1000)

		last_counter = end_counter
		last_cycle_count = end_cycle_count

		free_all(context.temp_allocator)
	}

}
