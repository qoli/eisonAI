#!/usr/bin/env python3
import argparse
import fnmatch
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


@dataclass(frozen=True)
class FileEntry:
    rel: str
    size: int
    digest: str
    chunk_digests: Tuple[str, ...]


@dataclass(frozen=True)
class Match:
    other_rel: Optional[str]
    similarity: float
    reason: str


def _iter_files(root: Path, ignore_globs: List[str]) -> Iterable[Path]:
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        rel = path.relative_to(root).as_posix()
        if any(fnmatch.fnmatch(rel, pat) for pat in ignore_globs):
            continue
        yield path


def _hash_file_with_chunks(path: Path, algo: str, chunk_size: int) -> Tuple[str, Tuple[str, ...]]:
    file_hash = hashlib.new(algo)
    chunk_hashes: List[str] = []
    with path.open("rb") as f:
        while True:
            b = f.read(chunk_size)
            if not b:
                break
            file_hash.update(b)
            chunk_hashes.append(hashlib.new(algo, b).hexdigest())
    return file_hash.hexdigest(), tuple(chunk_hashes)


def _scan(root: Path, algo: str, chunk_size: int, ignore_globs: List[str]) -> Tuple[List[FileEntry], int]:
    entries: List[FileEntry] = []
    total_bytes = 0
    for path in _iter_files(root, ignore_globs=ignore_globs):
        st = path.stat()
        digest, chunk_digests = _hash_file_with_chunks(path, algo=algo, chunk_size=chunk_size)
        rel = path.relative_to(root).as_posix()
        entries.append(FileEntry(rel=rel, size=st.st_size, digest=digest, chunk_digests=chunk_digests))
        total_bytes += st.st_size
    return entries, total_bytes


def _bytes_human(n: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    value = float(n)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.2f} {unit}"
        value /= 1024
    return f"{n} B"


def _file_similarity(a: FileEntry, b: FileEntry) -> Match:
    if a.digest == b.digest:
        return Match(other_rel=b.rel, similarity=1.0, reason="exact")
    if not a.chunk_digests and not b.chunk_digests:
        return Match(other_rel=b.rel, similarity=0.0, reason="empty")
    common = 0
    for i in range(min(len(a.chunk_digests), len(b.chunk_digests))):
        if a.chunk_digests[i] == b.chunk_digests[i]:
            common += 1
    denom = max(len(a.chunk_digests), len(b.chunk_digests))
    sim = 0.0 if denom == 0 else common / denom
    return Match(other_rel=b.rel, similarity=sim, reason="chunk")


