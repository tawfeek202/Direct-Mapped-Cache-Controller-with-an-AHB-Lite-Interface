#
# wave.do -- tb_cache_controller_top waveform setup
# Direct-Mapped Cache Controller (AHB-Lite) -- NTI HireReady / DEY Program
#
# Usage (ModelSim / QuestaSim):
#   vsim work.tb_cache_controller_top
#   do wave.do
#   run -all
#
# This file is organized as ONE divider + signal group PER TEST CASE from
# tb_cache_controller_top.v (T1..T6). Each group exposes exactly the
# internal signals needed to prove that test's claim on the waveform,
# in addition to the standard CPU-side and memory-side AHB interfaces.
#
# Color legend (used consistently across all groups):
#   Yellow  -> CPU-side AHB-Lite SLAVE interface (external, top-level)
#   Cyan    -> Memory-side AHB-Lite MASTER interface (external, top-level)
#   Orange  -> cpu_side_slave_fsm internal state / control
#   Magenta -> mem_side_master_fsm internal state / control
#   Green   -> cache_core internal (tag/valid/data arrays, hit logic)
#   White   -> testbench bookkeeping (checks/errors)
#

onerror {resume}
quietly WaveActivateNextPane {} 0

# Clean slate
delete wave *

# -----------------------------------------------------------------------
# Convenience shorthand for the DUT hierarchy
# -----------------------------------------------------------------------
set TB   sim:/tb_cache_controller_top
set TOP  ${TB}/dut_top
set CPU  ${TOP}/u_cpu_side_slave_fsm
set CORE ${TOP}/u_cache_core
set TAGV ${CORE}/u_tag_valid
set DATA ${CORE}/u_data_line
set MEMF ${TOP}/u_mem_side_master_fsm
set MMOD ${TB}/dut_mem

# =========================================================================
# GLOBAL: Clock / Reset / Testbench bookkeeping (always visible at top)
# =========================================================================
add wave -divider -height 30 "===================== GLOBAL: CLOCK / RESET / TB STATUS ====================="
add wave -color White  -label "HCLK"          ${TB}/HCLK
add wave -color White  -label "HRESETn"       ${TB}/HRESETn
add wave -color White  -label "checks (TB)"   -radix unsigned ${TB}/checks
add wave -color White  -label "errors (TB)"   -radix unsigned ${TB}/errors

# =========================================================================
# TEST 1: Cold read miss at 0x40 -- expect miss, 4-beat INCR fill, correct
#         data delivered on completion.
#         Proves: miss detection, mem-side master burst generation,
#         fill-buffer accumulation, atomic commit, correct HRDATA.
# =========================================================================
add wave -divider -height 35 "############ TEST 1: COLD READ MISS @ 0x40 (expect miss -> fill -> data) ############"

add wave -divider "T1 -- CPU-side AHB-Lite SLAVE port (external interface)"
add wave -color Yellow -label "HADDR"    -radix hex ${TB}/HADDR
add wave -color Yellow -label "HTRANS"   -radix hex ${TB}/HTRANS
add wave -color Yellow -label "HWRITE"              ${TB}/HWRITE
add wave -color Yellow -label "HREADY (stall=0)"    ${TB}/HREADY
add wave -color Yellow -label "HRDATA"   -radix hex ${TB}/HRDATA
add wave -color Yellow -label "HRESP"    -radix hex ${TB}/HRESP

add wave -divider "T1 -- cpu_side_slave_fsm internal (miss detection + stall)"
add wave -color Orange -label "current_state"  -radix ascii ${CPU}/current_state
add wave -color Orange -label "core_req_valid"           ${CPU}/core_req_valid
add wave -color Orange -label "core_hit (from cache_core)" ${CPU}/core_hit
add wave -color Orange -label "miss_req"                 ${CPU}/miss_req
add wave -color Orange -label "miss_addr"     -radix hex  ${CPU}/miss_addr
add wave -color Orange -label "miss_is_write"            ${CPU}/miss_is_write
add wave -color Orange -label "mem_op_done"              ${CPU}/mem_op_done

