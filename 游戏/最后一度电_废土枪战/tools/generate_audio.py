"""Deterministic, locally synthesized PCM effects for 最后一度电.

22050 Hz mono 16-bit WAV. No recordings, network media or external rights assets.
The bank applies per-effect gains and spatial attenuation after these peak limits.
"""
from pathlib import Path
import argparse
import hashlib
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
RATE = 22050
RNG = np.random.default_rng(9172026)
NAMES = ["rifle", "shotgun", "enemy_shot", "reload", "empty", "hit", "headshot",
         "footstep", "interact", "power", "alarm", "pickup", "heal", "death",
         "victory", "metal", "wind"]


def timeline(duration):
    return np.arange(int(RATE * duration), dtype=np.float64) / RATE


def noise(length):
    return RNG.standard_normal(length)


def lowpass(data, cutoff):
    """FFT filter for offline synthesis, never a runtime dependency."""
    spectrum = np.fft.rfft(data)
    frequencies = np.fft.rfftfreq(len(data), 1 / RATE)
    spectrum *= 1.0 / (1.0 + (frequencies / cutoff) ** 4)
    return np.fft.irfft(spectrum, n=len(data))


def click(duration=.07, pitch=1600, body=.5):
    t = timeline(duration)
    return (np.sin(2*np.pi*pitch*t)*np.exp(-t*80)
            + body*noise(len(t))*np.exp(-t*120))


def mix_at(destination, sound, second, gain=1.0):
    start = int(second * RATE)
    length = min(len(sound), len(destination) - start)
    if length > 0:
        destination[start:start+length] += sound[:length] * gain


def gun(heavy=False, distant=False):
    t = timeline(.94 if heavy else .57)
    raw = noise(len(t))
    body = lowpass(raw, 2800 if heavy else 4100)
    crack = (raw - lowpass(raw, 2300)) * np.exp(-t*150)
    transient = body * np.exp(-t*(42 if heavy else 65)) * 1.8
    phase = 2*np.pi*(48*t + (140 if heavy else 180)*(.040*(1-np.exp(-t/.04))))
    boom = np.sin(phase) * np.exp(-t*(8.2 if heavy else 14.0)) * (1.0 if heavy else .68)
    tail = lowpass(noise(len(t)), 900) * np.exp(-t*(6 if heavy else 11)) * .65
    signal = crack*.85 + transient + boom + tail
    for delay, gain in [(.037,.17),(.081,.09),(.146,.05)]:
        offset = int(delay*RATE)
        signal[offset:] += (crack+transient)[:-offset] * gain
    if heavy:
        mix_at(signal, click(.04, 320, .8), .009, .45)
    if distant:
        signal = lowpass(signal, 3400)
    return signal


