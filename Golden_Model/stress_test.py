#!/usr/bin/env python3
"""
stress_test.py

Extends verification beyond the RTL testbenches' hand-picked addresses by
exercising the golden model with pseudo-random, deterministic (seeded)
transaction sequences: random mix of reads/writes across many lines and
word offsets, then cross-checks strictly against a from-scratch software
"dumb array" model (a plain 256-word array with NO cache in front of it,
representing exactly what backing memory should end up containing).

This checks a property the RTL testbenches don't check directly:
after ANY sequence of CPU transactions, does the FINAL STATE of backing
memory match what a "no cache at all, memory-mapped directly" system
would have produced? Since the design is write-through, memory content
must always converge to exactly what a direct (uncached) system would
hold, regardless of hit/miss history. This is a strong invariant check
independent of cache internals.
"""

import random
from cache_reference_model import CacheModel, BackingMemory, MASK32

NUM_WORDS = 256


def run_stress(seed: int, num_ops: int = 500):
    random.seed(seed)

    model = CacheModel()
    # "Truth" model: direct memory, no cache, same init pattern
    truth = BackingMemory(num_words=NUM_WORDS)

    mismatches = []

    for i in range(num_ops):
        word_idx = random.randrange(NUM_WORDS)
        addr = word_idx * 4
        is_write = random.random() < 0.5

        if is_write:
            wdata = random.getrandbits(32)
            model.run_transaction(addr, is_write=True, wdata=wdata)
            truth.write_word(addr, wdata)
        else:
            got = model.run_transaction(addr, is_write=False)
            expected = truth.read_word(addr)
            if got != expected:
                mismatches.append((i, hex(addr), hex(got), hex(expected)))

    # Final full-memory-image comparison (write-through invariant)
    mem_mismatches = []
    for w in range(NUM_WORDS):
        cache_mem_val = model.peek_mem_word(w * 4)
        truth_val = truth.read_word(w * 4)
        if cache_mem_val != truth_val:
            mem_mismatches.append((w, hex(w * 4), hex(cache_mem_val), hex(truth_val)))

    return mismatches, mem_mismatches, model


def main():
    print("Randomized Stress / Invariant Cross-Check")
    print("=" * 70)
    print("Property under test: write-through cache's backing memory must")
    print("always match a direct (uncached) memory system after the same")
    print("transaction sequence, regardless of hit/miss history.\n")

    seeds = [1, 2, 3, 42, 12345]
    total_ops_all = 0
    total_mismatches_all = 0
    total_mem_mismatches_all = 0

    for seed in seeds:
        mismatches, mem_mismatches, model = run_stress(seed, num_ops=500)
        total_ops_all += 500
        total_mismatches_all += len(mismatches)
        total_mem_mismatches_all += len(mem_mismatches)

        status = "PASS" if not mismatches and not mem_mismatches else "FAIL"
        print(f"[seed={seed}] 500 ops | read mismatches={len(mismatches)} "
              f"| final-memory-image mismatches={len(mem_mismatches)} "
              f"| fills={model.fill_count} write-throughs={model.write_through_count} "
              f"-> {status}")

        for m in mismatches[:5]:
            print(f"    READ MISMATCH: op#{m[0]} addr={m[1]} got={m[2]} expected={m[3]}")
        for m in mem_mismatches[:5]:
            print(f"    MEM MISMATCH: word={m[0]} addr={m[1]} got={m[2]} expected={m[3]}")

    print("\n" + "=" * 70)
    print(f"TOTAL: {total_ops_all} random ops across {len(seeds)} seeds")
    print(f"Read mismatches: {total_mismatches_all}")
    print(f"Final-memory-image mismatches: {total_mem_mismatches_all}")
    if total_mismatches_all == 0 and total_mem_mismatches_all == 0:
        print("RESULT: Write-through invariant holds across all randomized sequences.")
    else:
        print("RESULT: INVARIANT VIOLATION FOUND.")
    print("=" * 70)


if __name__ == "__main__":
    main()