add wave -divider "T1 -- mem_side_master_fsm internal (4-beat INCR burst engine)"
add wave -color Magenta -label "state"        -radix unsigned ${MEMF}/state
add wave -color Magenta -label "beat_cnt"     -radix unsigned ${MEMF}/beat_cnt
add wave -color Magenta -label "line_base"    -radix hex      ${MEMF}/line_base
add wave -color Magenta -label "addr_index"   -radix unsigned ${MEMF}/addr_index
add wave -color Magenta -label "addr_tag"     -radix hex      ${MEMF}/addr_tag

add wave -divider "T1 -- Memory-side AHB-Lite MASTER port (external, drives ahb_mem_model)"
add wave -color Cyan -label "mHADDR"   -radix hex ${TB}/mHADDR
add wave -color Cyan -label "mHTRANS"  -radix hex ${TB}/mHTRANS
add wave -color Cyan -label "mHBURST"  -radix hex ${TB}/mHBURST
add wave -color Cyan -label "mHWRITE"             ${TB}/mHWRITE
add wave -color Cyan -label "mHRDATA" -radix hex  ${TB}/mHRDATA
add wave -color Cyan -label "mHREADY"             ${TB}/mHREADY

add wave -divider "T1 -- Fill bus into cache_core (proves 4-word accumulate + atomic commit)"
add wave -color Green -label "fill_word_en"                ${MEMF}/fill_word_en
add wave -color Green -label "fill_word_sel"  -radix unsigned ${MEMF}/fill_word_sel
add wave -color Green -label "fill_word_data" -radix hex   ${MEMF}/fill_word_data
add wave -color Green -label "line_buffer (staging)" -radix hex ${DATA}/line_buffer
add wave -color Green -label "fill_commit (atomic write pulse)" ${MEMF}/fill_commit
add wave -color Green -label "fill_index"     -radix unsigned ${MEMF}/fill_index
add wave -color Green -label "fill_tag"       -radix hex   ${MEMF}/fill_tag

add wave -divider "T1 -- cache_core result after fill (line now valid + correct data)"
add wave -color Green -label "stored tag @index1 (0x40>>4)" -radix hex ${TAGV}/tag_array(1)
add wave -color Green -label "valid @index1"                          ${TAGV}/valid_array(1)
add wave -color Green -label "data_array line[1] (128-bit)" -radix hex ${DATA}/data_array(1)

# =========================================================================
# TEST 2: Re-read same address 0x40 -- expect FAST HIT, no stall, no miss
#         traffic at all.
#         Proves: combinational hit path, zero-latency read, HREADY never
#         drops, mem-side FSM stays idle.
# =========================================================================
add wave -divider -height 35 "############ TEST 2: RE-READ 0x40 (expect fast HIT, no stall) ############"

add wave -divider "T2 -- CPU-side AHB-Lite SLAVE port"
add wave -color Yellow -label "HADDR"   -radix hex ${TB}/HADDR
add wave -color Yellow -label "HTRANS"  -radix hex ${TB}/HTRANS
add wave -color Yellow -label "HREADY (must stay 1 -- no stall)" ${TB}/HREADY
add wave -color Yellow -label "HRDATA"  -radix hex ${TB}/HRDATA

add wave -divider "T2 -- Proof of HIT (no miss service triggered)"
add wave -color Orange -label "current_state (must stay IDLE)" -radix ascii ${CPU}/current_state
add wave -color Orange -label "core_hit (must be 1 immediately)" ${CPU}/core_hit
add wave -color Orange -label "miss_req (must stay 0)"          ${CPU}/miss_req
add wave -color Magenta -label "mem FSM state (must stay IDLE=0)" -radix unsigned ${MEMF}/state

# =========================================================================
# TEST 3: Write-hit at 0x40 then read-back -- expect write-through to
#         memory AND cache line updated with new data.
#         Proves: we_gated safety interlock, single-beat write-through
#         burst, cache data array partial-word update, read-back match.
# =========================================================================
add wave -divider -height 35 "############ TEST 3: WRITE-HIT @ 0x40 (0xDEADBEEF) THEN READ-BACK ############"

