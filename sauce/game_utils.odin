package main

/*

This is mostly just a random collection of utility functions that are likely shared across games.

Funcitons here can't live in the actual `utils` package because they interface with game-specific state. 

*/

import "utils"
import "utils/color"
import "utils/shape"

import "core:log"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/linalg"

//
// shorthand namespace helpers

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Matrix4 :: linalg.Matrix4f32;
Vec2i :: [2]int

//
// constant compile-tile flags for target specific logic

// Release or Debug
GENERATE_DEBUG_SYMBOLS :: ODIN_DEBUG
RELEASE :: #config(RELEASE, !ODIN_DEBUG) // by default, make it not release on -debug
NOT_RELEASE :: !RELEASE // called this NOT_RELEASE because we can still be debuggin on release

// these are used right now, will make them useful later on
DEMO :: #config(DEMO, false)
DEV :: #config(DEV, NOT_RELEASE)

//
// game spaces

get_world_space :: proc() -> Coord_Space {
	return {proj=get_world_space_proj(), camera=get_world_space_camera()}
}
get_screen_space :: proc() -> Coord_Space {
	return {proj=get_screen_space_proj(), camera=Matrix4(1)}
}

get_world_space_proj :: proc() -> Matrix4 {
	return linalg.matrix_ortho3d_f32(f32(window_w) * -0.5, f32(window_w) * 0.5, f32(window_h) * -0.5, f32(window_h) * 0.5, -1, 1)
}
get_world_space_camera :: proc() -> Matrix4 {
	cam := Matrix4(1)
	cam *= utils.xform_translate(ctx.gs.cam_pos)
	cam *= utils.xform_scale(get_camera_zoom())
	return cam
}
get_camera_zoom :: proc() -> f32 {
	return f32(GAME_RES_HEIGHT) / f32(window_h)
}

get_screen_space_proj :: proc() -> Matrix4 {
	scale := f32(GAME_RES_HEIGHT) / f32(window_h) // same res as standard world zoom
	
	w := f32(window_w) * scale
	h := f32(window_h) * scale
	
	// this centers things
	offset := GAME_RES_WIDTH*0.5 - w*0.5

	return linalg.matrix_ortho3d_f32(0+offset, w+offset, 0, h, -1, 1)
}

//
// action input

is_action_pressed :: proc(action: Input_Action) -> bool {
	key := key_from_action(action)
	return key_pressed(key)
}
is_action_released :: proc(action: Input_Action) -> bool {
	key := key_from_action(action)
	return key_released(key)
}
is_action_down :: proc(action: Input_Action) -> bool {
	key := key_from_action(action)
	return key_down(key)
}

consume_action_pressed :: proc(action: Input_Action) {
	key := key_from_action(action)
	consume_key_pressed(key)
}
consume_action_released :: proc(action: Input_Action) {
	key := key_from_action(action)
	consume_key_released(key)
}

key_from_action :: proc(action: Input_Action) -> Key_Code {
	key, found := action_map[action]
	if !found {
		log.debugf("action %v not bound to any key", action)
	}
	return key
}

get_input_vector :: proc() -> Vec2 {
	input: Vec2
	if is_action_down(.left) do input.x -= 1.0
	if is_action_down(.right) do input.x += 1.0
	if is_action_down(.down) do input.y -= 1.0
	if is_action_down(.up) do input.y += 1.0
	if input == {} {
		return {}
	} else {
		return linalg.normalize(input)
	}
}

//
// timing utilities

app_now :: utils.seconds_since_init

now :: proc() -> f64 {
	return ctx.gs.game_time_elapsed
}
end_time_up :: proc(end_time: f64) -> bool {
	return end_time == -1 ? false : now() >= end_time 
}
time_since :: proc(time: f64) -> f32 {
	if time == 0 {
		return 99999999.0
	}
	return f32(now()-time)
}

//
// UI

screen_pivot_v2 :: proc(pivot: utils.Pivot) -> Vec2 {
	x,y := screen_pivot(pivot)
	return Vec2{x,y}
}

screen_pivot :: proc(pivot: utils.Pivot) -> (x, y: f32) {
	#partial switch(pivot) {
		case .top_left:
		x = 0
		y = f32(window_h)
		
		case .top_center:
		x = f32(window_w) / 2
		y = f32(window_h)
		
		case .bottom_left:
		x = 0
		y = 0
		
		case .center_center:
		x = f32(window_w) / 2
		y = f32(window_h) / 2
		
		case .top_right:
		x = f32(window_w)
		y = f32(window_h)
		
		case .bottom_center:
		x = f32(window_w) / 2
		y = 0
		
		case:
		utils.crash_when_debug(pivot, "TODO")
	}
	
	ndc_x := (x / (f32(window_w) * 0.5)) - 1.0;
	ndc_y := (y / (f32(window_h) * 0.5)) - 1.0;
	
	mouse_ndc := Vec2{ndc_x, ndc_y}
	
	mouse_world := Vec4{mouse_ndc.x, mouse_ndc.y, 0, 1}
	
	mouse_world = linalg.inverse(get_screen_space_proj()) * mouse_world
	x = mouse_world.x
	y = mouse_world.y
	
	return
}

raw_button :: proc(rect: shape.Rect) -> (hover, pressed: bool) {
	mouse_pos := mouse_pos_in_current_space()
	hover = shape.rect_contains(rect, mouse_pos)
	if hover && key_pressed(.LEFT_MOUSE) {
		consume_key_pressed(.LEFT_MOUSE)
		pressed = true
	}
	return
}

mouse_pos_in_current_space :: proc() -> Vec2 {
	proj := draw_frame.coord_space.proj
	cam := draw_frame.coord_space.camera
	if proj == {} || cam == {} {
		log.error("not in a space, need to push_coord_space first")
	}
	
	mouse := Vec2{state.mouse_x, state.mouse_y}

	ndc_x := (mouse.x / (f32(window_w) * 0.5)) - 1.0;
	ndc_y := (mouse.y / (f32(window_h) * 0.5)) - 1.0;
	ndc_y *= -1
	
	mouse_ndc := Vec2{ndc_x, ndc_y}
	
	mouse_world :Vec4= Vec4{mouse_ndc.x, mouse_ndc.y, 0, 1}

	mouse_world = linalg.inverse(proj) * mouse_world
	mouse_world = cam * mouse_world
	
	return mouse_world.xy
}