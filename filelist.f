// ====================================================
// 1. Cache Core (Internal SRAMs and Logic)
// ====================================================
./Cache_Core/data_line_array.v
./Cache_Core/tag_valid_array.v
./Cache_Core/comparator.v
./Cache_Core/cache_core.v

// ====================================================
// 2. Cache Controller (FSMs and Top Level)
// ====================================================
./cpu_side_slave_fsm.v
./mem_side_master_fsm.v
./cache_controller_top.v

// ====================================================
// 3. Testbenches and Memory Models
// ====================================================
./tb/ahb_mem_model.v
./tb/tb_cache_core.v
./tb/tb_cache_controller_top.v
./tb/tb_full_chain.v