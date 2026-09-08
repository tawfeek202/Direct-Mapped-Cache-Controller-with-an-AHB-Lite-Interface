#!/usr/bin/env python3
"""
compare_with_rtl.py

Scoreboard / cross-check harness.

Replays the SAME CPU transaction sequences that tb_full_chain.v and
tb_cache_controller_top.v drive onto the AHB-Lite slave port, through the
independent Python golden model (cache_reference_model.py), and diffs the
model's predicted RDATA / memory state against the EXPECTED values that
are hard-coded as `check_eq` / `check_bit` assertions in those Verilog
testbenches -- values which are already known-good, since both
testbenches pass with 0 failures under Icarus Verilog (see
Cache_Controller_Project_Report.docx, Section 6).

This does NOT re-run Icarus. It is a second, structurally-independent
implementation of the cache semantics, checked against the same pass/fail
criteria the RTL was checked against. Where both agree, you have two
independent implementations of the spec confirming the same answer --
which is a meaningfully stronger verification claim for the NTI report
than "the RTL testbench passed" alone.

If you additionally want to diff against LIVE Icarus output (not just
the recorded expected values), see the note at the bottom of this file.
"""

from cache_reference_model import CacheModel, MASK32

PASS = "PASS"
FAIL = "FAIL"


class Scoreboard:
    def __init__(self):
        self.results = []  # list of (name, got, expected, status)

    def check_eq(self, name, got, expected):
        got &= MASK32
        expected &= MASK32
        status = PASS if got == expected else FAIL
        self.results.append((name, hex(got), hex(expected), status))

    def check_bit(self, name, got, expected):
        status = PASS if bool(got) == bool(expected) else FAIL
        self.results.append((name, str(int(bool(got))), str(int(bool(expected))), status))

    def summary(self):
        total = len(self.results)
        failed = sum(1 for r in self.results if r[3] == FAIL)
        return total, failed

    def print_report(self, title):
        print(f"\n==== {title} ====")
        for name, got, exp, status in self.results:
            tag = "[PASS]" if status == PASS else "[FAIL]"
            print(f"{tag} {name} : got={got} expected={exp}")
        total, failed = self.summary()
        print(f"---- {total} checks run, {failed} failed ----")


def run_full_chain_sequence():
    """
    Mirrors tb_full_chain.v / tb_cache_controller_top.v Tests 1-6 exactly
    (same addresses, same operations, same expected constants as written
    in the RTL testbenches).
    """
    sb = Scoreboard()
    model = CacheModel()

    # -- Test 1: cold read at addr=0x40 --
    rdata = model.run_transaction(0x40, is_write=False)
    sb.check_eq("T1: read data after miss-fill", rdata, 0xCCCC_0010)

    # -- Test 2: re-read same address (fast hit) --
    rdata = model.run_transaction(0x40, is_write=False)
    sb.check_eq("T2: read data on hit matches", rdata, 0xCCCC_0010)

    # -- Test 3: write-hit then read-back --
    model.run_transaction(0x40, is_write=True, wdata=0xDEAD_BEEF)
    rdata = model.run_transaction(0x40, is_write=False)
    sb.check_eq("T3: read-back after write-hit", rdata, 0xDEAD_BEEF)

    # -- Test 4: write-through reached backing memory --
    sb.check_eq("T4: memory array updated by write-through",
                model.peek_mem_word(0x40), 0xDEAD_BEEF)

    # -- Test 5: second independent line at addr=0x80 --
    rdata = model.run_transaction(0x80, is_write=False)
    sb.check_eq("T5: second line reads correct data", rdata, 0xCCCC_0020)
    rdata = model.run_transaction(0x40, is_write=False)
    sb.check_eq("T5: first line still holds written value", rdata, 0xDEAD_BEEF)

    # -- Test 6: back-to-back transfer, third independent line at 0xC0 --
    rdata = model.run_transaction(0xC0, is_write=False)
    sb.check_eq("T6: third line reads correct data", rdata, 0xCCCC_0030)

    return sb, model


