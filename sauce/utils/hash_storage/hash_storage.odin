package hash_storage

// use a hash key to store data immediately.
// very useful for ooga booga gameplay code and just haphazardly storing something in a string
// will auto delete the memory when it's no longer called every frame

// TODO, put this into a datastructure so we can make multiple with different lifetimes
// (one for app frame, one for game frame)

import "core:log"

Entry :: struct {
	last_tick: u64,
	
	//
	// big sloppie storage dump
	
	next_run_time: f64,
	is_active: bool,
	
	state: enum { nil, fade_in, hold, fade_out },
	alpha: f32,
	alpha_target: f32,
	end_time: f64,
	
	scratch: struct {
		hit_this_frame: bool,
	}
}

store :: proc(hash: string, tick_count: u64) -> (entry: ^Entry, first_time: bool) #optional_ok {
	init_first_time()
	
	found: bool
	entry, found = &table[hash]
	if !found {
		// insert new entry
		table[hash] = {}
		entry, _ = &table[hash]
		first_time = true
	}
	entry.last_tick = tick_count
	return
}

is_initted := false
table: map[string]Entry

init_first_time :: proc() {
	if is_initted {
		return
	}
	table = make(map[string]Entry, 1024, allocator=context.allocator)
	is_initted = true
}

// call this at the end of every frame
clear_stale :: proc(tick_count: u64) {
	init_first_time()
	
	for key, &value in table {
		// reset frame
		value.scratch = {}
		
		// clear out stale guys
		if value.last_tick < tick_count {
			delete_key(&table, key)
		}
	}
}