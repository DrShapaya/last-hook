# Composes the four music loops of Last Hook and writes them as looping Ogg
# Vorbis files into game/assets/music (or the folder given as the first argument).
#   camp.ogg     menu: warm F major, nylon guitar, kalimba tune, flute in the bridge
#   mountain.ogg standard mountain: bright D major folk, flute, whistle, shaker
#   desert.ogg   canyon: D hijaz, santur ostinato, oud, ney, doumbek
#   winter.ogg   snowy summit: A minor, soft piano, celesta, flute, sleigh bells
# Each track is a song with sections (intro, verses, bridge, outro) rather than
# one repeated pattern, so a long climb keeps changing. Notes sit exactly on the
# beat grid. Every voice is additive synthesis in numpy, panned into a stereo
# field and glued by a synthetic hall. The ringing tail is folded back onto the
# start, so the files loop without a click. The master stays clean: no
# waveshaping, only a transparent look-ahead limiter on the rare peak.
# Needs numpy and soundfile. Run: python tools/make_music.py
import functools, math, os, sys
import numpy as np
import soundfile

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "music")
NOTE = {"C":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"E":4,"F":5,"F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11}
TARGET_RMS = 10 ** (-16.5 / 20)
CEILING = 10 ** (-1.5 / 20)

@functools.lru_cache(maxsize=None)
def hz(name):
    # "A4" -> 440 Hz, "F#3", "Bb2"...
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[pitch] + 12 * (octave + 1) - 69) / 12)

def in_scale(names, scale):
    # A typo in a melody is a wrong note nobody would catch by reading.
    allowed = {NOTE[n] for n in scale}
    for name in names:
        if NOTE[name[:-1]] not in allowed:
            raise ValueError(f"{name} is outside {scale}")

class Track:
    def __init__(self, bpm, bars, beats=4):
        self.beat = 60.0 / bpm
        self.bars = bars
        self.beats = beats
        self.length = int(round(bars * beats * self.beat * SR))
        self.tail = int(5.0 * SR)
        self.dry = np.zeros((self.length + self.tail, 2))
        self.send = np.zeros((self.length + self.tail, 2))
        self.rng = np.random.default_rng(7)

    def at(self, beat):
        return int(round(beat * self.beat * SR))

    def add(self, start_beat, signal, gain, pan=0.0, reverb=.3):
        # Equal-power pan: -1 left, 1 right.
        start = self.at(start_beat)
        end = min(start + len(signal), len(self.dry))
        if end <= start: return
        angle = (pan + 1) * math.pi / 4
        part = signal[:end - start] * gain
        sides = np.stack((part * math.cos(angle), part * math.sin(angle)), axis=1)
        self.dry[start:end] += sides
        self.send[start:end] += sides * reverb

    def render(self, wet=.3, seconds=2.2):
        hall = reverb(self.send, seconds)
        mix = self.dry + hall * wet
        # Fold the ringing tail onto the start: a seamless loop.
        loop = mix[:self.length].copy()
        loop[:self.tail] += mix[self.length:self.length + self.tail]
        loop = highpass(loop, 32.0)
        loop *= TARGET_RMS / np.sqrt(np.mean(loop ** 2))
        return limit(loop)

def highpass(x, cutoff):
    spectrum = np.fft.rfft(x, axis=0)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spectrum *= (1 / np.sqrt(1 + (cutoff / np.maximum(freqs, 1.0)) ** 4))[:, None]
    return np.fft.irfft(spectrum, len(x), axis=0)

def limit(x):
    # Look-ahead gain riding: the gain sinks smoothly before a peak arrives,
    # so loud moments get quieter instead of distorted. Runs round the loop.
    block = int(.002 * SR)
    count = len(x) // block
    peak = np.abs(x[:count * block]).max(axis=1).reshape(count, block).max(axis=1)
    gain = np.minimum(1.0, CEILING / np.maximum(peak, 1e-9))
    span = 5
    wide = np.stack([np.roll(gain, shift) for shift in range(-span, span + 1)]).min(axis=0)
    window = np.hanning(2 * span + 3)
    window /= window.sum()
    pad = len(window)
    smooth = np.convolve(np.concatenate((wide[-pad:], wide, wide[:pad])), window, "same")[pad:-pad]
    curve = np.interp(np.arange(len(x)), (np.arange(count) + .5) * block, smooth, period=count * block)
    return np.clip(x * curve[:, None], -CEILING, CEILING)

