#!/usr/bin/env python3
"""
cache_reference_model.py

Independent, transaction-level GOLDEN REFERENCE MODEL of the
Direct-Mapped Cache Controller with AHB-Lite Interface
(NTI HireReady DEY Program).

Purpose
-------
This is NOT a translation of the RTL. It is written from the architectural
specification only (address breakdown, line size, write policy) so that it
can act as an independent check on the RTL's behavior, the same way a
verification engineer would build a scoreboard/reference model separate
from the design.

It simulates the system at the AHB transaction level: given a sequence of
(address, is_write, wdata) CPU transactions, it predicts the RDATA that
should come back and the final state of "backing memory", exactly as a
CPU sitting on the AHB-Lite slave port would experience it. It does NOT
model AHB signal-level timing (HREADY cycle counts, burst beats) -- that
is what the RTL testbenches already verify at the protocol level. This
model verifies FUNCTIONAL CORRECTNESS: does the cache return the right
data, does write-through/write-allocate work, is line independence
preserved, etc.

Architecture modeled (per approved project spec)
-------------------------------------------------
- 1 KB total capacity
- 64 lines, direct-mapped
- 4 words (16 bytes) per line
- Address breakdown (32-bit):
    tag         = addr[31:10]   (22 bits)
    index       = addr[9:4]     (6 bits)
    word_offset = addr[3:2]     (2 bits)
    byte_offset = addr[1:0]     (2 bits, unused -- word aligned only)
- Write-through: a write-HIT updates the cache line AND backing memory.
- Write-allocate on write-MISS: line is fetched from memory first
  (fetch-then-retry), THEN the write is applied as a write-hit.
  (This mirrors the deliberate deviation from the nominal no-write-allocate
  policy, as documented in the project report / RTL: cpu_side_slave_fsm's
  STATE_COMPLETE re-issues a write as a normal write-hit after a fill.)
- Backing memory model: same pre-initialization pattern as ahb_mem_model.v
  (mem[word_index] = 0xCCCC_0000 + word_index), so results line up
  numerically with the RTL testbenches for direct comparison.

This file has two parts:
  1. The reference model classes (BackingMemory, CacheLine, CacheModel).
  2. A `run_transaction()` API that mimics one AHB-Lite CPU transfer and
     returns (rdata, hit_before_service) -- analogous to what the RTL
     testbenches' `ahb_transfer` task captures.

See compare_with_rtl.py for the scoreboard that replays the same
transaction sequences as tb_full_chain.v / tb_cache_controller_top.v and
diffs this model's output against the RTL testbenches' own expected
values (which are known-good, since those testbenches pass in Icarus
Verilog).
"""

from dataclasses import dataclass, field
from typing import Optional


NUM_LINES = 64
WORDS_PER_LINE = 4
BYTES_PER_WORD = 4
TAG_BITS = 22
INDEX_BITS = 6
WORD_OFF_BITS = 2

MASK32 = 0xFFFF_FFFF


def split_address(addr: int):
    """Break a 32-bit word-aligned address into (tag, index, word_offset)."""
    addr &= MASK32
    byte_offset = addr & 0x3
    word_offset = (addr >> 2) & 0x3
    index = (addr >> 4) & 0x3F
    tag = (addr >> 10) & 0x3FFFFF
    return tag, index, word_offset, byte_offset


def line_base_address(addr: int) -> int:
    """Line-aligned base address (matches mem_side_master_fsm's line_base)."""
    return addr & ~0xF & MASK32


class BackingMemory:
    """
    Behavioral model of ahb_mem_model.v.

    Word-addressed, pre-initialized with mem[i] = 0xCCCC_0000 + i,
    exactly matching the RTL memory model's `initial` block, so that
    "cold" read values match the RTL testbenches numerically.
    """

    def __init__(self, num_words: int = 256):
        self.num_words = num_words
        self.mem = [ (0xCCCC_0000 + i) & MASK32 for i in range(num_words) ]

    def read_word(self, byte_addr: int) -> int:
        widx = (byte_addr >> 2) & (self.num_words - 1)
        return self.mem[widx]

    def write_word(self, byte_addr: int, data: int):
        widx = (byte_addr >> 2) & (self.num_words - 1)
        self.mem[widx] = data & MASK32

    def read_line(self, line_base_addr: int):
        """Return list of 4 words starting at a line-aligned address."""
        return [self.read_word(line_base_addr + 4 * i) for i in range(WORDS_PER_LINE)]


