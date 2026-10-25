# Composes the four music loops of Last Hook and writes them as looping WAV
# files into game/assets/music (or the folder given as the first argument).
#   camp.wav     menu: warm F major, harp arpeggios, pad and a bell tune
#   mountain.wav standard mountain: bright D major folk with flute and shaker
#   desert.wav   canyon: D hijaz, marimba ostinato, oud-like lead, frame drum
#   winter.wav   snowy summit: A dorian, celesta, piano-like pluck, deep pad
# Every voice is additive synthesis in numpy; a synthetic hall reverb glues
# them. The tail of each loop is folded back onto its start, so the files
# loop without a click. Needs numpy only. Run: python tools/make_music.py
import math, os, struct, sys
import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "music")
NOTE = {"C":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"E":4,"F":5,"F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11}

def hz(name):
    # "A4" -> 440 Hz, "F#3", "Bb2"...
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[pitch] + 12 * (octave + 1) - 69) / 12)

class Track:
    def __init__(self, bpm, bars, beats=4):
        self.beat = 60.0 / bpm
        self.length = int(bars * beats * self.beat * SR)
        self.tail = int(4.0 * SR)
        self.dry = np.zeros(self.length + self.tail)
        self.send = np.zeros(self.length + self.tail)
        self.rng = np.random.default_rng(7)

    def at(self, beat):
        return int(beat * self.beat * SR)

    def add(self, start_beat, signal, gain, reverb=.3):
        start = self.at(start_beat)
        end = min(start + len(signal), len(self.dry))
        self.dry[start:end] += signal[:end - start] * gain
        self.send[start:end] += signal[:end - start] * gain * reverb

    def render(self, wet=.32):
        hall = reverb(self.send)
        mix = self.dry + hall * wet
        # Fold the ringing tail onto the start: a seamless loop.
        loop = mix[:self.length].copy()
        loop[:self.tail] += mix[self.length:self.length + self.tail]
        loop = np.tanh(loop / (np.max(np.abs(loop)) + 1e-9) * 1.25) / math.tanh(1.25)
        return loop * .89

def env(n, attack, release, total):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    rel_start = max(total - release, attack)
    e *= np.clip(1.0 - (t - rel_start) / max(release, 1e-4), 0.0, 1.0)
    return e

def harp(freq, seconds=2.6, bright=1.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 9):
        partial = freq * k * (1 + .0004 * k * k)
        if partial > SR * .45: break
        out += np.sin(2 * np.pi * partial * t) * (1.0 / k ** (1.6 - .4 * bright)) * np.exp(-t * (1.6 + 1.3 * k))
    pluck = np.minimum(1.0, t / .004)
    return out * pluck * .5

def oud(freq, seconds=1.4):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 10):
        out += np.sin(2 * np.pi * freq * k * t + k * .3) * (1.0 / k ** 1.15) * np.exp(-t * (3.0 + 2.2 * k))
    return out * np.minimum(1.0, t / .003) * .45

def marimba(freq, seconds=1.2):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * freq * t) * np.exp(-t * 5.0)
    out += .35 * np.sin(2 * np.pi * freq * 3.93 * t) * np.exp(-t * 14.0)
    out += .12 * np.sin(2 * np.pi * freq * 9.2 * t) * np.exp(-t * 30.0)
    return out * np.minimum(1.0, t / .002) * .55

def bell(freq, seconds=3.2):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, decay in ((1.0, 1.0, 1.1), (2.0, .45, 1.8), (3.01, .22, 2.6), (4.16, .14, 3.4), (5.43, .07, 5.0)):
        if freq * ratio < SR * .45:
            out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * decay)
    return out * np.minimum(1.0, t / .003) * .35

def piano(freq, seconds=2.8):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 7):
        out += np.sin(2 * np.pi * freq * k * (1 + .0007 * k * k) * t) * (1 / k ** 1.4) * np.exp(-t * (1.1 + .9 * k))
    return out * np.minimum(1.0, t / .005) * .45