def reverb(x, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    size = 1 << int(math.ceil(math.log2(len(x) + n)))
    out = np.empty_like(x)
    # A different impulse per side keeps the hall wide; the darkening is a
    # moving average, the pre-delay keeps the attack of the note dry.
    for side, seed in enumerate((3, 11)):
        rng = np.random.default_rng(seed)
        ir = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
        ir = np.convolve(ir, np.ones(12) / 12, mode="same")
        ir[:int(.022 * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        out[:, side] = np.fft.irfft(np.fft.rfft(x[:, side], size) * np.fft.rfft(ir, size), size)[:len(x)]
    return out

def timeline(seconds):
    n = int(seconds * SR)
    return n, np.arange(n) / SR

def fade_out(out, seconds=.012):
    # A note never ends on a non-zero sample: that would be a click.
    n = min(int(seconds * SR), len(out))
    out[-n:] *= np.linspace(1, 0, n)
    return out

def env(n, attack, release, total):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    rel_start = max(total - release, attack)
    e *= np.clip(1.0 - (t - rel_start) / max(release, 1e-4), 0.0, 1.0)
    return e

def additive(freq, t, partials):
    out = np.zeros(len(t))
    for ratio, amp, decay in partials:
        if freq * ratio < SR * .46:
            out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * decay)
    return out

def band_noise(n, low, high, rng):
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spectrum[(freqs < low) | (freqs > high)] = 0
    out = np.fft.irfft(spectrum, n)
    return out / (np.max(np.abs(out)) + 1e-9)

# --- Voices. Cached: a pitch sounds the same each time and costs nothing twice.

@functools.lru_cache(maxsize=None)
def guitar(freq, seconds=2.2):
    n, t = timeline(seconds)
    partials = [(k * (1 + .00025 * k * k), 1.0 / k ** 1.5, 1.5 + 1.1 * k) for k in range(1, 11)]
    return fade_out(additive(freq, t, partials) * np.minimum(1.0, t / .003) * .55)

@functools.lru_cache(maxsize=None)
def harp(freq, seconds=2.6):
    n, t = timeline(seconds)
    partials = [(k * (1 + .0004 * k * k), 1.0 / k ** 1.8, 1.2 + 1.4 * k) for k in range(1, 8)]
    return fade_out(additive(freq, t, partials) * np.minimum(1.0, t / .006) * .6)

@functools.lru_cache(maxsize=None)
def kalimba(freq, seconds=1.8):
    n, t = timeline(seconds)
    partials = ((1.0, 1.0, 3.2), (3.0, .16, 9.0), (5.6, .06, 18.0))
    return fade_out(additive(freq, t, partials) * np.minimum(1.0, t / .002) * .7)

@functools.lru_cache(maxsize=None)
def oud(freq, seconds=1.3):
    n, t = timeline(seconds)
    partials = [(k, 1.0 / k ** 1.25, 3.0 + 2.0 * k) for k in range(1, 10)]
    return fade_out(additive(freq, t, partials) * np.minimum(1.0, t / .003) * .6)

@functools.lru_cache(maxsize=None)
def santur(freq, seconds=1.5):
    # Two slightly detuned strings struck by a light hammer.
    n, t = timeline(seconds)
    partials = ((1.0, 1.0, 3.6), (2.0, .4, 6.0), (3.0, .2, 9.0), (4.1, .08, 16.0))
    out = additive(freq, t, partials) + additive(freq * 1.0016, t, partials)
    return fade_out(out * np.minimum(1.0, t / .002) * .36)

@functools.lru_cache(maxsize=None)
def bell(freq, seconds=3.0):
    n, t = timeline(seconds)
    partials = ((1.0, 1.0, 1.3), (2.0, .4, 2.0), (3.01, .16, 3.0), (4.16, .08, 4.0))
    return fade_out(additive(freq, t, partials) * np.minimum(1.0, t / .003) * .5)

@functools.lru_cache(maxsize=None)
def celesta(freq, seconds=2.2):
    n, t = timeline(seconds)
    partials = ((1.0, 1.0, 2.2), (4.0, .22, 7.0), (10.0, .05, 18.0))
    return fade_out(additive(freq, t, partials) * np.minimum(1.0, t / .002) * .6)

@functools.lru_cache(maxsize=None)
def piano(freq, seconds=3.0):
    n, t = timeline(seconds)
    partials = [(k * (1 + .0006 * k * k), 1 / k ** 1.6, .9 + .8 * k) for k in range(1, 8)]
    return fade_out(additive(freq, t, partials) * np.minimum(1.0, t / .006) * .6)

def flute(freq, seconds, rng, vibrato=.005, breath=.05):
    n, t = timeline(seconds)
    vib = 1 + vibrato * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - .2) / .35, 0, 1)
    phase = 2 * np.pi * freq * np.cumsum(vib) / SR
    out = np.sin(phase) + .2 * np.sin(2 * phase) + .05 * np.sin(3 * phase)
    air = band_noise(n, freq * .9, min(freq * 3, 9000), rng) * breath
    return (out + air) * env(n, .06, .16, seconds) * .5

