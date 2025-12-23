#+feature dynamic-literals
package main

/*

GAMEPLAY O'CLOCK MEGAFILE

*/

import "utils"
import "utils/color"
import "utils/shape"

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"

import spall "core:prof/spall"
import sapp "sokol/app"

VERSION: string : "v0.0.0"
WINDOW_TITLE :: "Isolated"
GAME_RES_WIDTH :: 480
GAME_RES_HEIGHT :: 270
window_w := 1280
window_h := 720

when NOT_RELEASE {
	// can edit stuff in here to be whatever for testing
	PROFILE :: false
} else {
	// then this makes sure we've got the right settings for release
	PROFILE :: false
}

//
// epic game state

Game_State :: struct {
	ticks:             u64,
	game_time_elapsed: f64,
	cam_pos:           Vec2, // this is used by the renderer
	smoothed_fps:      f32,

	// entity system
	entity_top_count:  int,
	latest_entity_id:  int,
	entities:          [MAX_ENTITIES]Entity,
	entity_free_list:  [dynamic]int,

	// sloppy state dump
	player_handle:     Entity_Handle,
	scratch:           struct {
		all_entities: []Entity_Handle,
	},

	// the matrix
	grid:              map[Vec2i]^Chunk,
}

//
// action -> key mapping

action_map: map[Input_Action]Key_Code = {
	.left     = .A,
	.right    = .D,
	.up       = .W,
	.down     = .S,
	.click    = .LEFT_MOUSE,
	.use      = .RIGHT_MOUSE,
	.interact = .E,
	.quit     = .ESC,
}

Input_Action :: enum u8 {
	left,
	right,
	up,
	down,
	click,
	use,
	interact,
	quit,
}

//
// entity system

Entity :: struct {
	handle:              Entity_Handle,
	kind:                Entity_Kind,

	// todo, move this into static entity data
	update_proc:         proc(_: ^Entity),
	draw_proc:           proc(_: Entity),

	// big sloppy entity state dump.
	// add whatever you need in here.
	pos:                 Vec2,
	last_known_x_dir:    f32,
	flip_x:              bool,
	draw_offset:         Vec2,
	draw_pivot:          utils.Pivot,
	rotation:            f32,
	hit_flash:           Vec4,
	sprite:              Sprite_Name,
	anim_index:          int,
	next_frame_end_time: f64,
	loop:                bool,
	frame_duration:      f32,
	z_layer:             ZLayer,

	// this gets zeroed every frame. Useful for passing data to other systems.
	scratch:             struct {
		col_override: Vec4,
	},
}

Entity_Kind :: enum {
	nil,
	player,
	conveyor,
	thing1,
}

entity_setup :: proc(e: ^Entity, kind: Entity_Kind) {
	// entity defaults
	e.draw_proc = draw_entity_default
	e.draw_pivot = .bottom_center
	e.z_layer = .playspace

	switch kind {
	case .nil:
	case .player:
		setup_player(e)
	case .thing1:
		setup_thing1(e)
	case .conveyor:
		setup_conveyor(e)
	}
}

// big chunkus
Chunk :: struct {
	pos:   Vec2i,
	tiles: [32][32]Tile,
}

init_chunk :: proc(c: ^Chunk) {
	for x in 0 ..< 32 {
		for y in 0 ..< 32 {
			c.tiles[x][y] = Tile {
				kind = .empty,
			}
		}
	}
}

// game tile related things
Tile :: struct {
	kind:           TileKind,
	sprite:         Sprite_Name,
	anim_index:     int,
	frame_duration: f32,
}

TileKind :: enum {
	empty,
	conveyor,
}

//
// game :draw related things

Quad_Flags :: enum u8 {
	// #shared with the shader.glsl definition
	background_pixels = (1 << 0),
	flag2             = (1 << 1),
	flag3             = (1 << 2),
}

ZLayer :: enum u8 {
	// Can add as many layers as you want in here.
	// Quads get sorted and drawn lowest to highest.
	// When things are on the same layer, they follow normal call order.
	nil,
	background,
	shadow,
	playspace,
	vfx,
	ui,
	tooltip,
	pause_menu,
	top,
}

Sprite_Name :: enum {
	nil,
	bald_logo,
	fmod_logo,
	player_still,
	shadow_medium,
	bg_repeat_tex0,
	player_death,
	player_run,
	player_idle,
	conveyor,
	empty_tile,
	// to add new sprites, just put the .png in the res/images folder
	// and add the name to the enum here
	//
	// we could auto-gen this based on all the .png's in the images folder
	// but I don't really see the point right now. It's not hard to type lol.
}