def _best_match(entry: FileEntry, others: List[FileEntry]) -> Match:
    if not others:
        return Match(other_rel=None, similarity=0.0, reason="no-candidates")
    best = Match(other_rel=None, similarity=-1.0, reason="no-candidates")
    best_name_bonus = False
    basename = Path(entry.rel).name

    for other in others:
        m = _file_similarity(entry, other)
        name_bonus = Path(other.rel).name == basename
        if m.similarity > best.similarity:
            best = m
            best_name_bonus = name_bonus
        elif m.similarity == best.similarity and name_bonus and not best_name_bonus:
            best = m
            best_name_bonus = True

    if best.other_rel is None:
        return best
    if best.reason == "exact":
        return best
    if best_name_bonus:
        return Match(other_rel=best.other_rel, similarity=best.similarity, reason=f"{best.reason}+name")
    return best


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare two directory trees by content hash and report reusable/identical files."
    )
    parser.add_argument("dir_a", type=Path)
    parser.add_argument("dir_b", type=Path)
    parser.add_argument("--algo", default="sha256", help="Hash algorithm (default: sha256)")
    parser.add_argument("--chunk-size", type=int, default=8 * 1024 * 1024, help="Read chunk size in bytes")
    parser.add_argument(
        "--ignore",
        action="append",
        default=[],
        help="Ignore relative path glob (repeatable), e.g. --ignore '**/.DS_Store'",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=1,
        help="For each file, print top-K similar matches from the other directory (default: 1).",
    )
    parser.add_argument(
        "--all-pairs",
        action="store_true",
        help="Compute and emit similarity for all A×B pairs (can be large).",
    )
    parser.add_argument("--json", dest="json_path", type=Path, default=None, help="Write JSON report to path")
    args = parser.parse_args()

    dir_a = args.dir_a.resolve()
    dir_b = args.dir_b.resolve()
    if not dir_a.exists() or not dir_a.is_dir():
        raise SystemExit(f"Not a directory: {dir_a}")
    if not dir_b.exists() or not dir_b.is_dir():
        raise SystemExit(f"Not a directory: {dir_b}")

    entries_a, bytes_a = _scan(dir_a, algo=args.algo, chunk_size=args.chunk_size, ignore_globs=args.ignore)
    entries_b, bytes_b = _scan(dir_b, algo=args.algo, chunk_size=args.chunk_size, ignore_globs=args.ignore)

    by_hash_a: Dict[str, List[FileEntry]] = {}
    by_hash_b: Dict[str, List[FileEntry]] = {}
    for e in entries_a:
        by_hash_a.setdefault(e.digest, []).append(e)
    for e in entries_b:
        by_hash_b.setdefault(e.digest, []).append(e)

    hashes_a = set(by_hash_a)
    hashes_b = set(by_hash_b)
    common_hashes = hashes_a & hashes_b

    reusable_a_files = [e for e in entries_a if e.digest in by_hash_b]
    reusable_b_files = [e for e in entries_b if e.digest in by_hash_a]
    reusable_a_bytes = sum(e.size for e in reusable_a_files)
    reusable_b_bytes = sum(e.size for e in reusable_b_files)

    unique_a_hashes = hashes_a - hashes_b
    unique_b_hashes = hashes_b - hashes_a

    def top_k_matches(entry: FileEntry, others: List[FileEntry], k: int) -> List[Match]:
        scored: List[Match] = []
        basename = Path(entry.rel).name
        for other in others:
            m = _file_similarity(entry, other)
            name_bonus = Path(other.rel).name == basename
            reason = m.reason + ("+name" if name_bonus and m.reason != "exact" else "")
            scored.append(Match(other_rel=other.rel, similarity=m.similarity, reason=reason))
        scored.sort(key=lambda x: (x.similarity, x.reason.endswith("+name")), reverse=True)
        if scored and scored[0].similarity > 0:
            scored = [m for m in scored if m.similarity > 0]
        return scored[: max(k, 0)]

    best_matches_a = {e.rel: _best_match(e, entries_b) for e in entries_a}
    best_matches_b = {e.rel: _best_match(e, entries_a) for e in entries_b}
    weighted_sim_a = sum(e.size * best_matches_a[e.rel].similarity for e in entries_a) / bytes_a if bytes_a else 0.0
    weighted_sim_b = sum(e.size * best_matches_b[e.rel].similarity for e in entries_b) / bytes_b if bytes_b else 0.0

    all_pairs: Optional[List[dict]] = None
    if args.all_pairs:
        all_pairs = []
        for a in entries_a:
            for b in entries_b:
                m = _file_similarity(a, b)
                all_pairs.append(
                    {
                        "a_rel": a.rel,
                        "b_rel": b.rel,
                        "similarity": m.similarity,
                        "reason": m.reason,
                    }
                )

    report = {
        "algo": args.algo,
        "dir_a": str(dir_a),
        "dir_b": str(dir_b),
        "dir_a_files": len(entries_a),
        "dir_b_files": len(entries_b),
        "dir_a_bytes": bytes_a,
        "dir_b_bytes": bytes_b,
        "common_unique_contents": len(common_hashes),
        "dir_a_reusable_files": len(reusable_a_files),
        "dir_a_reusable_bytes": reusable_a_bytes,
        "dir_b_reusable_files": len(reusable_b_files),
        "dir_b_reusable_bytes": reusable_b_bytes,
        "dir_a_only_unique_contents": len(unique_a_hashes),
        "dir_b_only_unique_contents": len(unique_b_hashes),
        "dir_a_only_examples": [by_hash_a[h][0].rel for h in sorted(unique_a_hashes)[:10]],
        "dir_b_only_examples": [by_hash_b[h][0].rel for h in sorted(unique_b_hashes)[:10]],
        "dir_a_weighted_best_similarity": weighted_sim_a,
        "dir_b_weighted_best_similarity": weighted_sim_b,
        "dir_a_best_matches": {
            rel: {"other_rel": m.other_rel, "similarity": m.similarity, "reason": m.reason}
            for rel, m in best_matches_a.items()
        },
        "dir_b_best_matches": {
            rel: {"other_rel": m.other_rel, "similarity": m.similarity, "reason": m.reason}
            for rel, m in best_matches_b.items()
        },
        "all_pairs": all_pairs,
    }

    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def pct(part: int, total: int) -> str:
        return "n/a" if total == 0 else f"{(part / total) * 100:.3f}%"

    def pct_float(part: float) -> str:
        return f"{part * 100:.3f}%"

    print(f"A: {dir_a}")
    print(f"  - files: {len(entries_a)}")
    print(f"  - bytes: {bytes_a} ({_bytes_human(bytes_a)})")
    print(f"B: {dir_b}")
    print(f"  - files: {len(entries_b)}")
    print(f"  - bytes: {bytes_b} ({_bytes_human(bytes_b)})")
    print("---")
    print(f"Common unique contents (by {args.algo}): {len(common_hashes)}")
    print(
        f"A -> B reusable: {len(reusable_a_files)}/{len(entries_a)} files, "
        f"{reusable_a_bytes}/{bytes_a} bytes ({pct(reusable_a_bytes, bytes_a)})"
    )
    print(
        f"B -> A reusable: {len(reusable_b_files)}/{len(entries_b)} files, "
        f"{reusable_b_bytes}/{bytes_b} bytes ({pct(reusable_b_bytes, bytes_b)})"
    )
    print("---")
    print(f"A-only unique contents: {len(unique_a_hashes)}")
    if unique_a_hashes:
        for rel in report["dir_a_only_examples"]:
            print(f"  - {rel}")
    print(f"B-only unique contents: {len(unique_b_hashes)}")
    if unique_b_hashes:
        for rel in report["dir_b_only_examples"]:
            print(f"  - {rel}")

    print("---")
    print(f"A best-match similarity (bytes-weighted): {pct_float(weighted_sim_a)}")
    print(f"B best-match similarity (bytes-weighted): {pct_float(weighted_sim_b)}")

    print("---")
    print("A -> B per-file similarity:")
    for e in sorted(entries_a, key=lambda x: x.rel):
        matches = top_k_matches(e, entries_b, args.top_k)
        if not matches:
            print(f"  - {e.rel}: 0.000% (no match)")
            continue
        first = matches[0]
        print(f"  - {e.rel}: {pct_float(first.similarity)} ({first.reason}) -> {first.other_rel}")
        for extra in matches[1:]:
            print(f"    + {pct_float(extra.similarity)} ({extra.reason}) -> {extra.other_rel}")

    print("---")
    print("B -> A per-file similarity:")
    for e in sorted(entries_b, key=lambda x: x.rel):
        matches = top_k_matches(e, entries_a, args.top_k)
        if not matches:
            print(f"  - {e.rel}: 0.000% (no match)")
            continue
        first = matches[0]
        print(f"  - {e.rel}: {pct_float(first.similarity)} ({first.reason}) -> {first.other_rel}")
        for extra in matches[1:]:
            print(f"    + {pct_float(extra.similarity)} ({extra.reason}) -> {extra.other_rel}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