def flute(freq, seconds, rng):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    vib = 1 + .006 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - .18) / .3, 0, 1)
    phase = 2 * np.pi * freq * np.cumsum(vib) / SR
    out = np.sin(phase) + .22 * np.sin(2 * phase) + .06 * np.sin(3 * phase)
    breath = lowpass(lowpass(rng.standard_normal(n), .06), .06) * .05
    return (out + breath) * env(n, .07, .18, seconds) * .32

def pad(freqs, seconds, rng):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for detune in (-.0035, 0.0, .0041):
            phase = rng.uniform(0, 2 * np.pi)
            wobble = 1 + .0015 * np.sin(2 * np.pi * .23 * t + phase)
            ph = 2 * np.pi * f * (1 + detune) * np.cumsum(wobble) / SR + phase
            out += np.sin(ph) + .18 * np.sin(2 * ph) + .05 * np.sin(3 * ph)
    return out / (3 * len(freqs)) * env(n, min(1.2, seconds * .35), min(1.4, seconds * .4), seconds)

def bass(freq, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * freq * t) + .25 * np.sin(4 * np.pi * freq * t)
    return out * env(n, .015, .12, seconds) * np.exp(-t * .9) * .6

def kick(seconds=.35):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = 52 + 70 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11) * .9

def frame_drum(rng, seconds=.5, tone=110):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(tone + 40 * np.exp(-t * 25)) / SR) * np.exp(-t * 9)
    skin = lowpass(rng.standard_normal(n), .25) * np.exp(-t * 40) * .5
    return (body + skin) * .6

