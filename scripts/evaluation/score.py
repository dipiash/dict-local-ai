#!/usr/bin/env python3
"""Score transcript and speaker labels against verified audio clips."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import unicodedata


def validate_case(case):
    if case.get('verified') is not True:
        return False
    if not case.get('reference_text', '').strip():
        raise ValueError(f"{case['id']}: verified=true but reference_text is empty")
    turns = case.get('speaker_turns', [])
    if not turns:
        raise ValueError(f"{case['id']}: verified=true but speaker_turns is empty")
    lo, hi = case['start'], case['end']
    for t in turns:
        if not (lo <= t['start'] < t['end'] <= hi):
            raise ValueError(f"{case['id']}: speaker turn outside its fully labelled window")
        if not str(t['speaker']).strip():
            raise ValueError(f"{case['id']}: speaker label missing")
    return True


def audit_words(audit, lo, hi):
    return ' '.join(w['text'] for w in audit['words']
                    if lo <= (w['start'] + w['end']) / 2 < hi)


def normalize(text):
    text = ''.join(' ' if unicodedata.category(ch).startswith('P') else ch
                   for ch in text.casefold())
    return text.split()


def word_edits(reference, hypothesis):
    """Exact Levenshtein alignment; substitutions, insertions, deletions, hits."""
    a, b = normalize(reference), normalize(hypothesis)
    previous = [(j, 0, j, 0, 0) for j in range(len(b) + 1)]
    for i, left in enumerate(a, 1):
        row = [(i, 0, 0, i, 0)]
        for j, right in enumerate(b, 1):
            diagonal = previous[j - 1]
            if left == right:
                sub = (diagonal[0], diagonal[1], diagonal[2], diagonal[3], diagonal[4] + 1)
            else:
                sub = (diagonal[0] + 1, diagonal[1] + 1,
                       diagonal[2], diagonal[3], diagonal[4])
            deleted = previous[j]
            deleted = (deleted[0] + 1, deleted[1], deleted[2], deleted[3] + 1, deleted[4])
            inserted = row[j - 1]
            inserted = (inserted[0] + 1, inserted[1], inserted[2] + 1, inserted[3], inserted[4])
            row.append(min([sub, deleted, inserted], key=lambda t: t[0]))
        previous = row
    edits, sub, ins, dele, hits = previous[-1]
    return {'wer': edits / len(a) if a else 0.0,
            'sub': sub, 'ins': ins, 'del': dele, 'hits': hits}


def score(reference, audits, selected_split=None):
    try:
        from pyannote.core import Annotation, Segment, Timeline
        from pyannote.metrics.diarization import DiarizationErrorRate
    except ImportError as error:
        raise RuntimeError('Install scorer tools: python3 -m pip install -r scripts/evaluation/requirements.txt') from error

    # Per-window matching can hide speaker swaps.
    metric = DiarizationErrorRate(collar=0.0, skip_overlap=False)
    by_recording = {}
    counts = {'sub': 0, 'ins': 0, 'del': 0, 'hits': 0}
    output = []
    verified = 0
    for case in reference['cases']:
        if selected_split and case.get('split') != selected_split:
            continue
        if not validate_case(case):
            continue
        verified += 1
        key = case['recording']
        if key not in audits:
            raise ValueError(f"Missing --audit {key}=/path/to/audit.json for {case['id']}")
        a = audits[key]
        if case['end'] > float(a['duration']) + 1:
            raise ValueError(f"Case {case['id']} beyond audio duration")
        if a.get('method') != 'nemotron3-fast128':
            raise ValueError(f"Unexpected diarizer {a.get('method')}")
        lo, hi = case['start'], case['end']
        hyp_text = audit_words(a, lo, hi)
        words = word_edits(case['reference_text'], hyp_text)
        counts['sub'] += words['sub']
        counts['ins'] += words['ins']
        counts['del'] += words['del']
        counts['hits'] += words['hits']
        ref = Annotation(uri=case['id'])
        hyp = Annotation(uri=case['id'])
        for i, t in enumerate(case['speaker_turns']):
            ref[Segment(t['start'], t['end']), i] = t['speaker']
        for i, t in enumerate(a['rawTurns']):
            start, end = max(lo, t['start']), min(hi, t['end'])
            if end > start:
                hyp[Segment(start, end), i] = t['id']
        local_metric = DiarizationErrorRate(collar=0.0, skip_overlap=False)
        detail = local_metric(ref, hyp, uem=Timeline(segments=[Segment(lo, hi)]), detailed=True)
        if key not in by_recording:
            by_recording[key] = {
                'reference': Annotation(uri=key),
                'hypothesis': Annotation(uri=key),
                'windows': [],
            }
        recording = by_recording[key]
        recording['windows'].append(Segment(lo, hi))
        for segment, track, label in ref.itertracks(yield_label=True):
            recording['reference'][segment, (case['id'], track)] = label
        for segment, track, label in hyp.itertracks(yield_label=True):
            recording['hypothesis'][segment, (case['id'], track)] = label
        output.append({
            'case': case['id'],
            'wer': round(words['wer'], 4),
            'wer_reference_words': words['hits'] + words['sub'] + words['del'],
            'wer_substitutions': words['sub'],
            'wer_deletions': words['del'],
            'wer_insertions': words['ins'],
            'der': round(float(detail['diarization error rate']), 4),
            'der_confusion_seconds': round(float(detail['confusion']), 3),
            'der_missed_seconds': round(float(detail['missed detection']), 3),
            'der_false_alarm_seconds': round(float(detail['false alarm']), 3),
        })
    if verified == 0:
        raise ValueError('No VERIFIED reference cases. Listen and annotate, then set verified=true.')
    global_by_recording = {}
    for key, row in by_recording.items():
        detail = metric(
            row['reference'], row['hypothesis'],
            uem=Timeline(segments=row['windows']), detailed=True)
        global_by_recording[key] = {
            'der': float(detail['diarization error rate']),
            'confusion_seconds': float(detail['confusion']),
            'missed_seconds': float(detail['missed detection']),
            'false_alarm_seconds': float(detail['false alarm']),
        }
    denominator = counts['hits'] + counts['sub'] + counts['del']
    if not denominator:
        raise ValueError('No reference words')
    return {
        'reviewed_cases': verified,
        'wer': (counts['sub'] + counts['ins'] + counts['del']) / denominator,
        'wer_components': counts,
        'der': abs(metric),
        'der_by_recording': global_by_recording,
        'metric_policy': {'collar': 0.0, 'skip_overlap': False, 'timestamp_units': 'seconds'},
        'cases': output,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=Path('benchmarks/references.json'))
    parser.add_argument('--audit', action='append', default=[], metavar='NAME=PATH')
    parser.add_argument('--audio', action='append', default=[], metavar='NAME=PATH',
                        help='Optionally verify original audio SHA-256 against the reference manifest')
    parser.add_argument('--output', type=Path, help='Optional JSON score report')
    parser.add_argument('--split', choices=['calibration', 'holdout'],
                        help='Score only this evaluation partition')
    args = parser.parse_args()
    refs = json.loads(args.reference.read_text(encoding='utf-8'))
    audits = {}
    for argument in args.audit:
        if '=' not in argument:
            parser.error('--audit expects name=/absolute/path/audit.json')
        name, path = argument.split('=', 1)
        audits[name] = json.loads(Path(path).read_text(encoding='utf-8'))
    try:
        verified_audio = {}
        for argument in args.audio:
            if '=' not in argument:
                parser.error('--audio expects name=/absolute/path/source.m4a')
            name, path = argument.split('=', 1)
            if name not in refs['recordings']:
                raise ValueError(f'Unknown recording {name}')
            with Path(path).open('rb') as file:
                digest = hashlib.file_digest(file, 'sha256').hexdigest()
            expected = refs['recordings'][name]['source_sha256']
            if digest != expected:
                raise ValueError(f'{name}: audio SHA-256 differs from benchmark source')
            verified_audio[name] = True
        result = score(refs, audits, selected_split=args.split)
        result['verified_audio_sha256'] = verified_audio
        result['split'] = args.split or 'all'
    except (ValueError, RuntimeError) as exc:
        print(f'Cannot score: {exc}', file=sys.stderr)
        return 2
    value = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    print(value)
    if args.output:
        args.output.write_text(value + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
