package main

/*
 * UIUIUIUIUIUI
*/

import "utils"
import shape "utils/shape"

draw_window_default :: proc(w: ^Window) {
	rect := shape.rect_make_with_pos(
		Vec2{w.pos.x, w.pos.y},
		Vec2{w.size.x, w.size.y},
		.center_center,
	)
	draw_rect(rect, w.sprite, z_layer = .ui)
}

make_window :: proc(name: string, pos: Vec2, size: Vec2, sprite: Sprite_Name = .nil) -> Window {
	return Window {
		name = name,
		pos = pos,
		size = size,
		sprite = sprite,
		draw_proc = draw_window_default,
	}
}

draw_window :: proc(w: ^Window) {
	w.draw_proc(w)
}

draw_window_text :: proc(w: ^Window, text: string, pos: Vec2, pivot: utils.Pivot) {
	pos_in_w := Vec2{w.pos.x - (w.size.x / 2) + pos.x, w.pos.y + (w.size.y / 2) - pos.y}

	draw_text(pos_in_w, text, pivot = pivot, z_layer = .ui)
}

Window :: struct {
	name:      string,
	sprite:    Sprite_Name,
	pos:       Vec2,
	size:      Vec2,
	draw_proc: proc(_: ^Window),
}
