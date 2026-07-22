package platform

import api "../shared"
import "core:fmt"
import "core:log"
import sdl "vendor:sdl2"

Input_System :: struct {
	// added 4 to be the max number of
	// controllers? waste of memory?
	controllers: [4]^sdl.GameController,
}

input_system_init :: proc() -> ^Input_System {
	result := new(Input_System)

	num_joysticks := sdl.NumJoysticks()
	for i in 0 ..< i32(4) {
		if sdl.IsGameController(i) {
			game_controller := sdl.GameControllerOpen(i)
			// just do first 4?
			result.controllers[i] = game_controller
		}
	}

	return result
}

collect_game_input :: proc(
	input_system: ^Input_System,
	old_input: ^api.Game_Input,
	new_input: ^api.Game_Input,
) {
	old_keyboard_controller: ^api.Game_Controller_Input = api.get_controller(old_input, 0)
	new_keyboard_controller: ^api.Game_Controller_Input = api.get_controller(new_input, 0)
	reset_controller_input(old_keyboard_controller, new_keyboard_controller)
	new_keyboard_controller.is_connected = true

	keys := sdl.GetKeyboardState(nil)
	process_keyboard_input(old_keyboard_controller, new_keyboard_controller, keys)

	mouse_state := sdl.GetMouseState(&new_input.mouse.pos[0], &new_input.mouse.pos[1])
	process_mouse_button_press(&old_input.mouse.Left_Button, &new_input.mouse.Left_Button, mouse_state, sdl.BUTTON_LMASK)
	process_mouse_button_press(&old_input.mouse.Middle_Button, &new_input.mouse.Middle_Button, mouse_state, sdl.BUTTON_MMASK)
	process_mouse_button_press(&old_input.mouse.Right_Button, &new_input.mouse.Right_Button, mouse_state, sdl.BUTTON_RMASK)
	process_mouse_button_press(&old_input.mouse.X1_Button, &new_input.mouse.X1_Button, mouse_state, sdl.BUTTON_X1MASK)
	process_mouse_button_press(&old_input.mouse.X2_Button, &new_input.mouse.X2_Button, mouse_state, sdl.BUTTON_X2MASK)

	for v, i in input_system.controllers {
		if v == nil {
			continue
		}
		// adjusts index so that the 0 index can be the kget_controller
		old_controller: ^api.Game_Controller_Input = api.get_controller(old_input, i + 1)
		new_controller: ^api.Game_Controller_Input = api.get_controller(new_input, i + 1)
		reset_controller_input(old_controller, new_controller)

		if !sdl.GameControllerGetAttached(v) {
			new_controller.is_connected = false
			log.info("Game controller disconnected")
			continue
		}

		new_controller.is_connected = true

		LEFT_THUMB_DEADZONE :: 7849

		left_thumb_x := sdl.GameControllerGetAxis(v, sdl.GameControllerAxis.LEFTX)
		new_controller.stick_avg_x = process_controller_axis_value(
			left_thumb_x,
			LEFT_THUMB_DEADZONE,
		)

		left_thumb_y := sdl.GameControllerGetAxis(v, sdl.GameControllerAxis.LEFTY)
		new_controller.stick_avg_y = process_controller_axis_value(
			left_thumb_y,
			LEFT_THUMB_DEADZONE,
		)

		if new_controller.stick_avg_x != 0 || new_controller.stick_avg_y != 0 {
			new_controller.is_analog = true
		}


		dpad_down := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_DOWN)
		dpad_up := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_UP)
		dpad_left := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_LEFT)
		dpad_right := sdl.GameControllerGetButton(v, sdl.GameControllerButton.DPAD_RIGHT)

		if dpad_down == 1 {
			new_controller.stick_avg_y = -1
			new_controller.is_analog = false
		}
		if dpad_up == 1 {
			new_controller.stick_avg_y = 1
			new_controller.is_analog = false
		}
		if dpad_left == 1 {
			new_controller.stick_avg_x = -1
			new_controller.is_analog = false
		}
		if dpad_right == 1 {
			new_controller.stick_avg_x = 1
			new_controller.is_analog = false
		}

		threshold: f32 = 0.5
		process_controller_button_press(
			&old_controller.Move_left,
			&new_controller.Move_left,
			new_controller.stick_avg_x < -threshold ? 1 : 0,
		)
		process_controller_button_press(
			&old_controller.Move_right,
			&new_controller.Move_right,
			new_controller.stick_avg_x > threshold ? 1 : 0,
		)
		process_controller_button_press(
			&old_controller.Move_down,
			&new_controller.Move_down,
			new_controller.stick_avg_y < -threshold ? 1 : 0,
		)
		process_controller_button_press(
			&old_controller.Move_up,
			&new_controller.Move_up,
			new_controller.stick_avg_y > threshold ? 1 : 0,
		)

		// returns 1 for pressed, 0 for not
		down := sdl.GameControllerGetButton(v, sdl.GameControllerButton.A)
		process_controller_button_press(
			&old_controller.Action_down,
			&new_controller.Action_down,
			down,
		)

		right := sdl.GameControllerGetButton(v, sdl.GameControllerButton.B)
		process_controller_button_press(
			&old_controller.Action_right,
			&new_controller.Action_right,
			right,
		)

		left := sdl.GameControllerGetButton(v, sdl.GameControllerButton.X)
		process_controller_button_press(
			&old_controller.Action_left,
			&new_controller.Action_left,
			left,
		)

		up := sdl.GameControllerGetButton(v, sdl.GameControllerButton.Y)
		process_controller_button_press(&old_controller.Action_up, &new_controller.Action_up, up)

		start := sdl.GameControllerGetButton(v, sdl.GameControllerButton.START)
		process_controller_button_press(&old_controller.Start, &new_controller.Start, start)

		back := sdl.GameControllerGetButton(v, sdl.GameControllerButton.BACK)
		process_controller_button_press(&old_controller.Back, &new_controller.Back, back)
	}
}

