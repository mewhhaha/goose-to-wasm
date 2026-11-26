export const MAX_SOUNDS = 256;
export const MAX_VOICES = 64;

const MAX_HANDLE = (1n << 64n) - 1n;
const RATE_ERROR = "sample rate must be 8000..192000 Hz";
const SOUND_ERROR = "a sound that is null, released, or was never created";
const VOICE_ERROR = "voice is no longer playing";
const PARAM_ERROR = "volume must be 0..1, pan -1..1, and pitch 0.125..8 (all finite)";
const LOOKAHEAD_SECONDS = 0.04;
const PUMP_INTERVAL_MS = 10;

function validRate(rate) {
  return Number.isInteger(rate) && rate >= 8000 && rate <= 192000;
}

function validParams(volume, pan, pitch) {
  return Number.isFinite(volume) && volume >= 0 && volume <= 1
    && Number.isFinite(pan) && pan >= -1 && pan <= 1
    && Number.isFinite(pitch) && pitch >= 0.125 && pitch <= 8;
}

export class GooseAudioMixer {
  constructor(options = {}) {
    this.options = options;
    this.lastError = "";
    this._mode = null;
    this._sampleRate = 0;
    this._sounds = new Map();
    this._voices = new Map();
    this._lastId = 0n;
    this._live = null;
  }

  available() {
    return true;
  }

  _fail(message, result = false) {
    this.lastError = message;
    return result;
  }

  _checkOpenRate(rate) {
    if (this._mode) return this._fail("audio is already open; close it before opening again");
    if (!validRate(rate)) return this._fail(RATE_ERROR);
    return true;
  }

  _newHandle() {
    if (this._lastId === MAX_HANDLE) return this._fail("audio handle ids exhausted", 0n);
    return ++this._lastId;
  }

  open(sampleRate = 48000) {
    if (!this._checkOpenRate(sampleRate)) return false;
    const provided = this.options.audioContext;
    const AudioContext = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!provided && !AudioContext) return this._fail("Web Audio API is not available");

