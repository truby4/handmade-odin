package handmade

import "base:intrinsics"
import "core:fmt"
import sdl "vendor:sdl2"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

SDL_Platform :: struct {
	running:           bool,
	surface:           ^sdl.Surface,
	window:            ^sdl.Window,
	game_controller:   ^sdl.GameController,
	using audio_state: Audio_State,
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

	init_audio(&s)
	defer {
		if s.audio_device_id != 0 {
			sdl.CloseAudioDevice(s.audio_device_id)
		}
	}

	audio_samples := make([]i16, 48000 / 30 * 2)
	defer delete(audio_samples)

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
				// Only handles one key at a time??
				#partial switch key {
				case sdl.Keycode.ESCAPE:
					fmt.println("ESCAPE")
				case sdl.Keycode.SPACE:
					s.audio_pause_on = audio_pause_device(s.audio_device_id, !s.audio_pause_on)
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

		sound_buffer := Game_sound_output_buffer {
			samples_per_second = s.audio_state.samples_per_second,
			sample_count       = s.audio_state.samples_per_second / 30,
			samples            = raw_data(audio_samples),
		}

		buffer := Game_offscreen_buffer {
			memory = s.surface.pixels,
			width  = s.surface.w,
			height = s.surface.h,
			pitch  = s.surface.pitch,
		}

		game_update_and_render(&buffer, x_offset, y_offset, &sound_buffer, s.audio_state.tone_hz)

		byte_count := sound_buffer.sample_count * 2 * size_of(i16)
		sdl.QueueAudio(s.audio_device_id, rawptr(sound_buffer.samples), u32(byte_count))

		update_window(&s)


		end_cycle_count := intrinsics.read_cycle_counter()
		end_counter := sdl.GetPerformanceCounter()

		// This is rdtsc (rough cpu cycle measure from cpu)
		cycles_elapsed: i64 = end_cycle_count - last_cycle_count
		// This is based on queryperformacnecounter - asks OS to the
		// best of knowledge whats the wall clock time
		counter_elapsed: u64 = end_counter - last_counter

		// perf count frequency is the count per second so multiplying
		// counter elapsed by 1000
		// 3 ms = (1000 * 3360459) / 1000000000 .. the billion is the frequency
		// so one count = one nanosecond
		ms_per_frame: f32 = (1000.0 * f32(counter_elapsed)) / f32(perf_count_frequency)
		fps: f32 = f32(perf_count_frequency) / f32(counter_elapsed)

		mega_cycles_per_frame := cast(f32)cycles_elapsed / (1000 * 1000)

		// ms/f   = milliseconds per frame
		// f/s    = frames per second
		// mc/f   = mega cycles per frame
		fmt.printfln("%.2fms/f, %.2ff/s, %.2fmc/f", ms_per_frame, fps, mega_cycles_per_frame)

		last_counter = end_counter
		last_cycle_count = end_cycle_count

		free_all(context.temp_allocator)
	}

}


Audio_State :: struct {
	samples_per_second:   i32, // hz or per second
	tone_hz:              i32,
	tone_volume:          i16,
	running_sample_index: u32,
	audio_pause_on:       bool,
	audio_device_id:      sdl.AudioDeviceID,
}

init_audio :: proc(g: ^SDL_Platform) {
	g.audio_state = Audio_State {
		samples_per_second   = 48000,
		tone_hz              = 256,
		tone_volume          = 3000,
		running_sample_index = 0,
	}

	desired := sdl.AudioSpec {
		freq     = g.audio_state.samples_per_second,
		format   = sdl.AUDIO_S16,
		channels = 2, /**< Number of channels: 1 mono, 2 stereo */
		samples  = 1024,
		callback = nil,
	}

	obtained: sdl.AudioSpec

	audio_device_id := sdl.OpenAudioDevice(
		nil,
		false,
		&desired,
		&obtained,
		sdl.AUDIO_ALLOW_ANY_CHANGE,
	)
	if audio_device_id == 0 {
		fmt.printfln("Error opening audio device: %s", sdl.GetError())
		return
	}
	g.audio_device_id = audio_device_id

	fmt.printfln(
		"Audio opened: device_id=%d freq=%d channels=%d samples=%d",
		cast(u32)g.audio_device_id,
		obtained.freq,
		obtained.channels,
		obtained.samples,
	)

	sdl.PauseAudioDevice(audio_device_id, sdl.bool(g.audio_pause_on))
}

// returns new pause_on state to store in game
// the pausing is overcomplicated !pause_on pause_on wtf.
audio_pause_device :: proc(audio_device_id: sdl.AudioDeviceID, pause_on: bool) -> bool {
	if audio_device_id != 0 {
		sdl.PauseAudioDevice(audio_device_id, sdl.bool(pause_on))
		return pause_on
	}
	return !pause_on
}
