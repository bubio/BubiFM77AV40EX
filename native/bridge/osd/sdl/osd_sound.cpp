/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiFM77AV40EX: 音声リングバッファ。

	この実装は「OSDが自分のタイマーでvm->create_sound()を呼ぶ」という
	upstream本来の設計を前提にしており、Core threadの駆動には使っていない
	（bridge/src/bubi_fm77av.cppは`vm->run()`を壁時計ペースで直接呼ぶ）。
	`docs/dev/design.md`16.1「音声はVMの駆動源にしない」の決定に従い、WP4で
	Core threadから直接`vm->create_sound()`を呼ぶ形へ作り直す。

	`vm->run()`は`event->drive()`そのもので（vm/fm7/fm7.cpp）、
	`vm->create_sound()`は要求した`sound_samples`が溜まるまで内部で
	追加の`drive()`を呼ぶ（vm/event.cpp）。壁時計ペースの`vm->run()`と
	無関係にcreate_sound()を呼ぶと二重にVMを進めてしまうため、
	`sound_samples`を1フレーム分のサンプル数に合わせ、`vm->run()`の直後に
	`create_sound()`を呼んで「そのフレーム分を取り出すだけ」にする方針を
	`native/spike/sound/sound_pacing_spike.cpp`で検証した。
*/

#include "osd.h"

void OSD::update_sound(int* extra_frames)
{
	*extra_frames = 0;
	// Mute is for one chunk only, exactly as in win32's OSD (which clears
	// it here too, osd_sound.cpp:101): mute_sound() drops what is already
	// queued and silences whatever is in flight, and the next chunk is
	// audible again. Clearing before the early returns below matters -
	// leaving it set while the ring happens to be full would latch the
	// machine silent for the rest of the session.
	sound_muted = false;
	if(!sound_available) {
		return;
	}

	pthread_mutex_lock(&sound_mutex);
	// Keep roughly two chunks buffered - enough headroom that a host tick
	// jitter doesn't underrun, but not so much that audio (and, since
	// this is also the VM-advance trigger, gameplay) lags noticeably
	// behind host real time.
	bool need_more = sound_ring_count < 2 * sound_samples;
	pthread_mutex_unlock(&sound_mutex);
	if(!need_more) {
		// Ring buffer already has enough headroom; let this tick advance
		// the VM by exactly one frame via the plain vm->run() path in
		// EMU::run() instead.
		return;
	}

	uint16_t* sound_buffer = vm->create_sound(extra_frames);

	pthread_mutex_lock(&sound_mutex);
	if(sound_ring_buffer != NULL) {
		int16_t* src = sound_muted || sound_buffer == NULL ? NULL : (int16_t*)sound_buffer;
		for(int i = 0; i < sound_samples; i++) {
			int write_pos = (sound_ring_head + sound_ring_count) % sound_ring_capacity;
			if(sound_ring_count >= sound_ring_capacity) {
				// Ring buffer overrun: the host is not draining fast enough.
				// Drop the oldest frame rather than block the emulation
				// thread or grow the buffer unbounded.
				sound_ring_head = (sound_ring_head + 1) % sound_ring_capacity;
				sound_ring_count--;
			}
			if(src != NULL) {
				sound_ring_buffer[write_pos * 2 + 0] = src[i * 2 + 0];
				sound_ring_buffer[write_pos * 2 + 1] = src[i * 2 + 1];
			} else {
				sound_ring_buffer[write_pos * 2 + 0] = 0;
				sound_ring_buffer[write_pos * 2 + 1] = 0;
			}
			sound_ring_count++;
		}
	}
	pthread_mutex_unlock(&sound_mutex);
}

int OSD::pull_sound(int16_t* dst, int frames)
{
	pthread_mutex_lock(&sound_mutex);
	int n = frames < sound_ring_count ? frames : sound_ring_count;
	for(int i = 0; i < n; i++) {
		int read_pos = (sound_ring_head + i) % sound_ring_capacity;
		dst[i * 2 + 0] = sound_ring_buffer[read_pos * 2 + 0];
		dst[i * 2 + 1] = sound_ring_buffer[read_pos * 2 + 1];
	}
	sound_ring_head = (sound_ring_head + n) % sound_ring_capacity;
	sound_ring_count -= n;
	pthread_mutex_unlock(&sound_mutex);
	return n;
}

int OSD::get_buffered_sound_frames()
{
	pthread_mutex_lock(&sound_mutex);
	int n = sound_ring_count;
	pthread_mutex_unlock(&sound_mutex);
	return n;
}

void OSD::mute_sound()
{
	// Throw away the audio still queued, which is what win32 does by
	// zeroing its DirectSound buffer here. Callers reach for this after
	// replacing the machine underneath the sound (a state load), where
	// what is already in the ring belongs to a machine that no longer
	// exists.
	pthread_mutex_lock(&sound_mutex);
	sound_ring_head = sound_ring_count = 0;
	pthread_mutex_unlock(&sound_mutex);
	sound_muted = true;
}

void OSD::stop_sound()
{
	sound_muted = true;
	pthread_mutex_lock(&sound_mutex);
	sound_ring_head = sound_ring_count = 0;
	pthread_mutex_unlock(&sound_mutex);
}

void OSD::start_record_sound()
{
	// Sound recording is a host UI feature; not implemented on the core
	// side (phase 0.6 group B).
}

void OSD::stop_record_sound()
{
	now_record_sound = false;
}

void OSD::restart_record_sound()
{
}
