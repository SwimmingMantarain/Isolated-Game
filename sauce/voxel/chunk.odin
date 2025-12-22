package voxel

import "core:math/linalg"
import "../utils"

CHUNK_SIZE :: 32

Block_Type :: enum u8 {
	Air,
	Dirt,
	Grass,
	Stone,
}

Chunk :: struct {
	blocks: [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]Block_Type,
	mesh:   Chunk_Mesh,
	pos:    [3]int, // Chunk coordinate
}

Chunk_Mesh :: struct {
	vertices: [dynamic]Voxel_Vertex,
	indices:  [dynamic]u16,
}

Voxel_Vertex :: struct {
	pos:    [3]f32,
	normal: [3]f32,
	uv:     [2]f32,
	color:  [4]f32,
}

// Simple naive meshing for now
chunk_gen_mesh :: proc(chunk: ^Chunk) {
	clear(&chunk.mesh.vertices)
	clear(&chunk.mesh.indices)

	for x in 0 ..< CHUNK_SIZE {
		for y in 0 ..< CHUNK_SIZE {
			for z in 0 ..< CHUNK_SIZE {
				block := chunk.blocks[x][y][z]
				if block == .Air do continue

				// Check neighbors
				// If neighbor is air or out of bounds, draw face

				// West (-x)
				if x == 0 || chunk.blocks[x - 1][y][z] == .Air {
					add_face(chunk, x, y, z, {-1, 0, 0}, block)
				}
				// East (+x)
				if x == CHUNK_SIZE - 1 || chunk.blocks[x + 1][y][z] == .Air {
					add_face(chunk, x, y, z, {1, 0, 0}, block)
				}
				// Bottom (-y)
				if y == 0 || chunk.blocks[x][y - 1][z] == .Air {
					add_face(chunk, x, y, z, {0, -1, 0}, block)
				}
				// Top (+y)
				if y == CHUNK_SIZE - 1 || chunk.blocks[x][y + 1][z] == .Air {
					add_face(chunk, x, y, z, {0, 1, 0}, block)
				}
				// South (-z)
				if z == 0 || chunk.blocks[x][y][z - 1] == .Air {
					add_face(chunk, x, y, z, {0, 0, -1}, block)
				}
				// North (+z)
				if z == CHUNK_SIZE - 1 || chunk.blocks[x][y][z + 1] == .Air {
					add_face(chunk, x, y, z, {0, 0, 1}, block)
				}
			}
		}
	}
}

add_face :: proc(chunk: ^Chunk, x, y, z: int, normal: [3]f32, block: Block_Type) {
	// Add 4 vertices and 6 indices for the face
	// This is very verbose in code, but simple conceptually.
	// For a cube at (x,y,z), size 1.

	fx, fy, fz := f32(x), f32(y), f32(z)
	
	// Define corners based on normal
	// ... This is tedious to write out manually for all 6 faces without lookup tables.
	// I'll use a standardized lookup or logic.
	
	// Let's use a simple basis construction.
	// Center of face is (x+0.5, y+0.5, z+0.5) + normal * 0.5
	
	// Tangent and Bitangent
	tangent: [3]f32
	bitangent: [3]f32
	
	if abs(normal.x) > 0.5 {
		tangent = {0, 1, 0}
		bitangent = {0, 0, 1}
	} else if abs(normal.y) > 0.5 {
		tangent = {1, 0, 0}
		bitangent = {0, 0, 1}
	} else {
		tangent = {1, 0, 0}
		bitangent = {0, 1, 0}
	}
    
    // Fix winding order if needed, but for now simple
    
    center := [3]f32{fx + 0.5, fy + 0.5, fz + 0.5} + normal * 0.5
    
    v0 := center - tangent * 0.5 - bitangent * 0.5
    v1 := center - tangent * 0.5 + bitangent * 0.5
    v2 := center + tangent * 0.5 + bitangent * 0.5
    v3 := center + tangent * 0.5 - bitangent * 0.5
    
    color := [4]f32{1, 1, 1, 1}
    if block == .Grass do color = {0.2, 0.8, 0.2, 1}
    else if block == .Dirt do color = {0.6, 0.4, 0.2, 1}
    else if block == .Stone do color = {0.5, 0.5, 0.5, 1}
    
    start_idx := u16(len(chunk.mesh.vertices))
    
    append(&chunk.mesh.vertices, Voxel_Vertex{pos = v0, normal = normal, uv = {0, 0}, color = color})
    append(&chunk.mesh.vertices, Voxel_Vertex{pos = v1, normal = normal, uv = {0, 1}, color = color})
    append(&chunk.mesh.vertices, Voxel_Vertex{pos = v2, normal = normal, uv = {1, 1}, color = color})
    append(&chunk.mesh.vertices, Voxel_Vertex{pos = v3, normal = normal, uv = {1, 0}, color = color})
    
    append(&chunk.mesh.indices, start_idx, start_idx + 1, start_idx + 2, start_idx, start_idx + 2, start_idx + 3)
}
