# ============================================================================
#  run.do  file 
# ============================================================================

# 1. Clean state
quit -sim
.main clear

# 2. Library
vlib work
vmap work work

# 3. Compile
#    Using filelist.f to load all Verilog files
vlog -work work \
    +incdir+./Cache_Core \
    +incdir+./tb \
    -f filelist.f

# 4. Start simulation with full visibility
#    -t 1ps : time resolution
#    +acc   : enable all signal access
vsim -voptargs="+acc" -t 1ps work.tb_cache_controller_top

# 5. Load waveforms
do wave.do

# 6. Run
run -all
