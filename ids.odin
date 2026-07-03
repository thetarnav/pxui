package pixui

// Mix two u64s into one. Used to combine parent_id and child_index into a
// stable widget id. Bit-mixing function (Murmur-style finalizer) — avoids
// the trivial collisions you get from plain XOR on sequential indices.
hash_combine :: proc (a, b: u64) -> u64 {
	x := a ~ b
	x = x ~ (x >> 33)
	x *= 0xff51afd7ed558ccd
	x = x ~ (x >> 33)
	x *= 0xc4ceb9fe1a85ec53
	x = x ~ (x >> 33)
	return x
}

// Hash a string with FNV-1a 64-bit. Cheap, deterministic, no allocations.
hash_string :: proc (s: string) -> u64 {
	h: u64 = 0xcbf29ce484222325
	for b in s {
		h = h ~ u64(b)
		h *= 0x100000001b3
	}
	return h
}
