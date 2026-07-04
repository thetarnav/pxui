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