def ney(freq, seconds, rng):
    # Breathier than the flute, and it scoops up into each note.
    n, t = timeline(seconds)
    scoop = 1 - .03 * np.exp(-t * 14)
    vib = 1 + .007 * np.sin(2 * np.pi * 4.3 * t) * np.clip((t - .25) / .4, 0, 1)
    phase = 2 * np.pi * freq * np.cumsum(vib * scoop) / SR
    out = np.sin(phase) + .1 * np.sin(2 * phase) + .12 * np.sin(3 * phase)
    air = band_noise(n, freq, min(freq * 4, 9000), rng) * .16
    return (out + air) * env(n, .09, .2, seconds) * .5

def pad(freqs, seconds, rng, bright=.14):
    n, t = timeline(seconds)
    out = np.zeros(n)
    for f in freqs:
        for detune in (-.0028, 0.0, .0033):
            phase = rng.uniform(0, 2 * np.pi)
            wobble = 1 + .0012 * np.sin(2 * np.pi * .21 * t + phase)
            ph = 2 * np.pi * f * (1 + detune) * np.cumsum(wobble) / SR + phase
            out += np.sin(ph) + bright * np.sin(2 * ph) + .3 * bright * np.sin(3 * ph)
    return out / (3 * len(freqs)) * env(n, min(1.0, seconds * .3), min(1.3, seconds * .4), seconds)

@functools.lru_cache(maxsize=None)
def bass(freq, seconds):
    # The upper partials carry the bass line on phone speakers.
    n, t = timeline(seconds)
    out = np.sin(2 * np.pi * freq * t) + .4 * np.sin(4 * np.pi * freq * t) + .18 * np.sin(6 * np.pi * freq * t)
    return out * env(n, .012, .1, seconds) * np.exp(-t * 1.1) * .6

@functools.lru_cache(maxsize=None)
def kick(seconds=.28):
    n, t = timeline(seconds)
    f = 58 + 60 * np.exp(-t * 34)
    return fade_out(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 13) * np.minimum(1.0, t / .001))

def frame_drum(rng, tone=110, seconds=.42):
    n, t = timeline(seconds)
    body = np.sin(2 * np.pi * np.cumsum(tone + 34 * np.exp(-t * 28)) / SR) * np.exp(-t * 11)
    skin = band_noise(n, 300, 3000, rng) * np.exp(-t * 55) * .35
    return fade_out((body + skin) * np.minimum(1.0, t / .001) * .8)

def tek(rng, seconds=.14):
    # The rim of the doumbek: short and woody.
    n, t = timeline(seconds)
    ring = np.sin(2 * np.pi * 620 * t) * np.exp(-t * 46) + .5 * np.sin(2 * np.pi * 1130 * t) * np.exp(-t * 60)
    skin = band_noise(n, 900, 5000, rng) * np.exp(-t * 90) * .4
    return fade_out((ring + skin) * np.minimum(1.0, t / .0008) * .55)