def shaker(rng, seconds=.12, accent=1.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    high = noise - lowpass(noise, .35)
    return high * np.exp(-t * 45) * np.minimum(1, t / .006) * .22 * accent

def lowpass(x, alpha):
    # One-pole low-pass (alpha 0..1), vectorised through an IIR via cumsum-free loop.
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += (x[i] - acc) * alpha
        y[i] = acc
    return y

def reverb(x, seconds=2.4):
    rng = np.random.default_rng(3)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
    # Darker tail: smooth the impulse a little, keep a soft pre-delay.
    ir = np.convolve(ir, np.ones(6) / 6, mode="same")
    ir[:int(.018 * SR)] = 0
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(math.ceil(math.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    return y

def chord(names):
    return [hz(n) for n in names]

# --- Compositions ------------------------------------------------------------------

def camp():
    tr = Track(76, 24)
    rng = tr.rng
    prog = [["F3","A3","C4","E4"],["A2","C4","E4","G4"],["Bb2","D4","F4","A4"],["C3","E4","G4","Bb4"],
            ["D3","F4","A4","C5"],["Bb2","D4","F4","A4"],["G2","Bb3","D4","F4"],["C3","E4","G4","C5"]]
    roots = ["F2","A2","Bb2","C3","D2","Bb2","G2","C3"]
    for bar in range(24):
        idx = bar % 8
        notes = prog[idx]
        b0 = bar * 4
        tr.add(b0, pad(chord(notes[1:]), 4 * tr.beat + 1.2, rng), .55, .6)
        if bar < 20:
            tr.add(b0, bass(hz(roots[idx]), 3.6 * tr.beat), .5, .1)
        # Harp: rolling eighths up and down the chord.
        pattern = [0, 1, 2, 3, 2, 1, 2, 3] if bar % 2 == 0 else [0, 2, 1, 3, 2, 3, 1, 2]
        if 2 <= bar < 22:
            for step, which in enumerate(pattern):
                f = hz(notes[which]) * (2 if which == 0 else 1)
                tr.add(b0 + step * .5 + rng.uniform(0, .015), harp(f, 2.4), .34 * (1.0 if step % 2 == 0 else .8), .45)
    # Bell tune (F major pentatonic), enters in the second half.
    tune = [("C5",0,1.5),("D5",1.5,.5),("F5",2,2),("A5",4,1.5),("G5",5.5,.5),("F5",6,2),
            ("D5",8,1.5),("F5",9.5,.5),("G5",10,2),("C5",12,3),("A4",15,1),
            ("C5",16,1.5),("D5",17.5,.5),("F5",18,2),("A5",20,1),("C6",21,1),("A5",22,2),
            ("G5",24,1.5),("F5",25.5,.5),("D5",26,2),("F5",28,4)]
    for start in (32, 64):
        for name, at, _dur in tune:
            if start + at < 92:
                tr.add(start + at, bell(hz(name)), .5, .7)
    return tr.render(.36)

def mountain():
    tr = Track(92, 32)
    rng = tr.rng
    prog = [["D3","F#3","A3","D4"],["G2","B3","D4","G4"],["B2","D4","F#4","B4"],["A2","C#4","E4","A4"]]
    roots = ["D2","G2","B1","A1"]
    for bar in range(32):
        idx = bar % 4
        notes = prog[idx]
        b0 = bar * 4
        tr.add(b0, pad(chord(notes[1:]), 4 * tr.beat + .8, rng), .32, .5)
        tr.add(b0, bass(hz(roots[idx]), 1.8 * tr.beat), .55, .05)
        tr.add(b0 + 2.5, bass(hz(roots[idx]) * 1.5, .9 * tr.beat), .35, .05)
        tr.add(b0 + 3, bass(hz(roots[idx]), .9 * tr.beat), .4, .05)
        # Guitar-like picking: root, fifth, octave, third...
        picks = [0, 2, 3, 1, 2, 3, 1, 3]
        for step, which in enumerate(picks):
            tr.add(b0 + step * .5, harp(hz(notes[which]), 1.6, 1.4), .28 if step % 2 == 0 else .2, .3)
        if bar >= 4:
            for step in range(8):
                tr.add(b0 + step * .5, shaker(rng, accent=1.0 if step % 2 else .6), .38, .15)
            tr.add(b0, kick(), .35, .05)
            tr.add(b0 + 2, kick(), .28, .05)
    # Flute melody over bars 8-15 and 20-27 (D major).
    phrase = [("F#5",0,1),("A5",1,1),("B5",2,1.5),("A5",3.5,.5),("F#5",4,2),("E5",6,1),("D5",7,1),
              ("E5",8,1),("F#5",9,1),("A5",10,1.5),("G5",11.5,.5),("F#5",12,1.5),("E5",13.5,.5),("D5",14,2),
              ("B4",16,1),("D5",17,1),("E5",18,1.5),("F#5",19.5,.5),("A5",20,2),("B5",22,1),("A5",23,1),
              ("F#5",24,1),("E5",25,.5),("D5",25.5,.5),("E5",26,2),("D5",28,4)]
    for start in (32, 80):
        for name, at, dur in phrase:
            tr.add(start + at, flute(hz(name), dur * tr.beat * .95, rng), .55, .5)
    return tr.render(.28)

def desert():
    tr = Track(84, 28)
    rng = tr.rng
    # D hijaz: D Eb F# G A Bb C.
    ost = ["D4","A3","Eb4","D4","F#4","D4","Eb4","A3"]
    for bar in range(28):
        b0 = bar * 4
        if bar % 4 == 0:
            tr.add(b0, pad([hz("D3"), hz("A3"), hz("D4")], 16 * tr.beat + 1.0, rng), .42, .5)
        tr.add(b0, bass(hz("D2"), 3.5 * tr.beat), .45, .05)
        if bar >= 2:
            for step, name in enumerate(ost):
                if bar % 8 >= 6 and step in (2, 6): name = "C4"
                tr.add(b0 + step * .5, marimba(hz(name)), .3 if step % 2 == 0 else .22, .35)
        if bar >= 4:
            for at, tone, g in ((0, 95, .55), (1.5, 140, .3), (2, 95, .45), (3, 140, .3), (3.5, 160, .22)):
                tr.add(b0 + at, frame_drum(rng, tone=tone), g, .2)
            for step in range(8):
                if step % 2: tr.add(b0 + step * .5, shaker(rng, .09, .7), .3, .2)
    lead = [("A4",0,1),("Bb4",1,.5),("A4",1.5,.5),("G4",2,1),("F#4",3,1),("G4",4,1.5),("A4",5.5,.5),("Bb4",6,2),
            ("C5",8,1),("Bb4",9,.5),("A4",9.5,.5),("G4",10,1),("A4",11,1),("F#4",12,1),("Eb4",13,1),("D4",14,2),
            ("D5",16,1.5),("C5",17.5,.5),("Bb4",18,1),("A4",19,1),("Bb4",20,.5),("A4",20.5,.5),("G4",21,1),("A4",22,2),
            ("F#4",24,1),("G4",25,1),("Eb4",26,1),("D4",27,5)]
    for start in (24, 72):
        for name, at, dur in lead:
            # Oud-like: a pluck, a quick tremolo on the long notes.
            notes = max(1, int(dur / .25)) if dur >= 2 else 1
            for k in range(notes):
                tr.add(start + at + k * .25, oud(hz(name), 1.2), .5 if k == 0 else .22, .4)
    return tr.render(.34)

def winter():
    tr = Track(70, 20)
    rng = tr.rng
    prog = [["A2","E3","A3","C4","E4"],["F2","C3","A3","C4","F4"],["C3","G3","C4","E4","G4"],["G2","D3","B3","D4","G4"]]
    for bar in range(20):
        idx = bar % 4
        notes = prog[idx]
        b0 = bar * 4
        tr.add(b0, pad(chord(notes[1:]), 4 * tr.beat + 1.6, rng), .6, .7)
        tr.add(b0, bass(hz(notes[0]), 3.8 * tr.beat), .35, .2)
        # Piano: open voicing on 1, a soft answer on 3.
        tr.add(b0, piano(hz(notes[2])), .3, .5)
        tr.add(b0 + .02, piano(hz(notes[3])), .25, .5)
        tr.add(b0 + 2, piano(hz(notes[4])), .22, .5)
        if bar >= 2:
            for step, which in enumerate([4, 3, 4, 2, 4, 3, 2, 3]):
                tr.add(b0 + step * .5, bell(hz(notes[which]) * 2, 2.0), .14, .8)
    tune = [("E5",0,2),("D5",2,1),("C5",3,1),("B4",4,2),("C5",6,1),("D5",7,1),
            ("E5",8,1.5),("G5",9.5,.5),("A5",10,2),("G5",12,2),("E5",14,2),
            ("F5",16,1.5),("E5",17.5,.5),("D5",18,2),("C5",20,1),("B4",21,1),("A4",22,2),
            ("B4",24,1),("C5",25,1),("D5",26,2),("E5",28,4)]
    for name, at, dur in tune:
        tr.add(32 + at, flute(hz(name), dur * tr.beat * .95, rng), .42, .65)
    return tr.render(.45)

def write_wav(path, data):
    pcm = (np.clip(data, -1, 1) * 32000).astype("<i2").tobytes()
    frames = len(data)
    # 'smpl' chunk: one forward loop over the whole file (Godot's
    # "Detect From WAV" loop mode reads it).
    smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
    smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"smpl" + struct.pack("<I", len(smpl)) + smpl + b"data" + struct.pack("<I", len(pcm)) + pcm
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, composer in (("camp", camp), ("mountain", mountain), ("desert", desert), ("winter", winter)):
        data = composer()
        write_wav(os.path.join(OUT, name + ".wav"), data)
        print(f"{name}.wav  {len(data)/SR:.1f} s")
