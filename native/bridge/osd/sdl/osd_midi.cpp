/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiFM77AV40EX: MIDI stub. USE_MIDI が定義される構成のために存在が必要
	だが、FM77AV40EXでは使用しない
	I/O to boot or play - see docs/dev/DevelopmentPlan.md 0.6).
*/

#include "osd.h"

#ifdef USE_MIDI
void OSD::send_to_midi(uint8_t data)
{
}

bool OSD::recv_from_midi(uint8_t *data)
{
	return false;
}
#endif