add wave -divider "T3 -- CPU-side AHB-Lite SLAVE port (write then read)"
add wave -color Yellow -label "HADDR"   -radix hex ${TB}/HADDR
add wave -color Yellow -label "HWRITE"             ${TB}/HWRITE
add wave -color Yellow -label "HWDATA"  -radix hex ${TB}/HWDATA
add wave -color Yellow -label "HREADY (stalls during write-through)" ${TB}/HREADY
add wave -color Yellow -label "HRDATA (read-back result)" -radix hex ${TB}/HRDATA

add wave -divider "T3 -- cpu_side_slave_fsm (write-hit -> STATE_WRITE_WAIT)"
add wave -color Orange -label "current_state"        -radix ascii ${CPU}/current_state
add wave -color Orange -label "core_hit"                        ${CPU}/core_hit
add wave -color Orange -label "core_we (write enable to core)"  ${CPU}/core_we
add wave -color Orange -label "core_wdata"           -radix hex ${CPU}/core_wdata
add wave -color Orange -label "miss_req (asserted for write-through)" ${CPU}/miss_req
add wave -color Orange -label "miss_is_write"                   ${CPU}/miss_is_write
add wave -color Orange -label "miss_wdata"           -radix hex ${CPU}/miss_wdata

add wave -divider "T3 -- cache_core safety interlock (we_gated = core_we AND core_hit)"
add wave -color Green -label "we_gated (internal net)" ${CORE}/we_gated
add wave -color Green -label "core_rdata"  -radix hex  ${CORE}/core_rdata

add wave -divider "T3 -- mem_side_master_fsm (single-beat write-through, not a burst)"
add wave -color Magenta -label "state"      -radix unsigned ${MEMF}/state
add wave -color Magenta -label "wdata_reg"  -radix hex      ${MEMF}/wdata_reg
add wave -color Magenta -label "addr_reg"   -radix hex      ${MEMF}/addr_reg

add wave -divider "T3 -- Memory-side AHB-Lite MASTER port (single write beat, HBURST=SINGLE)"
add wave -color Cyan -label "mHADDR"   -radix hex ${TB}/mHADDR
add wave -color Cyan -label "mHTRANS"  -radix hex ${TB}/mHTRANS
add wave -color Cyan -label "mHWRITE (=1 for this test)" ${TB}/mHWRITE
add wave -color Cyan -label "mHWDATA (=0xDEADBEEF)" -radix hex ${TB}/mHWDATA
add wave -color Cyan -label "mHBURST (=SINGLE, not INCR4)" -radix hex ${TB}/mHBURST

add wave -divider "T3 -- Cache data array updated in place (word1 @ index1)"
add wave -color Green -label "data_array line[1] (128-bit, word1 slice = 0xDEADBEEF)" -radix hex ${DATA}/data_array(1)

# =========================================================================
# TEST 4: Confirm write-through actually reached BACKING MEMORY, not just
#         the cache -- checked by peeking the ahb_mem_model array directly.
#         Proves: write-through policy is real, not just cache-local.
# =========================================================================
add wave -divider -height 35 "############ TEST 4: WRITE-THROUGH REACHED BACKING MEMORY ############"

add wave -divider "T4 -- ahb_mem_model internal state (verification stand-in memory)"
add wave -color Cyan  -label "mHADDR (last write addr)" -radix hex ${TB}/mHADDR
add wave -color Cyan  -label "mHWDATA (last write data)" -radix hex ${TB}/mHWDATA
add wave -color Green -label "pending_valid"                     ${MMOD}/pending_valid
add wave -color Green -label "pending_addr"        -radix hex    ${MMOD}/pending_addr
add wave -color Green -label "pending_write"                     ${MMOD}/pending_write
add wave -color Green -label "pending_wdata (latched, not live)" -radix hex ${MMOD}/pending_wdata
add wave -color Green -label "mem[16] (word @ 0x40>>2, expect 0xDEADBEEF after commit)" -radix hex ${MMOD}/mem(16)

