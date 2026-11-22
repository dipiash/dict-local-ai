# Speech evaluation

No real recordings, transcripts, or human-reviewed scores are distributed. `references.json` is an intentionally unverified template. Copy it into `benchmarks/local/` and use your own authorized audio. Never commit local datasets or generated results.

For each recording, populate `recordings` with an ID and `source_sha256`. For each case, set `recording`, `start`, `end`, `split` (`calibration` or `holdout`), `reference_text`, and `speaker_turns` (objects with `start`, `end` and `speaker`). Times are absolute seconds in the original audio. Set `verified: true` only after listening and manually checking the full reference. Use stable speaker IDs per recording.

```sh
python3 -m venv .venv-eval
. .venv-eval/bin/activate
pip install -r scripts/evaluation/requirements.txt
mkdir -p benchmarks/local
cp benchmarks/references.json benchmarks/local/references.json
# Fill the local reference first; ffmpeg is needed only for clip generation.
python3 scripts/evaluation/make_clips.py --reference benchmarks/local/references.json --audio example=/path/to/audio.m4a
python3 scripts/evaluation/score.py --reference benchmarks/local/references.json --audit example=/path/to/audit.json --audio example=/path/to/audio.m4a --split holdout --output benchmarks/local/result.json
```

WER uses normalized word-level Levenshtein alignment. DER uses pyannote.metrics with zero collar, overlap included, and one mapping per recording across reviewed windows. Unverified cases are excluded. Word attribution coverage is not DER. Keep calibration and holdout separate; short-window scores are not whole-recording scores.
