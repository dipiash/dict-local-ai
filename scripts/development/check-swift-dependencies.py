#!/usr/bin/env python3
"""Check for cycles between components of the macOS executable target."""

from collections import defaultdict
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
MAC = ROOT / "Sources" / "DictLocalAI"
TYPE_DECLARATION = re.compile(
    r"(?m)^(?:@[\w.]+(?:\([^\n]*\))?\s+|"
    r"(?:public|internal|package|private|fileprivate|final|nonisolated|indirect) +)*"
    r"(?:class|struct|enum|protocol|actor|typealias) +([A-Z]\w*)\b"
)
TYPE_REFERENCE = re.compile(r"\b[A-Z]\w*\b")
TRIVIA = re.compile(
    r"//[^\n]*"
    r"|/\*[\s\S]*?\*/"
    r'|(?P<hashes>#+)(?P<raw_quote>"""|")[\s\S]*?(?P=raw_quote)(?P=hashes)'
    r'|"""[\s\S]*?"""'
    r'|"(?:\\[^\n]|[^"\\\n])*"'
)


def component(path):
    directories = path.parts[:-1]
    if directories and directories[0] == "App":
        return "App"
    return "/".join(directories[:2]) or "DictLocalAI"


def source_code(text):
    # Keep newlines and columns stable so declarations remain distinguishable from nested types.
    return TRIVIA.sub(lambda match: re.sub(r"[^\n]", " ", match[0]), text)


def graph_for(directory):
    files = {}
    owners = defaultdict(set)
    for path in sorted(directory.rglob("*.swift")):
        relative = path.relative_to(directory)
        area = component(relative)
        code = source_code(path.read_text(encoding="utf-8"))
        files[relative] = (area, code)
        for name in TYPE_DECLARATION.findall(code):
            owners[name].add(area)

    edges = {area: {} for area, _ in files.values()}
    for path, (area, code) in files.items():
        for name in sorted(set(TYPE_REFERENCE.findall(code))):
            destinations = owners.get(name, set())
            if len(destinations) == 1 and area not in destinations:
                destination = next(iter(destinations))
                edges[area].setdefault(destination, (path, name))
    return edges


def find_cycle(graph):
    visiting = {}
    visited = set()

    def visit(area):
        visiting[area] = len(visiting)
        for dependency in sorted(graph[area]):
            if dependency in visiting:
                trail = list(visiting)
                return trail[visiting[dependency]:] + [dependency]
            if dependency not in visited:
                cycle = visit(dependency)
                if cycle:
                    return cycle
        visiting.pop(area)
        visited.add(area)
        return None

    for area in sorted(graph):
        if area not in visited:
            cycle = visit(area)
            if cycle:
                return cycle
    return None


def main():
    graph = graph_for(MAC)
    cycle = find_cycle(graph)
    if cycle is None:
        print("PASS: macOS source component dependencies are acyclic")
        return 0
    print("Swift component dependency cycle: " + " -> ".join(cycle), file=sys.stderr)
    for source, destination in zip(cycle, cycle[1:]):
        path, name = graph[source][destination]
        print(f"  {path} references {name} ({destination})", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
