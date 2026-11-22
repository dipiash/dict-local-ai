#!/usr/bin/env python3
"""Summarize opt-in Dict Local AI diarization JSON without printing transcript text."""
import argparse
import collections
import json
import math
from pathlib import Path


def minutes(seconds: float) -> str:
    return f"{int(seconds // 60):02}:{seconds % 60:04.1f}"


def unknown_spans(words, max_gap=1.0):
    spans = []
    first = last = None
    count = 0
    for word in words:
        if word.get("assignedSpeaker") is None:
            if first is not None and word["start"] - last <= max_gap:
                count += 1
                last = max(last, word["end"])
            else:
                if first is not None:
                    spans.append((first, last, count))
                first, last, count = word["start"], word["end"], 1
        elif first is not None:
            spans.append((first, last, count))
            first = last = None
    if first is not None:
        spans.append((first, last, count))
    return sorted(spans, key=lambda span: (span[2], span[1] - span[0]), reverse=True)


def matched_window_summaries(observations):
    """Compare only explicitly complete windows at identical absolute offsets."""
    results = []
    targets = sorted({o['start'] for o in observations if o['stage'] == 'segmentation_window'})
    for start in targets:
        def windows(stage, offset):
            found = {}
            for item in observations:
                metrics = item.get('metrics', {})
                if (item['start'] == start and item['stage'] == stage
                        and metrics.get('windowComplete') == 1):
                    moment = metrics.get('chunkOffsetSeconds')
                    mean, peak = metrics.get('speechProbabilityMean'), metrics.get('speechProbabilityMax')
                    if all(isinstance(x, (int, float)) and math.isfinite(x) for x in (moment, mean, peak)):
                        found[round(moment + offset, 9)] = (mean, peak)
            return found
        full = windows('segmentation_window', 0)
        for size in (20, 180):
            prefix = f'replay_{size}s'
            summary = next((o for o in observations if o['start'] == start and o['stage'] == prefix + '_summary'), None)
            offset = summary.get('metrics', {}).get('replayWindowStart') if summary else None
            replay = windows(prefix + '_segmentation_window', offset) if isinstance(offset, (int, float)) else {}
            common = sorted(full.keys() & replay.keys())
            results.append({
                'start': start, 'replaySeconds': size, 'commonCompleteWindows': len(common),
                'maxMeanSummaryDifference': max((abs(full[t][0] - replay[t][0]) for t in common), default=None),
                'maxPeakSummaryDifference': max((abs(full[t][1] - replay[t][1]) for t in common), default=None),
            })
    return results


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("json", type=Path, help="Speaker diagnostic JSON exported from File mode")
    args = cli.parse_args()
    data = json.loads(args.json.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 3 or not isinstance(data.get("words"), list):
        cli.error("Unsupported or invalid diarization audit JSON")
    words = data["words"]
    counts = collections.Counter(w["reason"] for w in words if w.get("assignedSpeaker") is None)
    assigned = sum(w.get("assignedSpeaker") is not None for w in words)
    print(f"Source: {data.get('source')} | method={data.get('method')} | duration={minutes(data['duration'])}")
    print(f"ASR words: {len(words)}; assigned: {assigned}; unknown: {len(words) - assigned}")
    print(f"Unknown reasons: {dict(counts)}")
    print("Longest Unknown spans (ASR-based, not acoustic DER):")
    for start, end, count in unknown_spans(words)[:10]:
        print(f"  {minutes(start)}–{minutes(end)}: {count} words")
    runs = data.get("chunkRuns", [])
    if runs:
        print("Comparative runs (local speaker IDs must NEVER be matched across rows):")
        for run in runs:
            print(f"  {minutes(run['start'])}–{minutes(run['end'])} | "
                  f"window={run['windowSeconds']/60:g}m | "
                  f"threshold={run.get('clusteringThreshold', 0.6):.2f} | "
                  f"speakers={run['distinctSpeakers']} | "
                  f"raw word coverage={run['wordCoverage']:.1%}")
    observations = data.get("pipelineObservations") or []
    if observations:
        print("Pipeline probes (overlapping observations, not unique speech duration):")
        for observation in observations:
            if observation["stage"].endswith("embedding_window"):
                continue  # many metadata-only trace records; summarize below
            metrics = " ".join(f"{key}={value:g}" for key, value in sorted(observation["metrics"].items()))
            print(f"  {minutes(observation['start'])}–{minutes(observation['end'])} | "
                  f"{observation['stage']} | {metrics} | {observation.get('note', '')}")
        traces = [o for o in observations if o["stage"].endswith("embedding_window")]
        if traces:
            reasons = collections.Counter(o.get("note", "unknown") for o in traces)
            print(f"Embedding trace: {len(traces)} windows; statuses={dict(reasons)}")
        if any(o['stage'].startswith('replay_') for o in observations):
            print('WARNING: pooled replay probabilities include different or padded windows; they are not a controlled comparison.')
        for match in matched_window_summaries(observations):
            label = f"{minutes(match['start'])} replay={match['replaySeconds']}s"
            if match['commonCompleteWindows'] == 0:
                print(f"Matched complete windows {label}: unavailable (no common explicitly complete windows; padding/unknown completeness excluded).")
            else:
                print(f"Matched complete windows {label}: count={match['commonCompleteWindows']} "
                      f"largest mean-summary difference={match['maxMeanSummaryDifference']:.9g}; "
                      f"largest max-summary difference={match['maxPeakSummaryDifference']:.9g} "
                      '(summary differences, not per-frame equality; padding/unknown completeness excluded).')
    for warning in data.get("warnings", []):
        print(f"WARNING: {warning}")
    print("No ground-truth speaker reference: raw coverage is NOT diarization error rate (DER).")


if __name__ == "__main__":
    main()