def shaker(rng, seconds=.1, accent=1.0):
    n, t = timeline(seconds)
    return fade_out(band_noise(n, 4500, 13000, rng) * np.exp(-t * 48) * np.minimum(1, t / .007) * .5 * accent)

def sleigh(rng, seconds=.16, accent=1.0):
    # Small bells: a few high partials over a soft shimmer.
    n, t = timeline(seconds)
    out = sum(np.sin(2 * np.pi * f * t) for f in (5200, 6930, 8110)) / 3
    return fade_out((out * .5 + band_noise(n, 6000, 13000, rng) * .5) * np.exp(-t * 32) * np.minimum(1, t / .004) * .5 * accent)

def chord(names):
    return [hz(n) for n in names]

def play_tune(tr, voice, tune, start, gain, pan, reverb, scale, length=.95):
    in_scale([name for name, _at, _dur in tune], scale)
    for name, at, dur in tune:
        tr.add(start + at, voice(hz(name), dur * tr.beat * length), gain, pan, reverb)

# --- Compositions ------------------------------------------------------------------

def camp():
    tr = Track(76, 40)
    rng = tr.rng
    major = ["F", "G", "A", "Bb", "C", "D", "E"]
    verse = [["F3","A3","C4","F4"],["A2","A3","C4","E4"],["Bb2","Bb3","D4","F4"],["C3","G3","C4","E4"],
             ["D3","A3","D4","F4"],["Bb2","Bb3","D4","F4"],["G2","Bb3","D4","G4"],["C3","G3","C4","E4"]]
    bridge = [["Bb2","Bb3","D4","F4"],["F3","A3","C4","F4"],["G2","Bb3","D4","G4"],["D3","A3","D4","F4"],
              ["Bb2","Bb3","D4","F4"],["F3","A3","C4","F4"],["G2","Bb3","D4","G4"],["C3","G3","C4","E4"]]
    tune = [("C5",0,1.5),("A4",1.5,.5),("C5",2,2),("E5",4,1.5),("D5",5.5,.5),("C5",6,2),
            ("D5",8,1),("F5",9,1),("D5",10,2),("C5",12,1),("E5",13,1),("G5",14,2),
            ("A5",16,1.5),("G5",17.5,.5),("F5",18,2),("D5",20,1),("F5",21,1),("F5",22,2),
            ("G5",24,1),("F5",25,1),("D5",26,2),("E5",28,1),("C5",29,1),("C5",30,2)]
    answer = [("F5",0,1),("D5",1,1),("Bb4",2,2),("C5",4,1),("A4",5,1),("C5",6,2),
              ("D5",8,1),("Bb4",9,1),("G4",10,2),("A4",12,1),("D5",13,1),("F5",14,2),
              ("F5",16,1.5),("G5",17.5,.5),("F5",18,1),("D5",19,1),("C5",20,1.5),("D5",21.5,.5),("C5",22,1),("A4",23,1),
              ("Bb4",24,1),("D5",25,1),("G5",26,2),("E5",28,2),("C5",30,2)]
    sections = [("intro",4),("verse",8),("tune",8),("bridge",8),("full",8),("intro",4)]
    bar = 0
    for section, count in sections:
        for index in range(count):
            b0 = bar * 4
            notes = (bridge if section == "bridge" else verse)[index % 8] if section != "intro" else verse[(0, 2, 0, 7)[index]]
            tr.add(b0, pad(chord(notes[1:]), 4 * tr.beat + 1.0, rng, .1), .34, 0, .6)
            if section != "intro":
                tr.add(b0, bass(hz(notes[0]) / 2, 3.4 * tr.beat), .34, 0, .08)
            # Fingerpicked guitar: thumb on the root, fingers over the top.
            picks = [0, 2, 1, 3, 2, 1, 2, 3] if index % 2 == 0 else [0, 3, 1, 2, 3, 1, 2, 1]
            for step, which in enumerate(picks):
                if section == "intro" and step % 2: continue
                tr.add(b0 + step * .5, guitar(hz(notes[which])), .32 if step % 2 == 0 else .24, -.3, .3)
            if section == "full":
                tr.add(b0 + 3, harp(hz(notes[3]) * 2), .16, .55, .6)
            bar += 1
    play_tune(tr, kalimba, tune, 4 * 12, .34, .35, .5, major)
    play_tune(tr, lambda f, s: flute(f, s, rng), answer, 4 * 20, .3, .2, .55, major)
    play_tune(tr, kalimba, tune, 4 * 28, .34, .35, .5, major)
    play_tune(tr, lambda f, s: bell(f), tune[::4], 4 * 28, .1, -.45, .7, major)
    return tr.render(.3)