sprite_data: [Sprite_Name]Sprite_Data = #partial {
	.player_idle = {frame_count = 2},
	.player_run = {frame_count = 3},
	.conveyor = {frame_count = 8},
}

Sprite_Data :: struct {
	frame_count: int,
	offset:      Vec2,
	pivot:       utils.Pivot,
}

get_sprite_offset :: proc(img: Sprite_Name) -> (offset: Vec2, pivot: utils.Pivot) {
	data := sprite_data[img]
	offset = data.offset
	pivot = data.pivot
	return
}

// #cleanup todo, this is kinda yuckie living in the bald-user
get_frame_count :: proc(sprite: Sprite_Name) -> int {
	frame_count := sprite_data[sprite].frame_count
	if frame_count == 0 {
		frame_count = 1
	}
	return frame_count
}

get_sprite_center_mass :: proc(img: Sprite_Name) -> Vec2 {
	size := get_sprite_size(img)

	offset, pivot := get_sprite_offset(img)

	center := size * utils.scale_from_pivot(pivot)
	center -= offset

	return center
}

//
// main game procs

app_init :: proc() {

}

app_frame :: proc() {

	// right now we are just calling the game update, but in future this is where you'd do a big
	// "UX" switch for startup splash, main menu, settings, in-game, etc

	{
		// ui space example
		push_coord_space(get_screen_space())

		x, y := screen_pivot(.top_left)
		x += 2
		y -= 2
		current_fps := f32(1 / ctx.delta_t)
		ctx.gs.smoothed_fps = math.lerp(ctx.gs.smoothed_fps, current_fps, f32(0.1))
		fps := fmt.aprintf("FPS: %.1f", ctx.gs.smoothed_fps)
		defer delete(fps)
		draw_text({x, y}, fps, z_layer = .ui, pivot = utils.Pivot.top_left)

		chunks_loaded := fmt.aprintf("Chunks Loaded: %v", len(ctx.gs.grid))
		defer delete(chunks_loaded)
		draw_text({x, y - 15}, chunks_loaded, z_layer = .ui, pivot = utils.Pivot.top_left)
	}

	//sound_play_continuously("event:/ambiance", "")

	game_update()
	game_draw()

	volume: f32 = 0.75
	//sound_update(get_player().pos, volume)
}

app_shutdown :: proc() {
	// cleanup chunkus
	for k, v in ctx.gs.grid {
		delete_key(&ctx.gs.grid, k)
		free(v)
	}
}

game_update :: proc() {
	ctx.gs.scratch = {} // auto-zero scratch for each update
	defer {
		// update at the end
		ctx.gs.game_time_elapsed += f64(ctx.delta_t)
		ctx.gs.ticks += 1
	}

	// this'll be using the last frame's camera position, but it's fine for most things
	push_coord_space(get_world_space())

	// setup world for first game tick
	if ctx.gs.ticks == 0 {
		player := entity_create(.player)
		ctx.gs.player_handle = player.handle
	}

	rebuild_scratch_helpers()

	// big :update time
	for handle in get_all_ents() {
		e := entity_from_handle(handle)

		update_entity_animation(e)

		if e.update_proc != nil {
			e.update_proc(e)
		}
	}

	if key_pressed(.ESC) {
		consume_key_pressed(.ESC)
		sapp.quit()
	}

	utils.animate_to_target_v2(&ctx.gs.cam_pos, get_player().pos, ctx.delta_t, rate = 10)

	// draw conveyor at mouse
	pos := mouse_pos_in_current_space()
	spos := Vec2{math.round_f32(pos.x / 10) * 10, math.round_f32(pos.y / 10) * 10}

	draw_sprite(
		spos,
		.conveyor,
		col = {0.8, 0.8, 0.8, 0.6},
		col_override = {0.3, 0.3, 0.3, 0.1},
		xform = utils.xform_scale(Vec2{0.3125, 0.3125}),
		z_layer = .playspace,
	)

	// load chunks
	player := get_player()
	px := int(math.floor_f32(player.pos.x / 320))
	py := int(math.floor_f32(player.pos.y / 320))
	radius := 2 // TODO: not good
	for x in -radius ..= radius {
		for y in -radius ..= radius {
			// chunkus player pos
			pos := Vec2i{px + x, py + y}
			_, exists := ctx.gs.grid[pos]
			if !exists {
				chunk := new(Chunk)
				init_chunk(chunk)
				chunk.pos = pos
				ctx.gs.grid[pos] = chunk
			}
		}
	}

	// place conveyor if we so desire
	if key_down(.LEFT_MOUSE) {

		cpos := Vec2i{int(math.floor_f32(spos.x / 320)), int(math.floor_f32(spos.y / 320))}
		c := ctx.gs.grid[cpos]

		lx := spos.x - f32(cpos.x * 320)
		ly := spos.y - f32(cpos.y * 320)

		tx := int(lx / 10)
		ty := int(ly / 10)

		c.tiles[tx][ty] = Tile {
			kind           = .conveyor,
			sprite         = .conveyor,
			frame_duration = 0.05,
		}
	}
}

