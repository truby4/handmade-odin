package handmade

Game_offscreen_buffer :: struct {
	memory:               rawptr,
	width, height, pitch: i32,
}

Game_sound_output_buffer :: struct {
	samples_per_second: i32,
	sample_count:       i32,
	samples:            [^]i16,
}
