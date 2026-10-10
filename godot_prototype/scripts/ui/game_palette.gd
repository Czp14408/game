class_name GamePalette
extends RefCounted
## Project semantic colors. Quality describes rarity; attribute color describes mechanics.

const BACKGROUND := Color("10151f")
const PANEL := Color("101b28")
const TEXT := Color("f3f6fa")
const MUTED := Color("aab4c4")
const FOCUS := Color("75bfff")
const DISABLED := Color("667085")
const ERROR := Color("e05263")
const ATTACK := Color("b53240")
const SHIELD := Color("f2cc60")
const POISON := Color("185c3a")
const BURN := Color("d97624")
const HEAL := Color("56c675")
const QUALITIES: Array[Color] = [Color("c28a54"), Color("d1d6e0"), Color("ebc75c"), Color("8cd9f2")]
const STAT_ORDER := ["attack", "shield", "poison", "burn", "heal"]
const ATTRIBUTES := {
	"attack": {"name": "攻击", "fill": ATTACK, "ink": TEXT},
	"shield": {"name": "护盾", "fill": SHIELD, "ink": BACKGROUND},
	"poison": {"name": "中毒", "fill": POISON, "ink": TEXT},
	"burn": {"name": "灼烧", "fill": BURN, "ink": BACKGROUND},
	"heal": {"name": "回复", "fill": HEAL, "ink": BACKGROUND},
}
