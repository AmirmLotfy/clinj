#!/usr/bin/env python3
# Renders README visuals from the SVG sources: results.png, scanning.png, demo.gif
import subprocess, pathlib
d = pathlib.Path(__file__).parent
scan = (d / "scanning.svg").read_text()
res = (d / "results.svg").read_text()

def repl(s, pairs):
    for a, b in pairs:
        assert a in s, f"missing: {a[:40]}"
        s = s.replace(a, b)
    return s

# high-res static screenshots
for name in ("results", "scanning"):
    subprocess.run(["magick", "-background", "none", "-density", "200",
                    str(d / f"{name}.svg"), str(d / f"{name}.png")], check=True)

# GIF frames
frames = []
frames.append(repl(scan, [
    ('stroke-dasharray="83 294"', 'stroke-dasharray="34 343"'),
    ("47 items · 1.8 GB found", "9 items · 280 MB found"),
    ("Google/Chrome — Service Worker/CacheStorage", "npm cache"),
]))
frames.append(repl(scan, [
    ('stroke-dasharray="83 294"', 'stroke-dasharray="172 205"'),
    ("47 items · 1.8 GB found", "38 items · 1.6 GB found"),
    ("Google/Chrome — Service Worker/CacheStorage", "Cursor — Code Cache"),
]))
frames.append(res)  # results list
done = repl(res, [
    ('  <text x="64" y="641" fill="#9a9aa0" font-size="14">Selected:</text>',
     '  <text x="64" y="641" fill="#4ade80" font-size="16" font-weight="700">✓</text>'),
    ('  <text x="134" y="641" fill="#ffffff" font-size="14" font-weight="600">2.1 GB</text>',
     '  <text x="88" y="641" fill="#ededf0" font-size="14" font-weight="600">Cleaned 2.1 GB</text>'),
    ('  <text x="188" y="641" fill="#9a9aa0" font-size="14">of 3.1 GB</text>',
     '  <text x="218" y="641" fill="#9a9aa0" font-size="14">· 8.7 GB free now</text>'),
    ('fill="#3b6ef6"/><text x="1019" y="641" fill="#fff" font-size="13" font-weight="600" text-anchor="middle">Clean</text>',
     'fill="#1c3a26"/><text x="1019" y="641" fill="#4ade80" font-size="13" font-weight="600" text-anchor="middle">Done</text>'),
])
frames.append(done)

pngs = []
for i, svg in enumerate(frames):
    sp = d / f"_f{i}.svg"; sp.write_text(svg)
    pp = d / f"_f{i}.png"
    subprocess.run(["magick", "-background", "#111113", "-density", "120", str(sp),
                    "-resize", "920x", "-flatten", str(pp)], check=True)
    pngs.append(str(pp))

subprocess.run(["magick", "-loop", "0", "-dispose", "None",
                "-delay", "95", pngs[0], "-delay", "95", pngs[1],
                "-delay", "190", pngs[2], "-delay", "280", pngs[3],
                "-colors", "200", str(d / "demo.gif")], check=True)
for f in d.glob("_f*"):
    f.unlink()
print("wrote results.png, scanning.png, demo.gif")
