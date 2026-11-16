import sys, wave
import numpy as np
from faster_whisper import WhisperModel

wav = sys.argv[1]
size = sys.argv[2] if len(sys.argv) > 2 else "small"

with wave.open(wav, "rb") as w:
    sr = w.getframerate()
    ch = w.getnchannels()
    data = w.readframes(w.getnframes())

audio = np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
if ch > 1:
    audio = audio.reshape(-1, ch).mean(axis=1)

model = WhisperModel(size, device="cpu", compute_type="int8")
segments, info = model.transcribe(audio, language="zh", vad_filter=True,
                                  initial_prompt="以下是普通话内容。")
for s in segments:
    t = s.text.strip()
    if len(t) < 2:
        continue
    print(f"[{int(s.start//60):02d}:{int(s.start%60):02d}] {t}")