@dataclass
class CacheLine:
    valid: bool = False
    tag: int = 0
    words: list = field(default_factory=lambda: [0, 0, 0, 0])


class CacheModel:
    """
    Independent functional model of cache_core + cpu_side_slave_fsm +
    mem_side_master_fsm, collapsed to transaction-level semantics:
    given one CPU request, produce the RDATA the CPU would see, and
    mutate cache/backing-memory state exactly as the documented policy
    dictates.
    """

    def __init__(self, backing_memory: Optional[BackingMemory] = None):
        self.mem = backing_memory if backing_memory is not None else BackingMemory()
        self.lines = [CacheLine() for _ in range(NUM_LINES)]
        # Stats, useful for cross-checking against RTL hazard tests
        self.fill_count = 0
        self.write_through_count = 0

    # -- internal helpers ---------------------------------------------

    def _lookup(self, tag: int, index: int):
        line = self.lines[index]
        hit = line.valid and (line.tag == tag)
        return hit, line

    def _fill_line(self, addr: int):
        """Fetch a full line from backing memory and install it (atomic commit)."""
        tag, index, _, _ = split_address(addr)
        base = line_base_address(addr)
        words = self.mem.read_line(base)
        self.lines[index] = CacheLine(valid=True, tag=tag, words=words)
        self.fill_count += 1

    # -- public transaction API ----------------------------------------

    def do_read(self, addr: int) -> int:
        """
        Perform a CPU read. Mirrors cpu_side_slave_fsm:
          - hit  -> return data same "cycle"
          - miss -> service via mem_side_master_fsm (fill), then hit guaranteed
        Returns the 32-bit read data as the CPU would observe it.
        """
        tag, index, word_off, _ = split_address(addr)
        hit, line = self._lookup(tag, index)

        if not hit:
            self._fill_line(addr)
            hit, line = self._lookup(tag, index)
            assert hit, "post-fill lookup must hit (architectural invariant)"

        return line.words[word_off] & MASK32

    def do_write(self, addr: int, wdata: int) -> None:
        """
        Perform a CPU write. Mirrors cpu_side_slave_fsm + write-allocate
        deviation:
          - hit  -> write-through: update cache line word AND backing memory
          - miss -> write-allocate: fill line first (fetch-then-retry),
                    then perform the write as a guaranteed write-hit
        """
        tag, index, word_off, _ = split_address(addr)
        hit, line = self._lookup(tag, index)

        if not hit:
            # write-allocate: fetch-then-retry (matches STATE_COMPLETE
            # re-issuing the original write request into cache_core after fill)
            self._fill_line(addr)
            hit, line = self._lookup(tag, index)
            assert hit, "post-fill lookup must hit (architectural invariant)"

        # write-hit path: update cache word ...
        line.words[word_off] = wdata & MASK32
        # ... and write-through to backing memory
        self.mem.write_word(addr, wdata & MASK32)
        self.write_through_count += 1

    def run_transaction(self, addr: int, is_write: bool, wdata: int = 0) -> int:
        """
        Single entry point mirroring the RTL testbenches' `ahb_transfer`
        task signature: (addr, write, wdata_in) -> rdata_out.
        For writes, RTL's HRDATA during a write is architecturally
        don't-care (the FSM does not drive meaningful read data on a
        write cycle); we return the pre-write value read-would-have-seen
        is NOT modeled here since it's not checked by the RTL TBs either.
        """
        if is_write:
            self.do_write(addr, wdata)
            return 0  # HRDATA is don't-care on write, same as RTL testbenches assume
        else:
            return self.do_read(addr)

    # -- introspection, useful for the comparison report ----------------

    def peek_mem_word(self, addr: int) -> int:
        return self.mem.read_word(addr)

    def peek_line(self, index: int) -> CacheLine:
        return self.lines[index]