rebuild_scratch_helpers :: proc() {
	// construct the list of all entities on the temp allocator
	// that way it's easier to loop over later on
	all_ents := make(
		[dynamic]Entity_Handle,
		0,
		len(ctx.gs.entities),
		allocator = context.temp_allocator,
	)
	for &e in ctx.gs.entities {
		if !is_valid(e) do continue
		append(&all_ents, e.handle)
	}
	ctx.gs.scratch.all_entities = all_ents[:]
}

game_draw :: proc() {

	// this is so we can get the current pixel in the shader in world space (VERYYY useful)
	draw_frame.ndc_to_world_xform =
		get_world_space_camera() * linalg.inverse(get_world_space_proj())
	draw_frame.bg_repeat_tex0_atlas_uv = atlas_uv_from_sprite(.bg_repeat_tex0)

	// background thing
	{
		// identity matrices, so we're in clip space
		push_coord_space({proj = Matrix4(1), camera = Matrix4(1)})

		// draw rect that covers the whole screen
		draw_rect(shape.Rect{-1, -1, 1, 1}, flags = .background_pixels) // we leave it in the hands of the shader
	}

	// world
	{
		push_coord_space(get_world_space())

		draw_text(
			{0, -50},
			"sugon deez nuts",
			pivot = .bottom_center,
			col = {0, 0, 0, 0.1},
			drop_shadow_col = {},
		)

		// draw big chunkus tiles
		player := get_player()
		for _, chunk in ctx.gs.grid {
			cx := f32(chunk.pos.x * 320)
			cy := f32(chunk.pos.y * 320)

			// debug shit
			push_z_layer(.ui)
			ccenter := Vec2{cx + 160, cy + 160}
			draw_text(
				ccenter,
				fmt.tprintf("(%d, %d)", chunk.pos.x, chunk.pos.y),
				z_layer = .ui,
				col = {0, 0, 0, 0.5},
			)

			for x in 0 ..< 32 {
				for y in 0 ..< 32 {
					tile := chunk.tiles[x][y]
					if tile.kind == .empty {continue}

					tile_pos := Vec2{cx + f32(x) * 10, cy + f32(y) * 10}

					if math.abs(tile_pos.x - player.pos.x) > 350 {continue}
					if math.abs(tile_pos.y - player.pos.y) > 200 {continue}

					update_tile_animation(&tile)

					draw_sprite(
						tile_pos,
						tile.sprite,
						xform = utils.xform_scale(Vec2{0.3125, 0.3125}),
						z_layer = .background,
						anim_index = tile.anim_index,
					)
				}
			}
		}

		for handle in get_all_ents() {
			e := entity_from_handle(handle)
			e.draw_proc(e^)
		}
	}
}

// note, this needs to be in the game layer because it varies from game to game.
// Specifically, stuff like anim_index and whatnot aren't guarenteed to be named the same or actually even be on the base entity.
// (in terrafactor, it's inside a sub state struct)
draw_entity_default :: proc(e: Entity) {
	e := e // need this bc we can't take a reference from a procedure parameter directly

	if e.sprite == nil {
		return
	}

	xform := utils.xform_rotate(e.rotation)

	draw_sprite_entity(
		&e,
		e.pos,
		e.sprite,
		xform = xform,
		anim_index = e.anim_index,
		draw_offset = e.draw_offset,
		z_layer = e.z_layer,
		flip_x = e.flip_x,
		pivot = e.draw_pivot,
	)
}

