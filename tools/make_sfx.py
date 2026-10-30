# Bakes the sound effects of Last Hook into game/assets/sfx (or the folder
# given as the first argument). Sounds the game plays often get several takes,
# so a repeat is never the same recording twice. Tonal sounds (catch, coin,
# pickup, win, revive) are written on C: SoundBank transposes them into the key
# of the music that is playing. Needs numpy only. Run: python tools/make_sfx.py
import os, struct, sys
import numpy as np

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "sfx")
C5, E5, G5, C6, E6, G6, C7 = 523.25, 659.26, 783.99, 1046.5, 1318.5, 1568.0, 2093.0

def timeline(seconds):
    n = int(seconds * SR)
    return n, np.arange(n) / SR

def noise(n, low, high, seed):
    rng = np.random.default_rng(seed)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spectrum[(freqs < low) | (freqs > high)] = 0
    out = np.fft.irfft(spectrum, n)
    return out / (np.max(np.abs(out)) + 1e-9)

def sweep(start, end, t, seconds, curve=1.0):
    # A sine gliding from one frequency to another.
    f = start + (end - start) * (t / seconds) ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR)

def ring(freq, t, partials):
    out = np.zeros(len(t))
    for ratio, amp, decay in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * decay)
    return out

def attack(t, seconds=.002):
    return np.minimum(1.0, t / seconds)

def place(total, sound, seconds, gain=1.0):
    start = int(seconds * SR)
    end = min(start + len(sound), len(total))
    total[start:end] += sound[:end - start] * gain

def launch(take):
    # The rope leaving the hand: an air rush that falls away.
    n, t = timeline(.2)
    seconds = .2
    centre = (1.0, 1.25, .85)[take]
    air = noise(n, 700 * centre, 4200 * centre, 100 + take) * .6
    zip_tone = sweep(1500 * centre, 420 * centre, t, seconds, .6) * .22
    return (air + zip_tone) * attack(t, .012) * (1 - t / seconds) ** 2.2

def catch(take):
    # A clean metal clink on C with a small thump of the rope going taut.
    n, t = timeline(.42)
    bright = (1.0, .8, 1.2)[take]
    clink = ring(C6, t, ((1.0, 1.0, 13.0), (2.0, .22 * bright, 22.0), (2.76, .3 * bright, 28.0), (5.4, .1 * bright, 60.0)))
    thump = np.sin(2 * np.pi * np.cumsum(170 + 90 * np.exp(-t * 40)) / SR) * np.exp(-t * 34) * .55
    tick = noise(n, 2000, 9000, 200 + take) * np.exp(-t * 170) * .3
    return (clink * .7 + thump + tick) * attack(t, .0015)

def release(take):
    # The line going slack: a short soft flutter.
    n, t = timeline(.13)
    air = noise(n, 500, 2600, 300 + take)
    return (air * .6 + sweep(300, 170, t, .13) * .3) * attack(t, .006) * (1 - t / .13) ** 2

def rope_return(take):
    n, t = timeline(.2)
    air = noise(n, 900, 3800, 320 + take) * .4
    return (air + sweep(380, 980 + 160 * take, t, .2) * .35) * np.sin(np.pi * t / .2) ** 1.5

def rock(take):
    # A hook glancing off stone: a rounded tock, not a burst of noise.
    n, t = timeline(.24)
    pitch = (1.0, .9, 1.09)[take]
    base = 190.0 * pitch * (1.0 + .55 * np.exp(-t * 38.0))
    phase = 2 * np.pi * np.cumsum(base) / SR
    body = np.sin(phase) * np.exp(-t * 21.0)
    stone = np.sin(phase * 2.37) * .32 * np.exp(-t * 42.0) + np.sin(phase * 3.91) * .14 * np.exp(-t * 70.0)
    tap = noise(n, 400, 3000, 400 + take) * .4 * np.exp(-t * 160.0)
    return (body * .85 + stone + tap) * attack(t, .002)

def spring(take):
    # A deep twang that shoots upwards as the bough lets go.
    n, t = timeline(.42)
    rate = (1.0, 1.1)[take]
    f = 150 * rate + 900 * rate * (t / .42) ** 1.6
    phase = 2 * np.pi * np.cumsum(f) / SR
    wobble = .78 + .22 * np.sin(2 * np.pi * 34 * t)
    return (np.sin(phase) * .8 + np.sin(2 * phase) * .22) * wobble * attack(t, .004) * (1 - t / .42) ** 1.5

