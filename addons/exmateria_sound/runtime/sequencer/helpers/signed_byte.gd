class_name SequencerSignedByte
## Two's-complement decode for a [0..255] byte parameter.


static func decode(value: int) -> int:
	return value - 256 if value >= 128 else value