    try {
      const context = provided ?? new AudioContext({ sampleRate });
      this._live = {
        context,
        owned: !provided,
        sources: new Set(),
        timer: null,
        nextTime: context.currentTime,
        frames: Math.ceil(sampleRate * PUMP_INTERVAL_MS / 1000),
      };
      if (context.state === "closed") throw new Error("audio context is closed");
      this._sampleRate = sampleRate;
      this._mode = "live";
      const live = this._live;
      if (context.state === "suspended") {
        Promise.resolve(context.resume()).catch((error) => {
          if (this._live === live) this._fail(`Web Audio playback failed: ${error.message}`);
        });
      }
      this._pump(live);
      live.timer = setInterval(() => this._serviceLive(live), PUMP_INTERVAL_MS);
      return true;
    } catch (error) {
      this.close();
      return this._fail(`Web Audio playback failed: ${error.message}`);
    }
  }

  openOffline(sampleRate = 48000) {
    if (!this._checkOpenRate(sampleRate)) return false;
    this._sampleRate = sampleRate;
    this._mode = "offline";
    return true;
  }

  close() {
    const live = this._live;
    this._live = null;
    this._mode = null;
    this._voices.clear();
    this._sounds.clear();
    if (!live) return;
    clearInterval(live.timer);
    for (const source of live.sources) {
      source.onended = null;
      source.stop();
      source.disconnect();
    }
    live.sources.clear();
    if (live.owned && live.context.state !== "closed") {
      return Promise.resolve(live.context.close()).catch(() => {});
    }
  }

  createSound(samples, sampleRate = 48000, channels = 1) {
    if (!this._mode) return this._fail("audio is not open", 0n);
    if (!validRate(sampleRate)) return this._fail(RATE_ERROR, 0n);
    if (channels !== 1 && channels !== 2) {
      return this._fail("a sound must have one or two channels", 0n);
    }
    if (samples.length === 0 || samples.length % channels !== 0) {
      return this._fail("PCM must contain nonempty complete frames of mono or stereo samples", 0n);
    }
    if (this._sounds.size >= MAX_SOUNDS) return this._fail("all 256 sound slots are in use", 0n);
    let copy;
    try {
      copy = new Float32Array(samples);
    } catch (error) {
      if (!(error instanceof RangeError)) throw error;
      return this._fail("out of memory copying PCM samples", 0n);
    }
    for (const sample of copy) {
      if (!(sample >= -1 && sample <= 1)) {
        return this._fail("PCM samples must be finite and within [-1, 1]", 0n);
      }
    }
    const id = this._newHandle();
    if (id) this._sounds.set(id, { samples: copy, sampleRate, channels, frames: copy.length / channels });
    return id;
  }

  releaseSound(soundId) {
    if (soundId === 0n) return true;
    const sound = this._sounds.get(soundId);
    if (!sound) return this._fail(SOUND_ERROR);
    for (const [id, voice] of this._voices) {
      if (voice.sound === sound) this._voices.delete(id);
    }
    this._sounds.delete(soundId);
    return true;
  }

  play(soundId, volume = 1, pan = 0, pitch = 1, looping = false) {
    const sound = this._sounds.get(soundId);
    if (!sound) return this._fail(SOUND_ERROR, 0n);
    if (!validParams(volume, pan, pitch)) return this._fail(PARAM_ERROR, 0n);
    if (this._voices.size >= MAX_VOICES) return this._fail("all 64 voice slots are playing", 0n);

    const id = this._newHandle();
    if (id) {
      const voice = { sound, looping, position: 0 };
      this._setVoiceParams(voice, volume, pan, pitch);
      this._voices.set(id, voice);
    }
    return id;
  }

  playing(voiceId) {
    // A Wasm caller may poll synchronously while the timer cannot run.
    if (this._live && this._voices.has(voiceId)) this._serviceLive(this._live);
    return this._voices.has(voiceId);
  }

  stop(voiceId) {
    this._voices.delete(voiceId);
  }

  stopAll() {
    this._voices.clear();
  }

  _setVoiceParams(voice, volume, pan, pitch) {
    voice.leftGain = pan > 0 ? volume * (1 - pan) : volume;
    voice.rightGain = pan < 0 ? volume * (1 + pan) : volume;
    voice.step = (voice.sound.sampleRate / this._sampleRate) * pitch;
  }

  setVoice(voiceId, volume, pan, pitch) {
    const voice = this._voices.get(voiceId);
    if (!voice) return this._fail(VOICE_ERROR);
    if (!validParams(volume, pan, pitch)) return this._fail(PARAM_ERROR);
    this._setVoiceParams(voice, volume, pan, pitch);
    return true;
  }

  voicePosition(voiceId) {
    const voice = this._voices.get(voiceId);
    return voice ? voice.position / voice.sound.sampleRate : -1;
  }

  seek(voiceId, seconds) {
    const voice = this._voices.get(voiceId);
    if (!voice) return this._fail(VOICE_ERROR);
    if (!Number.isFinite(seconds) || seconds < 0) {
      return this._fail("seek needs a position of 0 or more seconds");
    }
    const { sampleRate, frames } = voice.sound;
    let position = seconds * sampleRate;
    if (voice.looping) {
      // Reduce an overflowing time by a whole number of loop periods.
      if (!Number.isFinite(position)) position = (seconds % frames) * sampleRate;
      voice.position = position % frames;
    } else {
      voice.position = Math.min(position, frames - 1);
    }
    return true;
  }

  render(out) {
    if (this._mode !== "offline") return this._fail("render requires an offline mixer");
    if (out.length % 2 !== 0) return this._fail("render requires complete stereo frames");
    this._mixInto(out, out, out.length / 2, 2, 1);
    return true;
  }

  _mixInto(left, right, frames, stride = 1, rightOffset = 0) {
    for (let frame = 0; frame < frames; frame++) {
      let mixedLeft = 0;
      let mixedRight = 0;
      for (const [id, voice] of this._voices) {
        const { samples, channels, frames: soundFrames } = voice.sound;
        const first = Math.floor(voice.position);
        const fraction = voice.position - first;
        const second = voice.looping ? (first + 1) % soundFrames : Math.min(first + 1, soundFrames - 1);
        const a = first * channels;
        const b = second * channels;
        const leftSample = samples[a] + (samples[b] - samples[a]) * fraction;
        const r = channels - 1;
        const rightSample = samples[a + r] + (samples[b + r] - samples[a + r]) * fraction;
        mixedLeft += leftSample * voice.leftGain;
        mixedRight += rightSample * voice.rightGain;

        voice.position += voice.step;
        if (voice.looping) voice.position %= soundFrames;
        else if (voice.position >= soundFrames) this._voices.delete(id);
      }
      left[frame * stride] = Math.fround(Math.max(-1, Math.min(1, mixedLeft)));
      right[frame * stride + rightOffset] = Math.fround(Math.max(-1, Math.min(1, mixedRight)));
    }
  }

  _serviceLive(live) {
    try {
      this._pump(live);
    } catch (error) {
      this._fail(`Web Audio playback failed: ${error.message}`);
      this.close();
    }
  }

  _pump(live) {
    if (this._live !== live) return;
    const { context, frames } = live;
    if (context.state === "closed") throw new Error("audio context is closed");
    if (context.state !== "running") return;
    const now = context.currentTime;
    live.nextTime = Math.max(now, live.nextTime);
    while (live.nextTime < now + LOOKAHEAD_SECONDS) {
      const buffer = context.createBuffer(2, frames, this._sampleRate);
      const source = context.createBufferSource();
      source.buffer = buffer;
      source.connect(context.destination);
      source.onended = () => {
        source.disconnect();
        live.sources.delete(source);
      };
      this._mixInto(buffer.getChannelData(0), buffer.getChannelData(1), frames);
      try {
        source.start(live.nextTime);
      } catch (error) {
        source.disconnect();
        throw error;
      }
      live.sources.add(source);
      live.nextTime += buffer.duration;
    }
  }
}

