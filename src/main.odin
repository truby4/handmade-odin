package main

import "core:fmt"
import "core:os"
import sdl "vendor:sdl2"

//Screen consts
WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

//Colors
BLACK :: u32(0x00000000)
WHITE :: u32(0xFFFFFFFF)


main :: proc() {
	assert(
		sdl.Init(sdl.INIT_EVERYTHING) == 0,
		fmt.tprintf("Error initialising sdl: %s", sdl.GetError()),
	)

	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Hello",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		sdl.WINDOW_SHOWN,
	)
	assert(window != nil, fmt.tprintf("Error creating window: %s", sdl.GetError()))
	defer sdl.DestroyWindow(window)

	event: sdl.Event
	running := true

	for running {
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				fmt.println("Quitting")
				os.exit(1)
			case .KEYDOWN:
				fmt.println("KEYDOWN EVENT")
			case .KEYUP:
				fmt.println("KEYUP EVENT")
			case .DISPLAYEVENT:
				fmt.printfln(
					"DISPLAY EVENT: event=%v data1=%v",
					event.display.event,
					event.display.data1,
				)
			case .WINDOWEVENT:
				fmt.printfln(
					"WINDOW EVENT: type=%v data1=%v data2=%v event=%v windowID=%v",
					event.window.type,
					event.window.data1,
					event.window.data2,
					event.window.event,
					event.window.windowID,
				)
			case:
				fmt.println(event.type)
			}

			surface := sdl.GetWindowSurface(window)
			if surface == nil {
				panic(fmt.tprintf("Error creating surface: %s", sdl.GetError()))
			}

			@(static) color: u32

			if color == WHITE {
				color = BLACK
			} else {
				color = WHITE
			}

			sdl.FillRect(surface, nil, color)
			sdl.UpdateWindowSurface(window)
		}
	}
}