def mountain():
    tr = Track(96, 64)
    rng = tr.rng
    major = ["D", "E", "F#", "G", "A", "B", "C#"]
    verse_a = [["D3","A3","D4","F#4"],["G2","G3","B3","D4"],["B2","F#3","B3","D4"],["A2","E3","A3","C#4"]]
    verse_b = [["D3","A3","D4","F#4"],["G2","G3","B3","D4"],["E3","G3","B3","E4"],["A2","E3","A3","C#4"]]
    chorus = [["G2","G3","B3","D4"],["A2","E3","A3","C#4"],["F#2","F#3","A3","C#4"],["B2","F#3","B3","D4"],
              ["G2","G3","B3","D4"],["A2","E3","A3","C#4"],["D3","A3","D4","F#4"],["D3","A3","D4","F#4"]]
    bridge = [["B2","F#3","B3","D4"],["G2","G3","B3","D4"],["D3","A3","D4","F#4"],["A2","E3","A3","C#4"]]
    phrase_a = [("F#5",0,1),("A5",1,1),("B5",2,1.5),("A5",3.5,.5),("B5",4,1),("A5",5,1),("G5",6,2),
                ("F#5",8,1),("D5",9,1),("F#5",10,1.5),("G5",11.5,.5),("A5",12,1.5),("G5",13.5,.5),("E5",14,2)]
    phrase_b = [("F#5",0,1),("A5",1,1),("D6",2,1.5),("C#6",3.5,.5),("B5",4,1),("A5",5,1),("G5",6,1),("B5",7,1),
                ("G5",8,1),("F#5",9,1),("E5",10,1),("G5",11,1),("E5",12,2),("C#5",14,2)]
    hook = [("D6",0,1),("B5",1,1),("G5",2,1),("B5",3,1),("C#6",4,1),("A5",5,1),("E5",6,1),("A5",7,1),
            ("F#5",8,1),("A5",9,1),("C#6",10,2),("B5",12,1.5),("A5",13.5,.5),("F#5",14,2),
            ("G5",16,1),("B5",17,1),("D6",18,1),("B5",19,1),("A5",20,1),("C#6",21,1),("E6",22,2),
            ("D6",24,3),("A5",27,1),("F#5",28,4)]
    long_tones = [("D5",0,4),("B4",4,4),("A4",8,4),("C#5",12,4),("F#5",16,4),("D5",20,4),("A5",24,4),("E5",28,4)]
    # (name, bars, chord cycle, drums 0-2, picking on)
    sections = [("intro",4,verse_a,0),("verse",8,verse_a,1),("verse",8,verse_b,1),("chorus",8,chorus,2),
                ("break",4,verse_a,0),("verse",8,verse_a,1),("verse",8,verse_b,2),("bridge",8,bridge,0),("chorus",8,chorus,2)]
    bar = 0
    marks = {}
    for section, count, cycle, drums in sections:
        marks.setdefault(section, []).append(bar)
        for index in range(count):
            b0 = bar * 4
            notes = cycle[index % len(cycle)]
            tr.add(b0, pad(chord(notes[1:]), 4 * tr.beat + .7, rng), .2, 0, .5)
            if section not in ("intro", "break"):
                root = hz(notes[0])
                tr.add(b0, bass(root, 1.8 * tr.beat), .3, 0, .05)
                tr.add(b0 + 2, bass(root * 1.5, .9 * tr.beat), .22, 0, .05)
                tr.add(b0 + 3, bass(root, .9 * tr.beat), .24, 0, .05)
            picks = [0, 2, 3, 1, 2, 3, 1, 3] if section != "chorus" else [0, 3, 1, 3, 2, 3, 1, 3]
            for step, which in enumerate(picks):
                if section == "bridge" and step % 2: continue
                tr.add(b0 + step * .5, guitar(hz(notes[which]), 1.5), .3 if step % 2 == 0 else .22, -.35, .22)
            if section == "bridge":
                for step, which in enumerate((3, 2, 3, 1)):
                    tr.add(b0 + step, kalimba(hz(notes[which]) * 2), .17, .4, .5)
            if drums:
                for step in range(8):
                    tr.add(b0 + step * .5, shaker(rng, accent=1.0 if step % 2 else .55), .15, .3, .12)
                tr.add(b0, kick(), .36, 0, .03)
                tr.add(b0 + 2, kick(), .28, 0, .03)
            if drums == 2:
                tr.add(b0 + 1, frame_drum(rng, 170, .25), .13, -.2, .15)
                tr.add(b0 + 3, frame_drum(rng, 170, .25), .13, -.2, .15)
                tr.add(b0 + 3.5, kick(), .2, 0, .03)
            bar += 1
    lead = lambda f, s: flute(f, s, rng)
    whistle = lambda f, s: flute(f, s, rng, .0035, .03)
    counter = [(n, a, d) for n, a, d in phrase_a[::2]]
    for start, phrase in zip(marks["verse"], (phrase_a, phrase_b, phrase_a, phrase_b)):
        play_tune(tr, lead, phrase, start * 4, .4, .15, .45, major)
    # The second half of a verse breathes: the flute rests, the kalimba answers.
    play_tune(tr, kalimba, counter, (marks["verse"][0] + 4) * 4, .2, .45, .5, major)
    play_tune(tr, kalimba, counter, (marks["verse"][2] + 4) * 4, .2, .45, .5, major)
    for start in marks["chorus"]:
        play_tune(tr, whistle, hook, start * 4, .34, .2, .4, major)
        play_tune(tr, kalimba, [(n, a, d) for n, a, d in hook if a % 2 == 0], start * 4, .13, -.5, .5, major)
    play_tune(tr, whistle, long_tones, marks["bridge"][0] * 4, .26, .1, .7, major, .98)
    return tr.render(.26)

