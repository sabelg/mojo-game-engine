"""Verify Atlas's optional FFmpeg CLI package; synthetic CPU tests are explicit."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "9.0.2"
BUILD = "gpl_h2f3dd36_103"
PACKAGE_SHA256 = "9d0c599cc0834d04f20ffdffef3d7802cbf77c53807f4a9c1d49ff52fcc3d7f2"
PREFIX = ROOT / ".deps/ffmpeg-9.0.2/.pixi/envs/default"


def run(tool, args, binary=False):
    # A caller's linker override must not inject another libav ABI into this tool.
    env = dict(os.environ)
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)
    return subprocess.run([str(tool), *map(str, args)], env=env,
                          check=True, capture_output=True, text=not binary, timeout=60).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect-only", action="store_true", help="No encode/decode tests")
    args = parser.parse_args()
    ffmpeg, ffprobe = PREFIX / "bin/ffmpeg", PREFIX / "bin/ffprobe"
    if not ffmpeg.is_file() or not ffprobe.is_file():
        raise SystemExit("Atlas FFmpeg is absent; run bash scripts/setup-ffmpeg.sh.")
    meta_files = list((PREFIX / "conda-meta").glob("ffmpeg-*.json"))
    if len(meta_files) != 1:
        raise SystemExit("Expected exactly one FFmpeg package receipt.")
    meta = json.loads(meta_files[0].read_text())
    if (meta.get("version"), meta.get("build"), meta.get("sha256")) != (VERSION, BUILD, PACKAGE_SHA256):
        raise SystemExit("FFmpeg registry package receipt differs from the verified ARM64 GPL pin.")
    if not str(meta.get("url", "")).startswith("https://conda.anaconda.org/conda-forge/linux-aarch64/"):
        raise SystemExit("Unexpected FFmpeg package origin.")
    versions = {}
    for tool in [ffmpeg, ffprobe]:
        text = run(tool, ["-version"])
        if not text.startswith(f"{tool.name} version {VERSION} "):
            raise SystemExit(f"Unexpected {tool.name} version.")
        versions[tool.name] = text
    encoders = run(ffmpeg, ["-hide_banner", "-encoders"])
    required = ["ffv1", "pcm_f32le", "libx264", "libx265", "libvpx-vp9", "aac", "libopus"]
    for codec in required:
        if not re.search(r"^\s*\S+\s+" + re.escape(codec) + r"\s", encoders, re.M):
            raise SystemExit(f"Required encoder absent: {codec}")
    report = {"verified_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "executables": {"ffmpeg": str(ffmpeg), "ffprobe": str(ffprobe)},
              "versions": versions, "package": {k: meta.get(k) for k in ["version", "build", "url", "sha256", "depends"]},
              "executable_sha256": {t.name: hashlib.sha256(t.read_bytes()).hexdigest() for t in [ffmpeg, ffprobe]},
              "required_encoders": required, "encoder_inventory": encoders,
              "decoder_inventory": run(ffmpeg, ["-hide_banner", "-decoders"]),
              "listed_hwaccels": run(ffmpeg, ["-hide_banner", "-hwaccels"]),
              "hardware_tests": [], "synthetic_tests": []}
    if not args.inspect_only:
        # 0.5 s, 64x64 RGB + 24,000 stereo float samples, all generated locally.
        frames, w, h, rate, samples = 12, 64, 64, 48000, 24000
        rgb = bytes((x * 3 + y * 5 + c * 47 + f * 11) % 256
                    for f in range(frames) for y in range(h) for x in range(w) for c in range(3))
        audio = b"".join(struct.pack("<ff", ((i % 97) - 48) / 128, ((i % 89) - 44) / 128)
                         for i in range(samples))
        with tempfile.TemporaryDirectory(prefix="atlas-ffmpeg-") as temp:
            p = Path(temp)
            (p / "rgb.raw").write_bytes(rgb)
            (p / "audio.raw").write_bytes(audio)
            base = ["-hide_banner", "-loglevel", "error", "-nostdin", "-threads", "1", "-filter_threads", "1"]
            vin = ["-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "64x64", "-framerate", "24", "-i", p / "rgb.raw"]
            ain = ["-f", "f32le", "-ar", rate, "-ac", "2", "-i", p / "audio.raw"]
            lossless = p / "lossless.mkv"
            run(ffmpeg, base + vin + ain + ["-c:v", "ffv1", "-level", "3", "-threads:v", "1", "-c:a", "pcm_f32le", lossless])
            vr = run(ffmpeg, base + ["-i", lossless, "-map", "0:v:0", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"], True)
            ar = run(ffmpeg, base + ["-i", lossless, "-map", "0:a:0", "-f", "f32le", "pipe:1"], True)
            if vr != rgb or ar != audio:
                raise SystemExit("FFV1/PCM synthetic round trip did not preserve exact bytes.")
            probe = json.loads(run(ffprobe, ["-v", "error", "-count_frames", "-show_streams", "-of", "json", lossless]))
            streams = {s["codec_type"]: s for s in probe["streams"]}
            if (streams["video"]["codec_name"], int(streams["video"]["nb_read_frames"]), streams["audio"]["codec_name"], int(streams["audio"]["sample_rate"])) != ("ffv1", frames, "pcm_f32le", rate):
                raise SystemExit("FFprobe synthetic stream metadata mismatch.")
            report["synthetic_tests"].append({"codec_pair": ["ffv1", "pcm_f32le"], "RGB8_bitwise": True,
                                               "audio_F32_bitwise": True, "frames": frames, "samples_per_channel": samples,
                                               "ffprobe_streams": probe["streams"]})
            h264 = p / "h264.mp4"
            run(ffmpeg, base + vin + ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", "-threads:v", "1", h264])
            run(ffmpeg, base + ["-i", h264, "-f", "null", "-"])
            hp = json.loads(run(ffprobe, ["-v", "error", "-count_frames", "-show_streams", "-of", "json", h264]))["streams"][0]
            if hp["codec_name"] != "h264" or int(hp["nb_read_frames"]) != frames:
                raise SystemExit("H.264 synthetic frame-count mismatch.")
            report["synthetic_tests"].append({"codec": "libx264/h264", "encode_decode": True, "frames": frames})
    out = ROOT / "build/ffmpeg-qualification.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Atlas FFmpeg/FFprobe {VERSION} {BUILD}: codec inventory verified; {len(report['synthetic_tests'])} CPU synthetic tests; hardware untested.")
    print(out)


if __name__ == "__main__":
    main()