// helper for drawing a sprite that's based on an entity.
// useful for systems-based draw overrides, like having the concept of a hit_flash across all entities
draw_sprite_entity :: proc(
	entity: ^Entity,
	pos: Vec2,
	sprite: Sprite_Name,
	pivot := utils.Pivot.center_center,
	flip_x := false,
	draw_offset := Vec2{},
	xform := Matrix4(1),
	anim_index := 0,
	col := color.WHITE,
	col_override: Vec4 = {},
	z_layer: ZLayer = {},
	flags: Quad_Flags = {},
	params: Vec4 = {},
	crop_top: f32 = 0.0,
	crop_left: f32 = 0.0,
	crop_bottom: f32 = 0.0,
	crop_right: f32 = 0.0,
	z_layer_queue := -1,
) {

	col_override := col_override

	col_override = entity.scratch.col_override
	if entity.hit_flash.a != 0 {
		col_override.xyz = entity.hit_flash.xyz
		col_override.a = max(col_override.a, entity.hit_flash.a)
	}

	draw_sprite(
		pos,
		sprite,
		pivot,
		flip_x,
		draw_offset,
		xform,
		anim_index,
		col,
		col_override,
		z_layer,
		flags,
		params,
		crop_top,
		crop_left,
		crop_bottom,
		crop_right,
	)
}

//
// ~ Gameplay Slop Waterline ~
//
// From here on out, it's gameplay slop time.
// Structure beyond this point just slows things down.
//
// No point trying to make things 'reusable' for future projects.
// It's trivially easy to just copy and paste when needed.
//

// shorthand for getting the player
get_player :: proc() -> ^Entity {
	return entity_from_handle(ctx.gs.player_handle)
}

setup_player :: proc(e: ^Entity) {
	e.kind = .player

	// this offset is to take it from the bottom center of the aseprite document
	// and center it at the feet
	e.draw_offset = Vec2{0.5, 5}
	e.draw_pivot = .bottom_center

	e.update_proc = proc(e: ^Entity) {

		input_dir := get_input_vector()
		e.pos += input_dir * 100.0 * ctx.delta_t

		if input_dir.x != 0 {
			e.last_known_x_dir = input_dir.x
		}

		e.flip_x = e.last_known_x_dir < 0

		if input_dir == {} {
			entity_set_animation(e, .player_idle, 0.3)
		} else {
			entity_set_animation(e, .player_run, 0.1)
		}

		e.scratch.col_override = Vec4{0, 0, 1, 0.2}
	}

	e.draw_proc = proc(e: Entity) {
		draw_sprite(e.pos, .shadow_medium, col = {1, 1, 1, 0.2}, z_layer = .shadow)
		draw_entity_default(e)
	}
}

setup_thing1 :: proc(using e: ^Entity) {
	kind = .thing1
}

setup_conveyor :: proc(using e: ^Entity) {
	kind = .conveyor
	sprite = .conveyor
	draw_pivot = .center_center
	z_layer = .background
	loop = true
	frame_duration = 0.1
	entity_set_animation(e, .conveyor, 0.1)

	draw_proc = proc(e: Entity) {
		scale := utils.xform_scale(Vec2{0.3125, 0.3125}) // 32 * 0.3125 = 10
		draw_sprite(
			e.pos,
			.conveyor,
			z_layer = e.z_layer,
			xform = scale,
			anim_index = e.anim_index,
		)
	}
}

entity_set_animation :: proc(
	e: ^Entity,
	sprite: Sprite_Name,
	frame_duration: f32,
	looping := true,
) {
	if e.sprite != sprite {
		e.sprite = sprite
		e.loop = looping
		e.frame_duration = frame_duration
		e.anim_index = 0
		e.next_frame_end_time = 0
	}
}

update_entity_animation :: proc(e: ^Entity) {
	if e.frame_duration == 0 do return

	frame_count := get_frame_count(e.sprite)

	is_playing := true
	if !e.loop {
		is_playing = e.anim_index + 1 <= frame_count
	}

	if is_playing {

		if e.next_frame_end_time == 0 {
			e.next_frame_end_time = now() + f64(e.frame_duration)
		}

		if end_time_up(e.next_frame_end_time) {
			e.anim_index += 1
			e.next_frame_end_time = 0
			if e.anim_index >= frame_count {

				if e.loop {
					e.anim_index = 0
				}
			}
		}
	}
}

update_tile_animation :: proc(t: ^Tile) {
	if t.frame_duration == 0 do return
	if t.kind == .empty do return

	frame_count := get_frame_count(t.sprite)

	total_anim_time := f32(frame_count) * t.frame_duration
	progress := math.mod(f32(ctx.gs.game_time_elapsed), total_anim_time)
	t.anim_index = int(progress / t.frame_duration)
}
