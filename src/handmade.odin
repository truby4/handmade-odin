package handmade

render_weird_gradient :: proc(buffer: ^game_offscreen_buffer, blue_offset, green_offset: i32) {
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


game_update_and_render :: proc(buffer: ^game_offscreen_buffer, blue_offset, green_offset: i32) {
	render_weird_gradient(buffer, blue_offset, green_offset)
}