def ice(take):
    # A dry scrape falling away as the hook drops off the plate.
    n, t = timeline(.36)
    grit = noise(n, 1800, 8000, 500 + take) * .5 * (.65 + .35 * np.sin(2 * np.pi * (70 + 15 * take) * t))
    whine = sweep(2500, 900, t, .36, .7) * .2
    return (grit + whine) * attack(t, .005) * (1 - t / .36) ** 1.7

def focus_in():
    # Time slows: a soft whoomp sinking down.
    n, t = timeline(.42)
    body = sweep(480, 110, t, .42, .5)
    sub = sweep(240, 60, t, .42, .5)
    air = noise(n, 200, 1500, 600) * .2
    return (body * .6 + sub * .4 + air) * np.sin(np.minimum(1, t / .04) * np.pi / 2) * (1 - t / .42) ** 1.5

def focus_out():
    n, t = timeline(.2)
    return (sweep(210, 640, t, .2, 1.3) * .7 + noise(n, 400, 2400, 610) * .2) * np.sin(np.minimum(1, t / .02) * np.pi / 2) * (1 - t / .2) ** 1.4

def coin():
    n, t = timeline(.32)
    return ring(C6, t, ((1.0, 1.0, 11.0), (3.0, .22, 26.0), (4.2, .1, 42.0))) * attack(t, .001)

def chime(n, t, freq, decay=7.0):
    return ring(freq, t, ((1.0, 1.0, decay), (2.0, .3, decay * 1.7), (3.01, .14, decay * 2.6), (4.16, .06, decay * 4))) * attack(t, .002)

def pickup():
    # Treasure: a bright two-note lift with a little shimmer.
    total = np.zeros(int(.6 * SR))
    for at, freq, gain in ((0, C6, .7), (.075, G6, 1.0)):
        n, t = timeline(.5)
        place(total, chime(n, t, freq), at, gain)
    n, t = timeline(.3)
    place(total, noise(n, 6000, 13000, 700) * np.exp(-t * 18) * .1, .07)
    return total

def item_arm():
    # A latch being set.
    total = np.zeros(int(.2 * SR))
    for at, seed in ((0, 710), (.055, 711)):
        n, t = timeline(.05)
        place(total, (noise(n, 1200, 6000, seed) * .6 + np.sin(2 * np.pi * 700 * t) * .4) * np.exp(-t * 95) * attack(t, .001), at)
    return total

def item_fire():
    # An item bursting into action: rising air and a bright ping.
    n, t = timeline(.38)
    rise = (noise(n, 900, 5000, 720) * .35 + sweep(320, 1500, t, .38, 1.4) * .3) * np.sin(np.pi * np.minimum(1, t / .38)) ** 1.2
    total = rise.copy()
    m, u = timeline(.3)
    place(total, chime(m, u, G6, 11.0), .1, .35)
    return total

def land(take):
    # Boots on rock: a padded thud with a pinch of grit.
    n, t = timeline(.2)
    pitch = (1.0, .9, 1.12)[take]
    body = np.sin(2 * np.pi * np.cumsum(95 * pitch + 80 * np.exp(-t * 34)) / SR) * np.exp(-t * 24)
    grit = noise(n, 1000, 5000, 800 + take) * .28 * np.exp(-t * 55)
    return (body + grit) * attack(t, .0015)

def step(take):
    n, t = timeline(.075)
    pitch = (1.0, .88, 1.14, .95)[take]
    body = np.sin(2 * np.pi * 150 * pitch * t) * np.exp(-t * 62) * .7
    grit = noise(n, 1300 * pitch, 6500, 820 + take) * .4 * np.exp(-t * 90)
    return (body + grit) * attack(t, .001)

def knock():
    # A hazard hitting the hero: a heavy blow with air behind it.
    n, t = timeline(.32)
    body = np.sin(2 * np.pi * np.cumsum(70 + 110 * np.exp(-t * 26)) / SR) * np.exp(-t * 15)
    air = noise(n, 300, 3200, 900) * .4 * np.exp(-t * 16)
    return (body + air) * attack(t, .002)

