package platform

import api "../shared"
import "core:fmt"
import "core:log"
import "core:os"

REPLAY_BUFFER_COUNT :: 4

Replay_State :: struct {
	total_memory_size: u64,
	game_memory_block: rawptr,
	recording_file:    ^os.File,
	playing_file:      ^os.File,
	recording_index:   int,
	playing_index:     int,
}

memory_bytes :: proc(state: ^Replay_State) -> []u8 {
	return ([^]u8)(state.game_memory_block)[:int(state.total_memory_size)]
}

replay_path :: proc(index: int) -> string {
	return fmt.tprintf("build/loop_edit_%d.hmi", index)
}

validate_replay_index :: proc(index: int) {
	assert(index > 0 && index < REPLAY_BUFFER_COUNT)
}

replay_init :: proc(state: ^Replay_State, total_size: u64, memory_block: rawptr) -> bool {
	state.total_memory_size = total_size
	state.game_memory_block = memory_block
	return true
}

begin_recording :: proc(state: ^Replay_State, index: int) -> bool {
	validate_replay_index(index)

	file, err := os.create(replay_path(index))
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
	state.recording_index = index
	return true
}

end_recording :: proc(state: ^Replay_State) {
	if state.recording_file != nil {
		if err := os.close(state.recording_file); err != nil {
			log.errorf("Could not close recording: %v", err)
		}
	}

	state.recording_file = nil
	state.recording_index = 0
}

record_input :: proc(state: ^Replay_State, input: ^api.Game_Input) -> bool {
	written, err := os.write_ptr(state.recording_file, input, size_of(api.Game_Input))
	if err != nil || written != size_of(api.Game_Input) {
		log.errorf("Could not record input frame: %v", err)
		return false
	}

	return true
}

begin_playback :: proc(state: ^Replay_State, index: int) -> bool {
	validate_replay_index(index)

	file, err := os.open(replay_path(index), {.Read})
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
	state.playing_index = index
	return true
}

end_playback :: proc(state: ^Replay_State) {
	if state.playing_file != nil {
		if err := os.close(state.playing_file); err != nil {
			log.errorf("Could not close playback: %v", err)
		}
	}

	state.playing_file = nil
	state.playing_index = 0
}

playback_input :: proc(state: ^Replay_State, input: ^api.Game_Input) -> bool {
	input_size := size_of(api.Game_Input)
	input_bytes := ([^]u8)(input)[:input_size]

	bytes_read, err := os.read_full(state.playing_file, input_bytes)
	if bytes_read == input_size {
		return true
	}

	playing_index := state.playing_index
	end_playback(state)

	if !begin_playback(state, playing_index) {
		return false
	}

	bytes_read, err = os.read_full(state.playing_file, input_bytes)
	if err != nil || bytes_read != input_size {
		log.errorf("Could not read first replay frame: %v", err)
		end_playback(state)
		return false
	}

	return true
}
