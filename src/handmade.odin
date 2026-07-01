package handmade

import "core:math"

render_weird_gradient :: proc(buffer: ^Game_offscreen_buffer, blue_offset, green_offset: i32) {
	width := buffer.width
	height := buffer.height
	pitch := buffer.pitch

	row := ([^]u8)(buffer.memory)

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

game_output_sound :: proc(buffer: ^Game_sound_output_buffer, tone_hz: i32) {
	@(static) t_sine: f32

	tone_volume := i16(3000)
	wave_period := buffer.samples_per_second / tone_hz

	sample_out := buffer.samples

	for sample_index in 0 ..< buffer.sample_count {
		sine_value := math.sin(t_sine)
		sample_value := i16(sine_value * f32(tone_volume))

		sample_out[0] = sample_value
		sample_out[1] = sample_value
		sample_out = sample_out[2:]

		t_sine += 2.0 * math.PI / f32(wave_period)
	}
}

game_update_and_render :: proc(
	offscreen_buffer: ^Game_offscreen_buffer,
	blue_offset, green_offset: i32,
	sound_buffer: ^Game_sound_output_buffer,
	tone_hz: i32,
) {
	render_weird_gradient(offscreen_buffer, blue_offset, green_offset)
	game_output_sound(sound_buffer, tone_hz)
}
