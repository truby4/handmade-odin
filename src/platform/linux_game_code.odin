package platform

import "core:dynlib"
import "core:fmt"
import "core:os"
import api "../shared"

Game_code :: struct {
	library:          dynlib.Library,
	update_and_render: api.Game_update_and_render,
}

game_update_and_render_stub :: proc "c" (
	memory: ^api.Game_memory,
	input: ^api.Game_input,
	buffer: ^api.Game_offscreen_buffer,
) {
}

load_game_code :: proc(source_path, temp_path: string) -> (Game_code, bool) {
	result := Game_code {
		update_and_render = game_update_and_render_stub,
	}

	if err := os.copy_file(temp_path, source_path); err != nil {
		fmt.eprintfln("Unable to copy game library; %v", err)
		return result, false
	}

	library, ok := dynlib.load_library(temp_path)
	if !ok {
		fmt.eprintfln(
			"Unable to load game code from %q: %s",
			temp_path,
			dynlib.last_error(),
		)
		return result, false
	}

	symbol, found := dynlib.symbol_address(
		library,
		"Game_update_and_render",
	)

	if !found {
		fmt.eprintfln(
			"Unable to find Game_update_and_render: %s",
			dynlib.last_error(),
		)

		dynlib.unload_library(library)
		return result, false
	}

	result.library = library
	result.update_and_render =
		transmute(api.Game_update_and_render)symbol

	return result, true
}

unload_game_code :: proc(game_code: ^Game_code) {
	if game_code.library != nil {
		if !dynlib.unload_library(game_code.library) {
			fmt.eprintfln(
				"Unable to unload game code: %s",
				dynlib.last_error(),
			)
		}
	}

	game_code.library = nil
	game_code.update_and_render = game_update_and_render_stub
}
