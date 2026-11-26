import std;
import math;
import json;
import os;
import slice_pool;
import audio;

const SAMPLE_RATE = 48000;
const FRAMES = 28800;

fn make_chime(samples: f32[:], hz: f64) {
    for i in samples.len {
        let time = (i as f64) / (SAMPLE_RATE as f64);
        let edge = min(i, samples.len - 1 - i);
        let fade = min(1.0, (edge as f64) / 480.0);
        let wave = sin(2.0 * PI * hz * time);
        samples[i] = (0.45 * wave * fade * exp(-5.0 * time)) as f32;
    }
}

fn main() {
    assert(make_dir("/demo"));
    assert(write_file("/demo/chime.json", "{\"frequencyHz\": 440}"));

    var input: u8[>..] = [];
    assert(read_file("/demo/chime.json", input));
    var document: json::Node[>..] = [];
    var scratch: u8[>..] = [];
    let root, parse_error = json::parse(input, document, scratch);
    if root == null { abort(parse_error); }
    let hz, is_number = json::as_f64(json::member(root, "frequencyHz"));
    assert(is_number);

    var pool = slice_pool<f32> {};
    let initial = pool.alloc_slice(64);
    let samples = pool.realloc_slice(initial, FRAMES);
    make_chime(samples, hz);

    if !audio::open_offline(SAMPLE_RATE) { abort(audio::error()); }
    let sound = audio::create_sound(samples, SAMPLE_RATE);
    let voice = audio::play(sound);
    if !audio::playing(voice) { abort(audio::error()); }
    var stereo: f32[>..] = [];
    stereo.resize(FRAMES * 2, 0.0);
    if !audio::render(stereo) { abort(audio::error()); }
    var peak: f32 = 0.0;
    for sample in stereo { peak = max(peak, abs(sample)); }
    audio::close();

    var report: u8[>..] = [];
    report.append("{\"frequencyHz\":");
    json::format_number(report, hz);
    report.append(",\"frames\":");
    json::format_int(report, FRAMES);
    report.append(",\"peak\":");
    json::format_number(report, peak as f64);
    report.append("}\n");
    assert(write_file("/demo/report.json", report));

    var listing: u8[>..] = [];
    assert(list_dir("/demo", listing));
    print("chime ", report[..report.len - 1]);
    print("files /demo");
    write_stdout(listing);

    for arg in args() {
        if arg == "--play" {
            if !audio::open(SAMPLE_RATE) { abort(audio::error()); }
            let live_sound = audio::create_sound(samples, SAMPLE_RATE);
            let live_voice = audio::play(live_sound);
            if !audio::playing(live_voice) { abort(audio::error()); }
            print("playback started");
            break;
        }
    }
    pool.free_slice(samples);
}