process_controller_axis_value :: proc(v, deadzone: i16) -> (result: f32) {
	value := f32(v)
	deadzone_f := f32(deadzone)

	if v < -deadzone {
		result = (value + deadzone_f) / (32768.0 - deadzone_f)
	} else if v > deadzone {
		result = (value - deadzone_f) / (32767.0 - deadzone_f)
	}

	return
}


reset_controller_input :: proc(old_controller, new_controller: ^api.Game_Controller_Input) {
	previous_buttons := old_controller.Buttons

	new_controller^ = {}

	new_controller.is_connected = old_controller.is_connected
	new_controller.is_analog = old_controller.is_analog

	for button, index in previous_buttons {
		new_controller.Buttons[index].ended_down = button.ended_down
	}
}


process_mouse_button_press :: proc(
	old_state: ^api.Game_Button_State,
	new_state: ^api.Game_Button_State,
	state: u32,
	mask: u32,
) {
	pressed := (state & mask) != 0
	new_state.ended_down = pressed
	new_state.half_transition_count = old_state.ended_down != new_state.ended_down ? 1 : 0
}

process_controller_button_press :: proc(
	old_state: ^api.Game_Button_State,
	new_state: ^api.Game_Button_State,
	pressed: u8,
) {
	new_state.ended_down = pressed == 1
	new_state.half_transition_count = old_state.ended_down != new_state.ended_down ? 1 : 0
}

process_keyboard_input :: proc(
	old_controller: ^api.Game_Controller_Input,
	new_controller: ^api.Game_Controller_Input,
	keys: [^]u8,
) {
	process_controller_button_press(
		&old_controller.Move_down,
		&new_controller.Move_down,
		keys[sdl.SCANCODE_S],
	)

	process_controller_button_press(
		&old_controller.Move_up,
		&new_controller.Move_up,
		keys[sdl.SCANCODE_W],
	)

	process_controller_button_press(
		&old_controller.Move_left,
		&new_controller.Move_left,
		keys[sdl.SCANCODE_A],
	)

	process_controller_button_press(
		&old_controller.Move_right,
		&new_controller.Move_right,
		keys[sdl.SCANCODE_D],
	)

	process_controller_button_press(
		&old_controller.Action_down,
		&new_controller.Action_down,
		keys[sdl.SCANCODE_DOWN],
	)

	process_controller_button_press(
		&old_controller.Action_up,
		&new_controller.Action_up,
		keys[sdl.SCANCODE_UP],
	)

	process_controller_button_press(
		&old_controller.Action_left,
		&new_controller.Action_left,
		keys[sdl.SCANCODE_LEFT],
	)

	process_controller_button_press(
		&old_controller.Action_right,
		&new_controller.Action_right,
		keys[sdl.SCANCODE_RIGHT],
	)

	process_controller_button_press(
		&old_controller.Left_Shoulder,
		&new_controller.Left_Shoulder,
		keys[sdl.SCANCODE_Q],
	)

	process_controller_button_press(
		&old_controller.Right_Shoulder,
		&new_controller.Right_Shoulder,
		keys[sdl.SCANCODE_E],
	)
}
