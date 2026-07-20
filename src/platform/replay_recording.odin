package platform

import api "../shared"
import "core:log"
import "core:os"

Replay_State :: struct {
	total_memory_size: u64,
	game_memory_block: rawptr,
	recording_file:    ^os.File,
	playing_file:      ^os.File,
	recording:         bool,
	playing:           bool,
}

// helper for viewing raw memory as bytes
memory_bytes :: proc(state: ^Replay_State) -> []u8 {
	return ([^]u8)(state.game_memory_block)[:int(state.total_memory_size)]
}

begin_recording :: proc(state: ^Replay_State) -> bool {
	file, err := os.create("build/handmade.hmi")
	if err != nil {
		log.errorf("Could not create recording: %v", err)
		return false
	}

	snapshot := memory_bytes(state)
	written, write_err := os.write(file, snapshot)

	if write_err != nil || written != len(snapshot) {
		log.errorf("Could not write memory snapshot: %v", write_err)
		os.close(file)
		return false
	}

	state.recording_file = file
	state.recording = true
	return true
}

end_recording :: proc(state: ^Replay_State) {
	if state.recording_file != nil {
		if err := os.close(state.recording_file); err != nil {
			log.errorf("Could not close recording: %v", err)
		}
	}

	state.recording_file = nil
	state.recording = false
}

record_input :: proc(state: ^Replay_State, input: ^api.Game_input) -> bool {
	written, err := os.write_ptr(state.recording_file, input, size_of(api.Game_input))
	if err != nil || written != size_of(api.Game_input) {
		log.errorf("Could not record input frame: %v", err)
		return false
	}

	return true
}

begin_playback :: proc(state: ^Replay_State) -> bool {
	file, err := os.open("build/handmade.hmi", {.Read})
	if err != nil {
		log.errorf("Could not open recording: %v", err)
		return false
	}

	snapshot := memory_bytes(state)
	read, read_err := os.read_full(file, snapshot)

	if read_err != nil || read != len(snapshot) {
		log.errorf("Could not restore memory snapshot: %v", read_err)
		os.close(file)
		return false
	}

	state.playing_file = file
	state.playing = true
	return true
}


end_playback :: proc(state: ^Replay_State) {
	if state.playing_file != nil {
		if err := os.close(state.playing_file); err != nil {
			log.errorf("Could not close playback: %v", err)
		}
	}

	state.playing_file = nil
	state.playing = false
}

playback_input :: proc(
    state: ^Replay_State,
    input: ^api.Game_input,
) -> bool {
    input_size := size_of(api.Game_input)

    bytes_read, err := os.read_full(
        state.playing_file,
        ([^]u8)(input)[:input_size],
    )

    if bytes_read == input_size {
        return true
    }

    // reopen the file, restore memory, then read frame zero.
    end_playback(state)

    if !begin_playback(state) {
        return false
    }

    bytes_read, err = os.read_full(
        state.playing_file,
        ([^]u8)(input)[:input_size],
    )

    if err != nil || bytes_read != input_size {
        log.errorf("Could not read first replay frame: %v", err)
        end_playback(state)
        return false
    }

    return true
}
