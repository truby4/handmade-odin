package main

import "core:fmt"
import sdl "vendor:sdl2"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

Game :: struct {
	running: bool,
	surface: ^sdl.Surface,
	window:  ^sdl.Window,
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

	resize_surface(&g)
	update_window(&g)

	event: sdl.Event
	x_offset: i32 = 0
	y_offset: i32 = 0

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
	}
}