def desert():
    tr = Track(84, 56)
    rng = tr.rng
    hijaz = ["D", "Eb", "F#", "G", "A", "Bb", "C"]
    ost = ["D4","A3","Eb4","D4","F#4","D4","Eb4","A3"]
    ost_high = ["D5","A4","F#4","G4","A4","F#4","Eb4","D4"]
    lead_a = [("A4",0,1),("Bb4",1,.5),("A4",1.5,.5),("G4",2,1),("F#4",3,1),("G4",4,1.5),("A4",5.5,.5),("Bb4",6,2),
              ("C5",8,1),("Bb4",9,.5),("A4",9.5,.5),("G4",10,1),("A4",11,1),("F#4",12,1),("Eb4",13,1),("D4",14,2),
              ("D5",16,1.5),("C5",17.5,.5),("Bb4",18,1),("A4",19,1),("Bb4",20,.5),("A4",20.5,.5),("G4",21,1),("A4",22,2),
              ("F#4",24,1),("G4",25,1),("Eb4",26,1),("D4",27,5)]
    lead_b = [("D5",0,2),("Eb5",2,1),("D5",3,1),("C5",4,1.5),("Bb4",5.5,.5),("A4",6,2),
              ("Bb4",8,1),("C5",9,1),("D5",10,1),("Eb5",11,1),("F#5",12,2),("D5",14,2),
              ("G5",16,1.5),("F#5",17.5,.5),("Eb5",18,1),("D5",19,1),("C5",20,1),("Bb4",21,1),("A4",22,2),
              ("Bb4",24,1),("A4",25,1),("G4",26,1),("F#4",27,1),("D4",28,4)]
    sections = [("drone",4),("groove",8),("lead",8),("lead",8),("break",8),("high",8),("high",4),("lead",4),("drone",4)]
    bar = 0
    marks = {}
    for section, count in sections:
        marks.setdefault(section, []).append(bar)
        for index in range(count):
            b0 = bar * 4
            if index % 4 == 0:
                tr.add(b0, pad([hz("D3"), hz("A3"), hz("D4")], min(4, count - index) * 4 * tr.beat + .8, rng), .26, 0, .5)
            if index % 8 == 2 and section in ("lead", "high", "groove"):
                tr.add(b0, pad(chord(["G3","Bb3","D4"]), 4 * tr.beat, rng), .13, -.2, .6)
            if index % 8 == 3 and section in ("lead", "high", "groove"):
                tr.add(b0 + 2, pad(chord(["Eb3","G3","Bb3"]), 2 * tr.beat + .6, rng), .16, .2, .6)
            if section != "drone":
                tr.add(b0, bass(hz("D2") * 2, 1.7 * tr.beat), .3, 0, .05)
                if index % 2: tr.add(b0 + 2.5, bass(hz("A1") * 2, 1.2 * tr.beat), .22, 0, .05)
            if section in ("groove", "lead", "high"):
                pattern = ost_high if section == "high" and index % 2 else ost
                for step, name in enumerate(pattern):
                    if index % 8 >= 6 and step in (2, 6) and pattern is ost: name = "C4"
                    tr.add(b0 + step * .5, santur(hz(name)), .28 if step % 2 == 0 else .2, .4, .3)
                # Maqsum: dum tek . tek dum . tek . with a roll closing every fourth bar.
                for at, kind in ((0,"dum"),(.5,"tek"),(1.5,"tek"),(2,"dum"),(3,"tek")):
                    if kind == "dum": tr.add(b0 + at, frame_drum(rng, 92), .4, -.1, .12)
                    else: tr.add(b0 + at, tek(rng), .26, .15, .15)
                if index % 4 == 3:
                    for at, g in ((3.25,.14),(3.5,.18),(3.75,.22)):
                        tr.add(b0 + at, tek(rng), g, .15, .15)
                for step in (1, 3, 5, 7):
                    tr.add(b0 + step * .5, shaker(rng, .08, .7), .1, -.35, .15)
            elif section == "break":
                tr.add(b0, frame_drum(rng, 92), .26, -.1, .3)
                tr.add(b0 + 2, frame_drum(rng, 120), .16, .1, .3)
            bar += 1
    breath = lambda f, s: ney(f, s, rng)
    def oud_line(tune, start, gain, pan):
        in_scale([name for name, _at, _dur in tune], hijaz)
        for name, at, dur in tune:
            # A pluck, and a quick tremolo on the long notes.
            count = max(1, int(dur / .25)) if dur >= 2 else 1
            for k in range(count):
                tr.add(start + at + k * .25, oud(hz(name)), gain if k == 0 else gain * .42, pan, .35)
    play_tune(tr, breath, [("D5",0,4),("Eb5",4,2),("D5",6,2),("A4",8,6)], 0, .26, .2, .7, hijaz, .98)
    oud_line(lead_a, marks["lead"][0] * 4, .44, -.2)
    play_tune(tr, breath, lead_b, marks["lead"][1] * 4, .3, .2, .55, hijaz)
    play_tune(tr, breath, [("A4",0,4),("Bb4",4,4),("A4",8,2),("G4",10,2),("F#4",12,4),
                           ("G4",16,4),("A4",20,4),("Bb4",24,2),("A4",26,2),("D5",28,4)], marks["break"][0] * 4, .3, .1, .7, hijaz, .98)
    oud_line(lead_b, marks["high"][0] * 4, .42, -.2)
    oud_line(lead_a[:14], marks["high"][1] * 4, .42, -.2)
    play_tune(tr, breath, [(n, a - 16, d) for n, a, d in lead_a[14:]], marks["lead"][2] * 4, .28, .2, .55, hijaz)
    return tr.render(.3)

