package platform

import api "../shared"
import "base:intrinsics"
import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:os"
import "core:time"
import sdl "vendor:sdl2"
import mix "vendor:sdl2/mixer"

WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540

GAME_CODE_SO :: "build/libhandmade.so"
GAME_CODE_TEMP_SO :: "build/libhandmade_temp.so"

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
	running:      bool,
	surface:      ^sdl.Surface,
	window:       ^sdl.Window,
	input_system: ^Input_System,
	music:        ^mix.Music,
}

global_pause := false

main :: proc() {
	config: Config
	flags.parse_or_exit(&config, os.args)

	context.logger = log.create_console_logger()

	p := Platform_SDL{}
	p.running = true

	base_address: uintptr

	if config.internal {
		base_address = cast(uintptr)Terabytes(2)
	} else {
		base_address = 0
	}


	replay := Replay_State{}
	thread := api.Thread_Context{}

	game_memory: api.Game_Memory
	game_memory.permanent_storage_size = Megabytes(64)
	game_memory.transient_storage_size = Gigabytes(1)

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

	log.info("Game memory initialised")
	log.infof("Permanent storage: %p", game_memory.permanent_storage)
	log.infof("Transient storage: %p", game_memory.transient_storage)

	replay_init(&replay, total_size, game_memory.permanent_storage)

	game_code, ok := load_game_code("build/libhandmade.so", "build/libhandmade_temp.so")
	if ok {
		log.info("Game code loaded")
	} else {
		log.warn("Unable to load game code; using stub")
	}
	defer unload_game_code(&game_code)

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
		sdl.WINDOW_SHOWN, // for prototyping taking out resizable
	)
	assert(p.window != nil, fmt.tprintf("Error creating window: %s", sdl.GetError()))
	defer sdl.DestroyWindow(p.window)

	// monitor_refresh_hz := get_monitor_refresh_rate(p.window)
	monitor_refresh_hz := 30
	game_update_hz := monitor_refresh_hz
	target_seconds_per_frame := 1.0 / cast(f32)game_update_hz

	p.input_system = input_system_init()

	if mix.OpenAudio(48000, sdl.AUDIO_S16SYS, 2, 1024) < 0 {
		log.errorf("Mixer error: %s", mix.GetError())
	}
	defer mix.CloseAudio()

	music := mix.LoadMUS("src/data/wonders_of_the_earth.mp3")
	if music == nil {
		log.errorf("Load music error: %s", mix.GetError())
	}
	defer mix.FreeMusic(music)

	mix.PlayMusic(music, -1)

	resize_surface(&p)
	sdl.UpdateWindowSurface(p.window)

	event: sdl.Event

	// pointer swap shit for thee game inputs
	input: [2]api.Game_Input = {}
	new_input: ^api.Game_Input = &input[0]
	old_input: ^api.Game_Input = &input[1]


	perf_count_frequency: u64 = sdl.GetPerformanceFrequency()

	last_counter: u64 = sdl.GetPerformanceCounter()
	last_cycle_count: i64 = intrinsics.read_cycle_counter()

	main_loop: for p.running {
		new_input.dt_for_frame = target_seconds_per_frame

		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				p.running = false
			case .WINDOWEVENT:
				#partial switch event.window.event {
				case .RESIZED:
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
				case sdl.Keycode.SEMICOLON:
					if config.internal {
						build_game_code()
					}
				case sdl.Keycode.L:
					if event.key.repeat == 0 {
						if replay.recording_index != 0 {
							end_recording(&replay)

							if begin_playback(&replay, 1) {
								log.info("Playback started")
							}
						} else if replay.playing_index != 0 {
							end_playback(&replay)
							log.info("Playback stopped")
						} else {
							if begin_recording(&replay, 1) {
								log.info("Recording started")
							}
						}
					}

				}
			}
		}

		info, err := os.stat(GAME_CODE_SO, context.temp_allocator)

		if err == nil {
			defer os.file_info_delete(info, context.temp_allocator)

			if info.modification_time != game_code.last_so_build_time {
				unload_game_code(&game_code)

				game_code, ok = load_game_code(GAME_CODE_SO, GAME_CODE_TEMP_SO)
				if ok {
					log.info("Game code reloaded")
				} else {
					log.warn("Unable to load game code; using stub")
				}
			}
		}


		if (!global_pause) {

			@(static) frame := 0
			frame += 1

			collect_game_input(p.input_system, old_input, new_input)

			buffer := api.Game_Offscreen_Buffer {
				memory = p.surface.pixels,
				width  = p.surface.w,
				height = p.surface.h,
				pitch  = p.surface.pitch,
			}

			if replay.recording_index != 0 {
				if !record_input(&replay, new_input) {
					end_recording(&replay)
				}
			}

			if replay.playing_index != 0 {
				if !playback_input(&replay, new_input) {
					log.error("Playback failed")
				}
			}

			game_code.update_and_render(&thread, &game_memory, new_input, &buffer)

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

			if frame % 120 == 0 {
				fmt.printfln(
					"%.2fms/f, %.2ff/s, %.2fmc/f",
					ms_per_frame,
					fps,
					mega_cycles_per_frame,
				)
			}

			sdl.UpdateWindowSurface(p.window)
		}
		free_all(context.temp_allocator)
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

