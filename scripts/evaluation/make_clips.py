#!/usr/bin/env python3
"""Generate listening clips with ffmpeg; source audio never enters the source ZIP."""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=Path('benchmarks/references.json'))
    parser.add_argument('--audio', action='append', required=True, metavar='ID=PATH')
    parser.add_argument('--output-dir', type=Path, default=Path('benchmarks/local/clips'))
    args = parser.parse_args()
    data = json.loads(args.reference.read_text(encoding='utf-8'))
    audio = dict(item.split('=', 1) for item in args.audio)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for case in data['cases']:
        target = args.output_dir / f"{case['id']}.m4a"
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
            '-ss', str(case['start']), '-i', str(audio[case['recording']]),
            '-t', str(case['end'] - case['start']), '-vn',
            '-ac', '1', '-ar', '24000', '-c:a', 'aac', '-b:a', '96k', str(target),
        ], check=True)
        print(target)


if __name__ == '__main__':
    main()
