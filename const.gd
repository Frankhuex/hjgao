class_name Const

enum Purpose {
	NIL = 0,
	DRAG = 1,
	PILE_VIEW = 2,
	PILE_INPUT_TOP     = 3,
	PILE_INPUT_BOTTOM  = 4,
	PILE_INPUT_RANDOM  = 5,
	PILE_OUTPUT_TOP    = 6,
	PILE_OUTPUT_BOTTOM = 7,
	PILE_OUTPUT_RANDOM = 8,
}

enum CardSource {
	TOP = 0,
	BOTTOM = 1,
	RANDOM = 2,
}

const INPUT_SOURCE_TO_PURPOSE: Dictionary[CardSource, Purpose] = {
	CardSource.TOP:    Purpose.PILE_INPUT_TOP,
	CardSource.BOTTOM: Purpose.PILE_INPUT_BOTTOM,
	CardSource.RANDOM: Purpose.PILE_INPUT_RANDOM,
}

const OUTPUT_SOURCE_TO_PURPOSE: Dictionary[CardSource, Purpose] = {
	CardSource.TOP:    Purpose.PILE_OUTPUT_TOP,
	CardSource.BOTTOM: Purpose.PILE_OUTPUT_BOTTOM,
	CardSource.RANDOM: Purpose.PILE_OUTPUT_RANDOM,
}

const PURPOSE_TO_SOURCE: Dictionary[Purpose, CardSource] = {
	Purpose.PILE_INPUT_TOP:     CardSource.TOP,
	Purpose.PILE_INPUT_BOTTOM:  CardSource.BOTTOM,
	Purpose.PILE_INPUT_RANDOM:  CardSource.RANDOM,
	Purpose.PILE_OUTPUT_TOP:    CardSource.TOP,
	Purpose.PILE_OUTPUT_BOTTOM: CardSource.BOTTOM,
	Purpose.PILE_OUTPUT_RANDOM: CardSource.RANDOM,
}