def run_hazard_style_checks():
    """
    Functional analogue of tb_full_chain Test 7 (miss_req level-sensitivity /
    spurious re-fill hazard). We can't observe fill_commit pulses at the
    transaction level (that is signal-level, protocol-timing behavior that
    only the RTL simulation can show), but we CAN independently check the
    architectural invariant the hazard test cares about: a single CPU
    transaction to a new line results in exactly ONE fill's worth of data
    being installed, and re-reading afterward is stable (no data corruption
    from a hypothetical double-fill).
    """
    sb = Scoreboard()
    model = CacheModel()

    fills_before = model.fill_count
    rdata = model.run_transaction(0x140, is_write=False)
    fills_after = model.fill_count

    sb.check_eq("T7: read data correct on new line 0x140", rdata, 0xCCCC_0050)
    sb.check_eq("T7: exactly one fill occurred for one CPU miss",
                fills_after - fills_before, 1)

    # Re-read must be stable / unchanged (no corruption from a hypothetical
    # second fill overwriting with stale/incorrect data)
    rdata2 = model.run_transaction(0x140, is_write=False)
    sb.check_eq("T7: re-read after fill is stable", rdata2, 0xCCCC_0050)

    return sb


def run_write_allocate_check():
    """
    Explicitly exercises the documented deviation: write-miss triggers
    write-allocate (fetch-then-retry), not a no-write-allocate policy.
    This is architecturally implied by tb_cache_core.v Test 7
    (write-miss at index=10 tag=0x7, then hits after fill), replayed here
    at the transaction level with a fresh model and an address that has
    never been touched.
    """
    sb = Scoreboard()
    model = CacheModel()

    addr = 0x2C0  # untouched line
    model.run_transaction(addr, is_write=True, wdata=0xCAFEF00D)
    rdata = model.run_transaction(addr, is_write=False)
    sb.check_eq("WA: write-miss then read-back reflects written value",
                rdata, 0xCAFEF00D)
    sb.check_eq("WA: write-through also reached backing memory",
                model.peek_mem_word(addr), 0xCAFEF00D)

    return sb


def main():
    print("Golden Reference Model vs. RTL Testbench Expected Values")
    print("=" * 70)
    print("Model: cache_reference_model.py (independent Python implementation)")
    print("Expected values sourced from: tb_full_chain.v / tb_cache_controller_top.v")
    print("(both RTL testbenches pass 0/N failures under Icarus Verilog)")

    sb1, model = run_full_chain_sequence()
    sb1.print_report("Sequence: tb_full_chain / tb_cache_controller_top Tests 1-6")

    sb2 = run_hazard_style_checks()
    sb2.print_report("Sequence: Test 7 hazard-style check (functional analogue)")

    sb3 = run_write_allocate_check()
    sb3.print_report("Sequence: Write-allocate-on-miss policy check")

    all_boards = [sb1, sb2, sb3]
    total = sum(sb.summary()[0] for sb in all_boards)
    failed = sum(sb.summary()[1] for sb in all_boards)

    print("\n" + "=" * 70)
    print(f"GRAND TOTAL: {total} checks, {failed} failed")
    if failed == 0:
        print("RESULT: Golden model agrees with all RTL-testbench-derived expected values.")
    else:
        print("RESULT: DISAGREEMENT FOUND -- investigate model vs. RTL discrepancy.")
    print("=" * 70)


if __name__ == "__main__":
    main()

# -----------------------------------------------------------------------
# NOTE on comparing against LIVE Icarus output instead of recorded values:
#
# This script currently compares the model against the *expected constants*
# written into the RTL testbenches (e.g. 0xCCCC_0010), which are trustworthy
# because those testbenches already pass in Icarus Verilog. This is
# equivalent to comparing against Icarus's actual output, without needing
# a Verilog toolchain available in this environment.
#
# If you want a literal live diff instead (RTL simulator invoked fresh,
# stdout parsed, compared line-by-line to this model's output), that just
# needs Icarus Verilog installed wherever this runs:
#
#   iverilog -g2001 -o sim tag_valid_array.v comparator.v data_line_array.v \
#       cache_core.v cpu_side_slave_fsm.v mem_side_master_fsm.v \
#       ahb_mem_model.v cache_controller_top.v tb_full_chain.v
#   vvp sim > rtl_output.log
#
# then a small parser can grep the [PASS]/[FAIL] lines and the numeric
# rdata values out of rtl_output.log and compare them directly to this
# model's `sb.results`. I can write that parser too if you get iverilog
# running locally and paste me a sample log.
# -----------------------------------------------------------------------