def make_effects():
    effects = {"rifle": gun(), "shotgun": gun(True), "enemy_shot": gun(distant=True)}
    t = timeline(1.18)
    reload = np.zeros(len(t))
    for when, hz, gain in [(0,1100,.6),(.13,620,.8),(.46,940,.45),(.71,430,1),(.92,1580,.55)]:
        mix_at(reload,click(.105,hz,.7),when,gain)
    scrape = lowpass(noise(int(RATE*.18)),2300)*np.hanning(int(RATE*.18))*.16
    mix_at(reload,scrape,.28)
    effects["reload"] = reload
    effects["empty"] = click(.10, 1200, .4)
    t = timeline(.16)
    effects["hit"] = lowpass(noise(len(t)),1500)*np.exp(-t*38) + .55*np.sin(2*np.pi*185*t)*np.exp(-t*24)
    t = timeline(.32)
    effects["metal"] = sum(np.sin(2*np.pi*f*t)*np.exp(-t*d)*a for f,d,a in [(1860,16,.4),(2927,24,.3),(4370,37,.15)]) + noise(len(t))*.07*np.exp(-t*90)
    effects["headshot"] = np.pad(effects["hit"],(0,len(t)-len(effects["hit"]))) + effects["metal"]*.65
    t = timeline(.24)
    sole = lowpass(noise(len(t)),750)*np.exp(-t*25)
    gravel = (noise(len(t))-lowpass(noise(len(t)),1500))*np.exp(-t*35)*.12
    effects["footstep"] = sole + gravel + np.sin(2*np.pi*90*t)*np.exp(-t*30)*.30
    t = timeline(.24)
    effects["interact"] = np.sin(2*np.pi*620*t)*np.exp(-t*17)*.6 + np.sin(2*np.pi*930*t)*np.exp(-t*22)*.25
    t = timeline(1.55)
    surge = (np.sin(2*np.pi*60*t)+.2*np.sin(2*np.pi*120*t))*(1-np.exp(-t*8))*np.exp(-t*2.5)*.55
    chime = np.sin(2*np.pi*(360*t+180*t*t))*np.exp(-t*3.4)*.35
    effects["power"] = surge + chime
    mix_at(effects["power"],click(.07,320,.6),0,.8)
    t = timeline(1.7)
    gate = np.maximum(0,np.sin(2*np.pi*2.5*t))**2
    effects["alarm"] = (np.sin(2*np.pi*690*t)+.25*np.sin(2*np.pi*1035*t))*gate*np.minimum(t/.05,1)*np.minimum((1.7-t)/.12,1)
    t = timeline(.48)
    effects["pickup"] = np.zeros(len(t))
    for when,f in [(0,540),(.13,810)]:
        note_t=timeline(.30)
        mix_at(effects["pickup"],np.sin(2*np.pi*f*note_t)*np.exp(-note_t*12),when,.55)
    t = timeline(1.0)
    effects["heal"] = lowpass(noise(len(t)),3800)*np.sin(np.pi*t)**2*.17
    mix_at(effects["heal"],click(.09,680,.1),.06,.18)
    mix_at(effects["heal"],effects["pickup"],.40,.32)
    t = timeline(1.65)
    effects["death"] = (np.sin(2*np.pi*(110*t-27*t*t))*np.exp(-t*2.7)
                        + lowpass(noise(len(t)),550)*np.exp(-t*3.8)*.5)
    t = timeline(3.0)
    effects["victory"] = np.zeros(len(t))
    for when,f in [(0,196),(.32,246.94),(.64,293.66),(1.04,392)]:
        nt=timeline(1.75)
        note=(np.sin(2*np.pi*f*nt)+.22*np.sin(2*np.pi*f*2*nt))*np.minimum(nt/.022,1)*np.exp(-nt*2.5)
        mix_at(effects["victory"],note,when,.6)
    # Periodic Fourier synthesis gives a genuinely seamless, nonrepeating-in-short-time wind loop.
    t = timeline(12.0)
    freq = np.fft.rfftfreq(len(t),1/RATE)
    spectrum = (RNG.standard_normal(len(freq))+1j*RNG.standard_normal(len(freq)))
    spectrum *= np.where(freq>18,1/np.maximum(freq,18)**.8,0)
    spectrum /= (1+(freq/1700)**3)
    spectrum[0] = 0
    wind=np.fft.irfft(spectrum,n=len(t))
    wind*=.65+.20*np.sin(2*np.pi*t/12)+.12*np.sin(2*np.pi*t/4)
    effects["wind"] = wind
    return effects


def write_wav(name, signal):
    signal = np.asarray(signal,dtype=np.float64)
    signal -= np.mean(signal)
    # Soft compression controls initial gun transients without hard clipping.
    signal = np.tanh(signal*.90)
    peak = np.max(np.abs(signal))
    signal *= (.80 if name == "wind" else .89) / max(peak,1e-10)
    if name != "wind":
        attack=min(int(.0015*RATE),len(signal)//4)
        release=min(int(.018*RATE),len(signal)//4)
        signal[:attack]*=np.linspace(0,1,attack)
        signal[-release:]*=np.linspace(1,0,release)
    pcm=(signal*32767).astype("<i2")
    path=OUT/(name+".wav")
    with wave.open(str(path),"wb") as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm.tobytes())
    return {"file":path.name,"seconds":round(len(pcm)/RATE,4),
            "peak_dbfs":round(20*np.log10(np.max(np.abs(signal))+1e-12),3),
            "rms_dbfs":round(20*np.log10(np.sqrt(np.mean(signal**2))+1e-12),3),
            "sha256":hashlib.sha256(path.read_bytes()).hexdigest()}


def verify():
    errors=[]
    for name in NAMES:
        path=OUT/(name+".wav")
        if not path.exists():errors.append(f"Missing {name}");continue
        with wave.open(str(path),"rb") as f:
            if (f.getnchannels(),f.getsampwidth(),f.getframerate()) != (1,2,RATE):errors.append(f"Invalid PCM format {name}")
            samples=np.frombuffer(f.readframes(f.getnframes()),dtype="<i2").astype(float)/32768
        if len(samples)<RATE*.06:errors.append(f"Too short {name}")
        if max(abs(samples))>.90:errors.append(f"Clipping/headroom violation {name}")
        if np.sqrt(np.mean(samples*samples))<.002:errors.append(f"Silent {name}")
        if abs(np.mean(samples))>.01:errors.append(f"DC offset {name}")
    if errors:raise SystemExit("\n".join(errors))
    print(f"AUDIO_VERIFY PASS: {len(NAMES)} WAV files, mono PCM16/{RATE}, headroom >=0.9 dB")


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--verify",action="store_true")
    args=parser.parse_args()
    if not args.verify:
        OUT.mkdir(parents=True,exist_ok=True)
        manifest=[write_wav(name,sound) for name,sound in make_effects().items()]
        (OUT/"manifest.json").write_text(json.dumps({"source":"Local procedural synthesis, no recordings", "sample_rate":RATE,"effects":manifest},ensure_ascii=False,indent=2),encoding="utf-8")
        print(f"Generated {len(manifest)} local effects in {OUT}")
    verify()
