package main

import "core:fmt"
import "core:math"
import sdl "vendor:sdl2"

Audio_State :: struct {
	samples_per_second:      i32, // hz or per second
	tone_hz:                 i32,
	tone_volume:             i16,
	running_sample_index:    u32,
	square_wave_period:      i32,
	half_square_wave_period: i32,
	t_sine:                  f32,
}

init_audio :: proc(g: ^Game) {
	g.audio_state = Audio_State {
		samples_per_second   = 48000,
		tone_hz              = 256,
		tone_volume          = 3000,
		running_sample_index = 0,
	}
	g.audio_state.square_wave_period = g.audio_state.samples_per_second / g.audio_state.tone_hz
	g.audio_state.half_square_wave_period = g.audio_state.square_wave_period / 2

	desired := sdl.AudioSpec {
		freq     = g.audio_state.samples_per_second,
		format   = sdl.AUDIO_S16,
		channels = 2, /**< Number of channels: 1 mono, 2 stereo */
		samples  = 1024,
		callback = audio_callback,
		userdata = &g.audio_state,
	}

	obtained: sdl.AudioSpec

	audio_device_id := sdl.OpenAudioDevice(
		nil,
		false,
		&desired,
		&obtained,
		sdl.AUDIO_ALLOW_ANY_CHANGE,
	)
	if audio_device_id == 0 {
		fmt.printfln("Error opening audio device: %s", sdl.GetError())
		return
	}
	g.audio_device_id = audio_device_id

	fmt.printfln(
		"Audio opened: device_id=%d freq=%d channels=%d samples=%d",
		cast(u32)g.audio_device_id,
		obtained.freq,
		obtained.channels,
		obtained.samples,
	)

	sdl.PauseAudioDevice(audio_device_id, sdl.bool(g.audio_pause_on))
}

// returns new pause_on state to store in game
audio_pause_device :: proc(audio_device_id: sdl.AudioDeviceID, pause_on: bool) -> bool {
	sdl.PauseAudioDevice(audio_device_id, sdl.bool(pause_on))
	return pause_on
}


audio_callback :: proc "c" (userdata: rawptr, stream: [^]u8, len: i32) {
	audio := cast(^Audio_State)userdata

	bytes_per_sample := size_of(i16) * 2 // left + right
	sample_count := len / cast(i32)bytes_per_sample

	sample_out := cast([^]i16)stream

	for sample_index in 0 ..< sample_count {

		sine_value := math.sin(audio.t_sine)
		sample_value := i16(sine_value * f32(audio.tone_volume))

		audio.t_sine += (2.0 * math.PI) / f32(audio.square_wave_period)

		sample_out[0] = sample_value // left
		sample_out[1] = sample_value // right
		sample_out = sample_out[2:]

		audio.running_sample_index += 1
	}
}
