package shape

// shorthand
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

//
// TYPES
//

Shape :: union {
	Rect,
	Circle
}

Circle :: struct {
	pos: Vec2,
	radius: f32,
}

/*
Rect is defined as:

xy = bottom left (or min)
zw = top right (or max)

It's very useful for making UI rects, also for collision.
*/
Rect :: Vec4