export function createAudioImports(mem, options = {}) {
  const mixer = new GooseAudioMixer(options);
  const encoder = new TextEncoder();
  // f32 slices carry an element count. The memory helper handles byte widths and alignment.
  const f32Slice = (args) => mem.readSliceArgs ? mem.readSliceArgs(args) : mem.readSliceView(args);
  const handle = (id) => BigInt.asUintN(64, id);

  const imports = {
    gs_audio_available: () => (mixer.available() ? 1 : 0),
    gs_audio_open: (rate) => (mixer.open(Number(rate)) ? 1 : 0),
    gs_audio_open_offline: (rate) => (mixer.openOffline(Number(rate)) ? 1 : 0),
    gs_audio_close() { mixer.close(); },
    gs_audio_create_sound(...args) {
      const { ptr, len, next } = f32Slice(args);
      const samples = len === 0 ? new Float32Array(0) : mem.readF32Array(ptr, len);
      return mixer.createSound(samples, Number(args[next]), Number(args[next + 1]));
    },
    gs_audio_release_sound: (id) => (mixer.releaseSound(handle(id)) ? 1 : 0),
    gs_audio_play: (id, volume, pan, pitch, looping) => mixer.play(handle(id), volume, pan, pitch, Boolean(looping)),
    gs_audio_playing: (id) => (mixer.playing(handle(id)) ? 1 : 0),
    gs_audio_stop: (id) => mixer.stop(handle(id)),
    gs_audio_stop_all: () => mixer.stopAll(),
    gs_audio_set_voice: (id, volume, pan, pitch) => (mixer.setVoice(handle(id), volume, pan, pitch) ? 1 : 0),
    gs_audio_voice_position: (id) => mixer.voicePosition(handle(id)),
    gs_audio_seek: (id, seconds) => (mixer.seek(handle(id), seconds) ? 1 : 0),
    gs_audio_render(...args) {
      const { ptr, len } = f32Slice(args);
      if (len > 0 && ptr > mem.bytes().byteLength - len * Float32Array.BYTES_PER_ELEMENT) {
        throw new RangeError("range is outside Wasm memory");
      }
      const out = new Float32Array(len);
      if (!mixer.render(out)) return 0;
      if (len > 0) mem.writeF32Array(ptr, out);
      return 1;
    },
    gs_audio_error: (out) => mem.appendBuilder(out, mixer.lastError),
    gs_audio_error_into(...args) {
      const { view } = mem.readSliceView(args);
      const message = encoder.encode(mixer.lastError);
      view.set(message.subarray(0, view.length));
      return BigInt(message.length);
    },
  };
  return { imports, mixer };
}