def fail():
    # Losing the climb: a sad falling third over a soft thud. Soft on purpose,
    # the player hears it often.
    total = np.zeros(int(.9 * SR))
    for at, freq, gain in ((0, 392.0, .8), (.16, 329.6, .9), (.32, 261.6, 1.0)):
        n, t = timeline(.56)
        tone = ring(freq, t, ((1.0, 1.0, 5.5), (2.0, .2, 9.0), (3.0, .07, 14.0)))
        place(total, tone * np.minimum(1, t / .01), at, gain * .6)
    n, t = timeline(.3)
    place(total, np.sin(2 * np.pi * np.cumsum(55 + 60 * np.exp(-t * 22)) / SR) * np.exp(-t * 13) * .6, 0)
    return total

def win():
    # Reaching the summit: a rising arpeggio that opens into a held chord.
    total = np.zeros(int(1.9 * SR))
    for at, freq, gain in ((0, C5, .7), (.11, E5, .75), (.22, G5, .8), (.33, C6, 1.0), (.33, E6, .55), (.33, G6, .4)):
        n, t = timeline(1.5)
        place(total, chime(n, t, freq, 3.4), at, gain)
    n, t = timeline(1.2)
    place(total, noise(n, 7000, 14000, 950) * np.exp(-t * 5) * .06 * attack(t, .08), .33)
    return total

def revive():
    # A second chance: a soft upward shimmer.
    total = np.zeros(int(.9 * SR))
    for at, freq, gain in ((0, G5, .6), (.08, C6, .7), (.16, E6, .8), (.24, G6, .8), (.32, C7, .6)):
        n, t = timeline(.55)
        place(total, chime(n, t, freq, 6.0), at, gain)
    return total

def tap(take):
    # A menu button: small and wooden, it must not tire.
    n, t = timeline(.05)
    freq = (880.0, 740.0)[take]
    return (np.sin(2 * np.pi * freq * t) * np.exp(-t * 120) + np.sin(2 * np.pi * freq * 2.3 * t) * .3 * np.exp(-t * 190)) * attack(t, .0008)

def wind():
    # Seamless: filtered in the frequency domain and modulated by whole cycles.
    n, t = timeline(8.0)
    low = noise(n, 90, 620, 960)
    mid = noise(n, 500, 1700, 961)
    swell = .75 + .25 * np.sin(2 * np.pi * t / 8.0)
    gust = .6 + .4 * np.sin(2 * np.pi * 3 * t / 8.0 + 1.1)
    return low * swell * .8 + mid * gust * .3

def write_wav(path, data, loop=False):
    pcm = (np.clip(data / (np.max(np.abs(data)) + 1e-9), -1, 1) * 23000).astype("<i2").tobytes()
    chunks = b""
    if loop:
        # 'smpl' chunk: one forward loop over the whole file.
        frames = len(data)
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        chunks = b"smpl" + struct.pack("<I", len(smpl)) + smpl
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + chunks + b"data" + struct.pack("<I", len(pcm)) + pcm
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)

def fade_end(data, seconds=.006):
    # A sound never ends on a non-zero sample: that would be a click.
    n = min(int(seconds * SR), len(data))
    data = data.copy()
    data[-n:] *= np.linspace(1, 0, n)
    return data

TAKES = {"launch":(launch,3),"catch":(catch,3),"release":(release,2),"return":(rope_return,2),"rock":(rock,3),
         "spring":(spring,2),"ice":(ice,2),"land":(land,3),"step":(step,4),"tap":(tap,2)}
SINGLE = {"focus_in":focus_in,"focus_out":focus_out,"coin":coin,"pickup":pickup,"item_arm":item_arm,"item_fire":item_fire,
          "knock":knock,"fail":fail,"win":win,"revive":revive}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, (make, count) in TAKES.items():
        for take in range(count):
            write_wav(os.path.join(OUT, f"{name}_{take + 1}.wav"), fade_end(make(take)))
    for name, make in SINGLE.items():
        write_wav(os.path.join(OUT, f"{name}_1.wav"), fade_end(make()))
    write_wav(os.path.join(OUT, "wind_1.wav"), wind(), True)
    print("sfx written:", len(os.listdir(OUT)))
