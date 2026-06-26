package main

import "core:fmt"
import sdl "vendor:sdl2"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

Game :: struct {
	running: bool,
	// `^sdl.Surface.pixels` for window surface is essentially the backbuffer
	// sdl.UpdateWindowSurface will then apply the buffer
	surface: ^sdl.Surface,
	window:  ^sdl.Window,
}


resize_surface :: proc(g: ^Game) {

	if g.surface != nil {
		sdl.FreeSurface(g.surface)
		g.surface = nil
	}

	g.surface = sdl.GetWindowSurface(g.window)

	w := g.surface.w
	h := g.surface.h

	pitch := w * 4

	if g.surface == nil {
		panic(fmt.tprintf("Error creating surface: %s", sdl.GetError()))
	}

	pixels := cast([^]u32)(g.surface.pixels)
	for i in 0 ..< w * h {
		pixels[i] = sdl.MapRGB(g.surface.format, 255, 0, 0)
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

	main_loop: for g.running {
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				g.running = false
			case .WINDOWEVENT:
				if event.window.event == sdl.WindowEventID.RESIZED {
					resize_surface(&g)
					update_window(&g)
				}
			}
		}
	}
}
