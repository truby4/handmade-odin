package main

import "core:fmt"
import sdl "vendor:sdl2"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

//Colors
BLACK :: u32(0x00000000)
WHITE :: u32(0xFFFFFFFF)
RED :: u32(0xFF0000FF)
BLUE :: u32(0x0000FFFF)

Game :: struct {
	running:        bool,
	backbuffer:     ^sdl.Surface,
	window_surface: ^sdl.Surface,
	window:         ^sdl.Window,
}

resize_surface :: proc(g: ^Game, w, h: i32) {
	if g.backbuffer != nil {
		sdl.FreeSurface(g.backbuffer)
		g.backbuffer = nil
	}

	format := g.window_surface.format.format

	g.backbuffer = sdl.CreateRGBSurfaceWithFormat(0, w, h, 32, format)

	if g.backbuffer == nil {
		panic(fmt.tprintf("Error creating backbuffer: %s", sdl.GetError()))
	}
}

update_window :: proc(g: ^Game) {
	sdl.BlitSurface(g.backbuffer, nil, g.window_surface, nil)
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

	g.window_surface = sdl.GetWindowSurface(g.window)
	if g.window_surface == nil {
		panic(fmt.tprintf("Error getting window surface: %s", sdl.GetError()))
	}

	resize_surface(&g, WINDOW_WIDTH, WINDOW_HEIGHT)
	defer sdl.FreeSurface(g.backbuffer)


	// loop
	event: sdl.Event
	color := BLUE

	for g.running {
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				g.running = false
			case .KEYDOWN:
				if color == BLUE {
					color = RED
				} else {
					color = BLUE
				}
			case .WINDOWEVENT:
				if event.window.event == sdl.WindowEventID.RESIZED {
					g.window_surface = sdl.GetWindowSurface(g.window)
					resize_surface(&g, event.window.data1, event.window.data2)
				}
			}
		}
		sdl.FillRect(g.backbuffer, nil, color)
		update_window(&g)
	}
}