resize_surface :: proc(p: ^Platform_SDL) {
	p.surface = sdl.GetWindowSurface(p.window)
	if p.surface == nil {
		panic(fmt.tprintf("Error creating surface: %s", sdl.GetError()))
	}
}

debug_platform_read_entire_file :: proc "c" (
	thread: ^api.Thread_Context,
	path: string,
) -> api.Debug_Read_File_Result {
	context = runtime.default_context()
	result: api.Debug_Read_File_Result
	path_string := string(path)

	if data, data_err := os.read_entire_file(path_string, context.allocator); data_err == nil {
		result.size = cast(u32)len(data)
		result.contents = raw_data(data)
	} else {
		log.errorf("Failed reading from '%s'. Error: %v", path_string, data_err)
	}

	return result
}

debug_platform_write_entire_file :: proc "c" (
	thread: ^api.Thread_Context,
	dst: string,
	filesize: u32,
	contents: rawptr,
) {
	context = runtime.default_context()
	bytes := ([^]byte)(contents)[:filesize]
	dst_string := string(dst)

	write_err := os.write_entire_file(dst_string, bytes)

	if write_err != nil {
		log.errorf("Failed writing '%s'. Error: %v", dst_string, write_err)
	}
}

debug_platform_free_file_memory :: proc "c" (thread: ^api.Thread_Context, memory: rawptr) {
	context = runtime.default_context()
	free(memory)
}


debug_draw_vertical :: proc(buffer: ^api.Game_Offscreen_Buffer, x, top, bottom: i32, color: u32) {
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

get_monitor_refresh_rate :: proc(window: ^sdl.Window) -> int {
	DEFAULT_REFRESH_HZ :: 60

	display_index := sdl.GetWindowDisplayIndex(window)
	if display_index < 0 {
		log.warnf(
			"Unable to determine window display: %s; using %d Hz",
			sdl.GetError(),
			DEFAULT_REFRESH_HZ,
		)
		return DEFAULT_REFRESH_HZ
	}

	display_mode: sdl.DisplayMode
	if sdl.GetCurrentDisplayMode(display_index, &display_mode) != 0 {
		log.warnf(
			"Unable to query display mode: %s; using %d Hz",
			sdl.GetError(),
			DEFAULT_REFRESH_HZ,
		)
		return DEFAULT_REFRESH_HZ
	}

	if display_mode.refresh_rate <= 0 {
		log.warnf("Display refresh rate is unspecified; using %d Hz", DEFAULT_REFRESH_HZ)
		return DEFAULT_REFRESH_HZ
	}

	log.infof("Display refresh rate: %d Hz", display_mode.refresh_rate)
	return int(display_mode.refresh_rate)
}
