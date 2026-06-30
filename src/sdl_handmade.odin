package handmade

import "base:intrinsics"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl2"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

// TODO(atruby) Rename to something more appropriate
// "SDL_Platform?"
Game :: struct {
	running:         bool,
	surface:         ^sdl.Surface,
	window:          ^sdl.Window,
	audio_device_id: sdl.AudioDeviceID,
	audio_state:     Audio_State,
	audio_pause_on:  bool,
}


resize_surface :: proc(g: ^Game) {
	g.surface = sdl.GetWindowSurface(g.window)
	if g.surface == nil {
		panic(fmt.tprintf("Error creating surface: %s", sdl.GetError()))
	}
}

update_window :: proc(g: ^Game) {
	sdl.UpdateWindowSurface(g.window)
}


main :: proc() {
	g := Game{}
	g.running = true

	assert(
		sdl.Init(sdl.INIT_EVERYTHING) == 0,
		fmt.tprintf("Error initialising sdl: %s", sdl.GetError()),
	)
	defer sdl.Quit()

	g.window = sdl.CreateWindow(
		"Handmade Odin",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		sdl.WINDOW_SHOWN | sdl.WINDOW_RESIZABLE,
	)
	assert(g.window != nil, fmt.tprintf("Error creating window: %s", sdl.GetError()))
	defer sdl.DestroyWindow(g.window)

	init_audio(&g)
	defer {
		if g.audio_device_id != 0 {
			sdl.CloseAudioDevice(g.audio_device_id)
		}
	}

	resize_surface(&g)
	update_window(&g)

	event: sdl.Event
	x_offset: i32 = 0
	y_offset: i32 = 0

	perf_count_frequency: u64 = sdl.GetPerformanceFrequency()

	last_counter: u64 = sdl.GetPerformanceCounter()
	last_cycle_count: i64 = intrinsics.read_cycle_counter()
	fmt.printfln("%d", last_counter)

	main_loop: for g.running {

		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				g.running = false
			case .WINDOWEVENT:
				if event.window.event == sdl.WindowEventID.RESIZED {
					resize_surface(&g)

				}
			case .KEYDOWN:
				key := event.key.keysym.sym
				// Only handles one key at a time??
				#partial switch key {
				case sdl.Keycode.ESCAPE:
					fmt.println("ESCAPE")
				case sdl.Keycode.SPACE:
					g.audio_pause_on = audio_pause_device(g.audio_device_id, !g.audio_pause_on)
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

		buffer: game_offscreen_buffer
		buffer.memory = g.surface.pixels
		buffer.width = g.surface.w
		buffer.height = g.surface.h
		buffer.pitch = g.surface.pitch

		game_update_and_render(&buffer, x_offset, y_offset)
		update_window(&g)

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
	samples_per_second:      i32, // hz or per second
	tone_hz:                 i32,
	tone_volume:             i16,
	running_sample_index:    u32,
	square_wave_period:      i32,
	half_square_wave_period: i32,
	t_sine:                  f32,
}

init_audio :: proc(g: ^Game) {
	g.audio_state = Audio_State {
		samples_per_second   = 48000,
		tone_hz              = 256,
		tone_volume          = 3000,
		running_sample_index = 0,
	}
	g.audio_state.square_wave_period = g.audio_state.samples_per_second / g.audio_state.tone_hz
	g.audio_state.half_square_wave_period = g.audio_state.square_wave_period / 2

	desired := sdl.AudioSpec {
		freq     = g.audio_state.samples_per_second,
		format   = sdl.AUDIO_S16,
		channels = 2, /**< Number of channels: 1 mono, 2 stereo */
		samples  = 1024,
		callback = audio_callback,
		userdata = &g.audio_state,
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
audio_pause_device :: proc(audio_device_id: sdl.AudioDeviceID, pause_on: bool) -> bool {
	sdl.PauseAudioDevice(audio_device_id, sdl.bool(pause_on))
	return pause_on
}


audio_callback :: proc "c" (userdata: rawptr, stream: [^]u8, len: i32) {
	audio := cast(^Audio_State)userdata

	bytes_per_sample := size_of(i16) * 2 // left + right
	sample_count := len / cast(i32)bytes_per_sample

	sample_out := cast([^]i16)stream

	for sample_index in 0 ..< sample_count {

		sine_value := math.sin(audio.t_sine)
		sample_value := i16(sine_value * f32(audio.tone_volume))

		audio.t_sine += (2.0 * math.PI) / f32(audio.square_wave_period)

		sample_out[0] = sample_value // left
		sample_out[1] = sample_value // right
		sample_out = sample_out[2:]

		audio.running_sample_index += 1
	}
}
