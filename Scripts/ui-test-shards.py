#!/usr/bin/env python3
"""Partition every UI test class without maintaining a partial allow-list."""

import argparse
from pathlib import Path
import re
import sys


def partition(root: Path, count: int) -> list[list[str]]:
    classes = []
    for path in sorted(root.glob("*.swift")):
        source = path.read_text()
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
        if not methods:
            continue
        names = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source)
        if len(names) != 1:
            raise ValueError(f"Expected one XCTestCase class in {path}")
        classes.append((names[0], len(methods)))
    if not classes or len({name for name, _ in classes}) != len(classes):
        raise ValueError("Missing or duplicate UI test classes")
    shards = [[] for _ in range(count)]
    weights = [0] * count
    for name, weight in sorted(classes, key=lambda item: (-item[1], item[0])):
        index = min(range(count), key=lambda index: (weights[index], index))
        shards[index].append(f"biliUITests/{name}")
        weights[index] += weight
    if any(not shard for shard in shards):
        raise ValueError("Empty UI test shard")
    return [sorted(shard) for shard in shards]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shard", type=int, required=True, help="1-based shard")
    parser.add_argument("--count", type=int, default=4)
    args = parser.parse_args()
    if not 1 <= args.shard <= args.count:
        parser.error("shard must be between 1 and count")
    root = Path(__file__).resolve().parents[1] / "biliUITests"
    try:
        print("\n".join(partition(root, args.count)[args.shard - 1]))
    except ValueError as error:
        sys.exit(str(error))


if __name__ == "__main__":
    main()