# =========================================================================
# TEST 5: Second independent line @ 0x80 -- proves index independence:
#         a NEW line fill at a different index must not disturb line 0x40,
#         and line 0x40 must still hold its written value.
# =========================================================================
add wave -divider -height 35 "############ TEST 5: SECOND INDEPENDENT LINE @ 0x80 (index independence) ############"

add wave -divider "T5 -- CPU-side AHB-Lite SLAVE port (two different addresses)"
add wave -color Yellow -label "HADDR"  -radix hex ${TB}/HADDR
add wave -color Yellow -label "HRDATA" -radix hex ${TB}/HRDATA

add wave -divider "T5 -- Index decode (0x80 -> index 8, 0x40 -> index 4 -- must not alias)"
add wave -color Orange -label "core_addr_index (from live HADDR)" -radix unsigned ${CPU}/core_addr_index
add wave -color Orange -label "core_addr_tag"                     -radix hex      ${CPU}/core_addr_tag
add wave -color Magenta -label "fill_index (mem-side FSM target line)" -radix unsigned ${MEMF}/fill_index

add wave -divider "T5 -- Independent tag/valid storage: index 8 (0x80) vs index 4 (0x40)"
add wave -color Green -label "tag_array[8] (line 0x80)"   -radix hex ${TAGV}/tag_array(8)
add wave -color Green -label "valid_array[8]"                        ${TAGV}/valid_array(8)
add wave -color Green -label "tag_array[4] (line 0x40, must be unchanged)" -radix hex ${TAGV}/tag_array(4)
add wave -color Green -label "valid_array[4] (must remain 1, untouched)"   ${TAGV}/valid_array(4)

add wave -divider "T5 -- Independent data storage: index 8 vs index 4"
add wave -color Green -label "data_array[8] (new line, 128-bit)" -radix hex ${DATA}/data_array(8)
add wave -color Green -label "data_array[4] (old line, must still hold 0xDEADBEEF at word1)" -radix hex ${DATA}/data_array(4)

# =========================================================================
# TEST 6: Back-to-back transfer immediately after completion -- proves the
#         miss_req level-sensitivity hazard does NOT cause a hang or a
#         spurious extra service cycle, and HREADY returns cleanly to 1
#         in STATE_IDLE with no pending request.
# =========================================================================
add wave -divider -height 35 "############ TEST 6: BACK-TO-BACK TRANSFER (no hang, clean IDLE return) ############"

add wave -divider "T6 -- CPU-side AHB-Lite SLAVE port"
add wave -color Yellow -label "HADDR"  -radix hex ${TB}/HADDR
add wave -color Yellow -label "HTRANS" -radix hex ${TB}/HTRANS
add wave -color Yellow -label "HREADY (proof: returns to 1 cleanly, no extra stall)" ${TB}/HREADY
add wave -color Yellow -label "HRDATA" -radix hex ${TB}/HRDATA

add wave -divider "T6 -- FSM hazard proof (miss_req deasserts before mem FSM re-enters IDLE)"
add wave -color Orange  -label "cpu FSM current_state" -radix ascii     ${CPU}/current_state
add wave -color Orange  -label "miss_req"                              ${CPU}/miss_req
add wave -color Magenta -label "mem FSM state"          -radix unsigned ${MEMF}/state
add wave -color Magenta -label "fill_commit (must pulse exactly once per transfer)" ${MEMF}/fill_commit

add wave -divider "T6 -- New third line result (0xC0 -> index 12)"
add wave -color Green -label "core_addr_index (=12 for 0xC0)" -radix unsigned ${CPU}/core_addr_index
add wave -color Green -label "data_array[12]" -radix hex ${DATA}/data_array(12)

# =========================================================================
# Layout / cosmetics
# =========================================================================
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
configure wave -namecolwidth 320
configure wave -valuecolwidth 140
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 10
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns

# Zoom to fit the whole run once simulation has finished
run -all
wave zoom full
