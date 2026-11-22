#!/usr/bin/env python3
"""Find speaker label differences between a full pass and shorter replays."""
import argparse
import collections
import json
from pathlib import Path


def overlap(a, b):
    return max(0, min(a['end'], b['end']) - max(a['start'], b['start']))


def find_conflicts(audit, min_seconds=4, min_ratio=0.08,
                   max_merge_gap=2.5, min_candidate_span=2):
    result = []
    main = [turn for turn in audit.get('rawTurns', [])
            if turn['end'] > turn['start']]
    for window in audit.get('chunkRuns', []):
        local = [turn for turn in window.get('turns', [])
                 if turn['end'] > turn['start']]
        supports = collections.defaultdict(lambda: collections.defaultdict(float))
        for global_turn in main:
            if global_turn['end'] <= window['start'] or global_turn['start'] >= window['end']:
                continue
            for local_turn in local:
                amount = overlap(global_turn, local_turn)
                if amount > 0:
                    supports[global_turn['id']][local_turn['id']] += amount
        for main_id, labels in supports.items():
            ranked = sorted(labels.items(), key=lambda x: (-x[1], x[0]))
            if not ranked:
                continue
            for secondary_id, seconds in ranked[1:]:
                if seconds < min_seconds or seconds / ranked[0][1] < min_ratio:
                    continue
                pieces = sorted((max(g['start'], l['start']), min(g['end'], l['end']))
                                for g in main if g['id'] == main_id
                                for l in local if l['id'] == secondary_id
                                if overlap(g, l) > 0)
                merged = []
                for start, end in pieces:
                    if merged and start - merged[-1][1] <= max_merge_gap:
                        merged[-1] = (merged[-1][0], max(merged[-1][1], end))
                    else:
                        merged.append((start, end))
                for start, end in merged:
                    if end - start >= min_candidate_span:
                        result.append({'start': start, 'end': end, 'global': main_id,
                                       'local': secondary_id,
                                       'alternateSupportSeconds': seconds,
                                       'windowStart': window['start'],
                                       'windowEnd': window['end']})
    return sorted(result, key=lambda x: (x['start'], x['windowStart']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('audit', type=Path)
    args = parser.parse_args()
    audit = json.loads(args.audit.read_text(encoding='utf-8'))
    if not audit.get('chunkRuns'):
        parser.error('No independent chunkRuns: enable comparison diagnostics in the app.')
    findings = find_conflicts(audit)
    print(f"{audit.get('source')} | {audit.get('method')} | review candidates: {len(findings)}")
    for item in findings:
        print(f"  {item['start']/60:.2f}–{item['end']/60:.2f} min "
              f"(seconds {item['start']:.1f}–{item['end']:.1f}) | "
              f"full={item['global']} local={item['local']} "
              f"window={item['windowStart']:.0f}–{item['windowEnd']:.0f}")
    print('REVIEW ONLY: local IDs are unrelated to full-run IDs. Not DER.')


if __name__ == '__main__':
    main()
