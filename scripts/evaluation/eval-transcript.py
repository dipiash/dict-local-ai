#!/usr/bin/env python3
"""Measure word errors against a checked transcript."""
import argparse
import json
import re
from pathlib import Path

TIME = re.compile(r"^\[\d{2}:\d{2}:\d{2}(?:\.\d+)?[–-]\d{2}:\d{2}:\d{2}(?:\.\d+)?\]\s*")
CHANNEL = re.compile(r"^\[(?:Микрофон|Звук компьютера|Microphone|System Audio)\]\s*")
SPEAKER = re.compile(
    r"^(?:(?:Микрофон|Созвон|Microphone|Call) · )?"
    r"(?:Спикер(?: не определён| \d+)?|Speaker(?: \d+)?|Unknown Speaker):\s*"
)
WORDS = re.compile(r"[^\W_]+(?:['’\-][^\W_]+)*", flags=re.UNICODE)


def get_text(path: Path, export: bool) -> str:
    data = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        document = json.loads(data)
        if not isinstance(document, dict) or not isinstance(document.get("segments"), list):
            raise ValueError("Expected Dict Local AI transcript JSON with segments")
        return " ".join(s["text"] for s in document["segments"])
    if export:
        lines = []
        for line in data.splitlines():
            match = TIME.match(line)
            if match:
                lines.append(SPEAKER.sub("", CHANNEL.sub("", line[match.end():])))
        if not lines:
            raise ValueError("Expected transcript timecoded segments, found none")
        return " ".join(lines)
    return data


def normalize(text: str) -> list[str]:
    return WORDS.findall(text.casefold())


def count_errors(reference: list[str], hypothesis: list[str]) -> tuple[int, int, int]:
    """Rolling DP counts (substitutions, deletions, insertions) with O(M) memory."""
    prev = [(j, 0, 0, j) for j in range(len(hypothesis) + 1)]
    for i, expected in enumerate(reference, 1):
        current = [(i, 0, i, 0)]
        for j, actual in enumerate(hypothesis, 1):
            match = prev[j - 1]
            if expected != actual:
                match = (match[0] + 1, match[1] + 1, match[2], match[3])
            deletion = prev[j]
            deletion = (deletion[0] + 1, deletion[1], deletion[2] + 1, deletion[3])
            insertion = current[j - 1]
            insertion = (insertion[0] + 1, insertion[1], insertion[2], insertion[3] + 1)
            current.append(min((match, deletion, insertion), key=lambda t: (t[0], t[2], t[3])))
        prev = current
    _, sub, delete, insert = prev[-1]
    return sub, delete, insert


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path, help="Manually checked plain UTF-8 text")
    parser.add_argument("--hypothesis", required=True, type=Path, help="Dict Local AI TXT or JSON export")
    parser.add_argument("--reference-status", choices=["draft", "verified"], default="draft")
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()
    ref = normalize(get_text(args.reference, export=False))
    hyp = normalize(get_text(args.hypothesis, export=True))
    if not ref:
        parser.error("reference contains no words")
    sub, delete, insert = count_errors(ref, hyp)
    result = {
        "reference_status": args.reference_status,
        "reference_words": len(ref), "hypothesis_words": len(hyp),
        "substitutions": sub, "deletions": delete, "insertions": insert,
        "wer": (sub + delete + insert) / len(ref),
        "valid_for_quality_claims": args.reference_status == "verified",
    }
    if args.json_output:
        args.json_output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if args.reference_status != "verified":
        print("WARNING: reference not verified against audio; WER is diagnostic only.")


if __name__ == "__main__":
    main()
