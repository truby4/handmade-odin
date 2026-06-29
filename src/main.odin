package main

import "base:intrinsics"
import "core:fmt"
import sdl "vendor:sdl2"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

Game :: struct {
	running:         bool,
	surface:         ^sdl.Surface,
	window:          ^sdl.Window,
	audio_device_id: sdl.AudioDeviceID,
	audio_state:     Audio_State,
	audio_pause_on:  bool,
}

render_weird_gradient :: proc(buffer: ^sdl.Surface, blue_offset, green_offset: i32) {
	width := buffer.w
	height := buffer.h
	pitch := buffer.pitch

	row := ([^]u8)(buffer.pixels)

	for y in 0 ..< height {
		pixel := ([^]u32)(row)

		for x in 0 ..< width {
			blue := u8(x + blue_offset)
			green := u8(y + green_offset)

			pixel[x] = (u32(green) << 8) | u32(blue)
		}

		row = ([^]u8)(uintptr(row) + uintptr(pitch))
	}
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

		render_weird_gradient(g.surface, x_offset, y_offset)
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
