// PCM playback and offline stereo mixing through the Web host.
namespace audio;

let MAX_SOUNDS = 256;
let MAX_VOICES = 64;

struct Sound { id: u64 }
struct Voice { id: u64 }

extern fn detail::available() -> bool = "gs_audio_available";
extern fn detail::open(sample_rate: i64) -> bool = "gs_audio_open";
extern fn detail::open_offline(sample_rate: i64) -> bool = "gs_audio_open_offline";
extern fn detail::close() = "gs_audio_close";
extern fn detail::create_sound(samples: const f32[:], sample_rate: i64, channels: i64) -> u64 = "gs_audio_create_sound";
extern fn detail::release_sound(sound_id: u64) -> bool = "gs_audio_release_sound";
extern fn detail::play(sound_id: u64, volume: f64, pan: f64, pitch: f64, looping: bool) -> u64 = "gs_audio_play";
extern fn detail::playing(voice_id: u64) -> bool = "gs_audio_playing";
extern fn detail::stop(voice_id: u64) = "gs_audio_stop";
extern fn detail::stop_all() = "gs_audio_stop_all";
extern fn detail::set_voice(voice_id: u64, volume: f64, pan: f64, pitch: f64) -> bool = "gs_audio_set_voice";
extern fn detail::voice_position(voice_id: u64) -> f64 = "gs_audio_voice_position";
extern fn detail::seek(voice_id: u64, seconds: f64) -> bool = "gs_audio_seek";
extern fn detail::render(out: f32[:]) -> bool = "gs_audio_render";
extern fn detail::error_append(out: u8[>..]&) = "gs_audio_error";
extern fn detail::error_into(out: u8[:]) -> i64 = "gs_audio_error_into";

fn available() -> bool { detail::available() }
fn open(sample_rate: i64 = 48000) -> bool { detail::open(sample_rate) }
fn open_offline(sample_rate: i64 = 48000) -> bool { detail::open_offline(sample_rate) }
fn close() { detail::close() }

fn create_sound(samples: const f32[:], sample_rate: i64 = 48000, channels: i64 = 1) -> Sound {
    return Sound { id: detail::create_sound(samples, sample_rate, channels) };
}
fn release_sound(sound: Sound) -> bool { detail::release_sound(sound.id) }

fn play(sound: Sound, volume: f64 = 1.0, pan: f64 = 0.0, pitch: f64 = 1.0,
        looping: bool = false) -> Voice {
    return Voice { id: detail::play(sound.id, volume, pan, pitch, looping) };
}
fn playing(voice: Voice) -> bool { detail::playing(voice.id) }
fn stop(voice: Voice) { detail::stop(voice.id) }
fn stop_all() { detail::stop_all() }
fn set_voice(voice: Voice, volume: f64, pan: f64, pitch: f64) -> bool {
    return detail::set_voice(voice.id, volume, pan, pitch);
}
fn voice_position(voice: Voice) -> f64 { detail::voice_position(voice.id) }
fn seek(voice: Voice, seconds: f64) -> bool { detail::seek(voice.id, seconds) }
fn render(out: f32[:]) -> bool { detail::render(out) }

fn error() -> u8[>..] {
    var out: u8[>..] = [];
    detail::error_append(out);
    return out;
}
fn error_into(out: u8[:]) -> i64 { detail::error_into(out) }