def winter():
    tr = Track(70, 40)
    rng = tr.rng
    minor = ["A", "B", "C", "D", "E", "F", "G"]
    verse = [["A2","E3","A3","C4","E4"],["F2","C3","A3","C4","F4"],["C3","G3","C4","E4","G4"],["G2","D3","B3","D4","G4"]]
    bridge = [["F2","C3","A3","C4","F4"],["G2","D3","B3","D4","G4"],["E2","B2","G3","B3","E4"],["A2","E3","A3","C4","E4"],
              ["D3","A3","D4","F4","A4"],["G2","D3","B3","D4","G4"],["C3","G3","C4","E4","G4"],["G2","D3","B3","D4","G4"]]
    tune = [("E5",0,2),("D5",2,1),("C5",3,1),("A4",4,2),("C5",6,1),("D5",7,1),
            ("E5",8,1.5),("G5",9.5,.5),("E5",10,2),("D5",12,2),("B4",14,2),
            ("C5",16,1),("E5",17,1),("A5",18,2),("A5",20,1),("G5",21,1),("F5",22,2),
            ("E5",24,1),("G5",25,1),("E5",26,1),("C5",27,1),("D5",28,4)]
    answer = [("F5",0,1.5),("E5",1.5,.5),("C5",2,2),("D5",4,1.5),("E5",5.5,.5),("D5",6,2),
              ("E5",8,1),("G5",9,1),("B5",10,2),("A5",12,2),("E5",14,2),
              ("F5",16,1.5),("A5",17.5,.5),("F5",18,2),("G5",20,1),("D5",21,1),("B4",22,2),
              ("C5",24,1),("E5",25,1),("G5",26,2),("D5",28,2),("B4",30,2)]
    sections = [("intro",4),("verse",8),("bells",8),("bridge",8),("full",8),("intro",4)]
    bar = 0
    for section, count in sections:
        for index in range(count):
            b0 = bar * 4
            notes = (bridge[index % 8] if section == "bridge" else verse[index % 4])
            tr.add(b0, pad(chord(notes[1:]), 4 * tr.beat + 1.3, rng, .08), .42, 0, .7)
            tr.add(b0, bass(hz(notes[0]) * (2 if hz(notes[0]) < 60 else 1), 3.7 * tr.beat), .2, 0, .2)
            tr.add(b0, piano(hz(notes[2])), .3, -.2, .45)
            tr.add(b0 + 1, piano(hz(notes[3])), .2, -.15, .45)
            tr.add(b0 + 2, piano(hz(notes[4])), .22, -.1, .45)
            tr.add(b0 + 3, piano(hz(notes[3])), .17, -.15, .45)
            if section in ("bells", "full"):
                for step, which in enumerate([4, 3, 4, 2, 4, 3, 2, 3]):
                    tr.add(b0 + step * .5, celesta(hz(notes[which]) * 2), .15 if step % 2 == 0 else .1, .45, .6)
            if section in ("bridge", "full"):
                for step in range(8):
                    tr.add(b0 + step * .5, sleigh(rng, accent=1.0 if step % 4 == 0 else .55), .08, -.4, .3)
            bar += 1
    lead = lambda f, s: flute(f, s, rng, .004, .04)
    play_tune(tr, lead, tune, 4 * 12, .34, .1, .6, minor)
    play_tune(tr, celesta, tune[::2], 4 * 12, .1, .5, .7, minor)
    play_tune(tr, lead, answer, 4 * 20, .34, -.1, .6, minor)
    play_tune(tr, lead, tune, 4 * 28, .34, .1, .6, minor)
    return tr.render(.4, 2.8)

def report(name, data, seconds):
    rms = np.sqrt(np.mean(data ** 2))
    print(f"{name}.ogg  {seconds:.1f} s  rms {20 * math.log10(rms):.1f} dB  peak {np.max(np.abs(data)):.3f}")

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, composer in (("camp", camp), ("mountain", mountain), ("desert", desert), ("winter", winter)):
        data = composer()
        # In blocks: libsndfile's Vorbis encoder crashes on one long write.
        with soundfile.SoundFile(os.path.join(OUT, name + ".ogg"), "w", SR, 2, format="OGG", subtype="VORBIS") as out:
            for start in range(0, len(data), 8192):
                out.write(data[start:start + 8192].astype("float32"))
        report(name, data, len(data) / SR)
