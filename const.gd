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

const PURPOSE_STR: Dictionary[Purpose, String] = {
	Purpose.NIL:       "NIL",
	Purpose.DRAG:      "DRAG",
	Purpose.PILE_VIEW: "PILE_VIEW",
	Purpose.PILE_INPUT_TOP:     "PILE_INPUT_TOP",
	Purpose.PILE_INPUT_BOTTOM:  "PILE_INPUT_BOTTOM",
	Purpose.PILE_INPUT_RANDOM:  "PILE_INPUT_RANDOM",
	Purpose.PILE_OUTPUT_TOP:    "PILE_OUTPUT_TOP",
	Purpose.PILE_OUTPUT_BOTTOM: "PILE_OUTPUT_BOTTOM",
	Purpose.PILE_OUTPUT_RANDOM: "PILE_OUTPUT_RANDOM",
}

enum CardSource {
	TOP = 0,
	BOTTOM = 1,
	RANDOM = 2,
}

const SOURCE_STR: Dictionary[CardSource, String] = {
	CardSource.TOP: "TOP",
	CardSource.BOTTOM: "BOTTOM",
	CardSource.RANDOM: "RANDOM",
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
