package platform

import api "../shared"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"
import "core:log"

Game_code :: struct {
	library:            dynlib.Library,
	last_so_build_time: time.Time,
	update_and_render:  api.game_update_and_render,
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

	info, err := os.stat(source_path, context.temp_allocator)
	if err != nil {
		log.errorf("Unable to stat game code %q: %v", source_path, err)
		return result, false
	}
	defer os.file_info_delete(info, context.temp_allocator)


	if err := os.copy_file(temp_path, source_path); err != nil {
		log.errorf("Unable to copy game library; %v", err)
		return result, false
	}

	library, ok := dynlib.load_library(temp_path)
	if !ok {
		log.errorf("Unable to load game code from %q: %s", temp_path, dynlib.last_error())
		return result, false
	}

	symbol, found := dynlib.symbol_address(library, "game_update_and_render")

	if !found {
		log.errorf("Unable to find game_update_and_render: %s", dynlib.last_error())

		dynlib.unload_library(library)
		return result, false
	}

	result.library = library
	result.update_and_render = transmute(api.game_update_and_render)symbol
	result.last_so_build_time = info.modification_time

	return result, true
}

unload_game_code :: proc(game_code: ^Game_code) {
	if game_code.library != nil {
		if !dynlib.unload_library(game_code.library) {
			log.errorf("Unable to unload game code: %s", dynlib.last_error())
		}
	}

	game_code.library = nil
	game_code.update_and_render = game_update_and_render_stub
}

build_game_code :: proc() -> bool {
	description := os.Process_Desc {
		command = []string{"bash", "scripts/build_game_code.sh"},
	}

	state, stdout, stderr, err := os.process_exec(description, context.temp_allocator)

	if len(stdout) > 0 {
		fmt.print(string(stdout))
	}

	if len(stderr) > 0 {
		fmt.eprint(string(stderr))
	}

	if err != nil {
		log.errorf("Unable to execute game build: %v", err)
		return false
	}

	if state.exit_code != 0 {
		log.errorf("Game build failed with exit code %d", state.exit_code)
		return false
	}

	return true
}
