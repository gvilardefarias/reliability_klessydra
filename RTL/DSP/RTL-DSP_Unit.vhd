----------------------------------------------------------------------------------------------------------
--  DSP Unit(s) --                                                                                      --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                    --
--                                                                                                      --
--  Date Modified: 02-04-2020                                                                           --
----------------------------------------------------------------------------------------------------------
--  The DSP unit executes on vectors fetched from local-low-latency-wide-bus scratchpad memories.       --
--  The DSP has five functional units, adder/subtractor, multiplier, right arith/logic shifter,         --
--  accumulator, and ReLu each of which supports three integer data types (8-bit, 16-bit and 32-bits)   --
--  The data parallelism of the DSP is defined by the SIMD parameter in the PKG file. Increasing the    --
--  data level parallelism increasess the number of banks per SPM as well, as the number of functional  --
--  units. To increase the instruction level parallelism, the replicated_accl_en parameter must be      --
--  set. Setting it will provide a dedicated hardware accelerator for each hart,                        --
--  Custom CSRs are implemented for the accelerator unit                                                --
----------------------------------------------------------------------------------------------------------

-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages -----------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

-- DSP  pinout --------------------
entity DSP_Unit is
  generic(
    THREAD_POOL_SIZE      : natural;
    accl_en               : natural;
    replicate_accl_en     : natural;
    multithreaded_accl_en : natural;
    SPM_NUM               : natural; 
    Addr_Width            : natural;
    SIMD                  : natural;
    --------------------------------
    ACCL_NUM              : natural;
    FU_NUM                : natural;
    TPS_CEIL              : natural;
    TPS_BUF_CEIL          : natural;
    SPM_ADDR_WID          : natural;
    SIMD_BITS             : natural;
    Data_Width            : natural;
    SIMD_Width            : natural
  );
  port (
  -- Core Signals
    clk_i, rst_ni              : in std_logic;
    -- Processing Pipeline Signals
    rs1_to_sc                  : in  std_logic_vector(SPM_ADDR_WID-1 downto 0);
    rs2_to_sc                  : in  std_logic_vector(SPM_ADDR_WID-1 downto 0);
    rd_to_sc                   : in  std_logic_vector(SPM_ADDR_WID-1 downto 0);
  -- CSR Signals
    MVSIZE                     : in  array_2d(THREAD_POOL_SIZE-1 downto 0)(Addr_Width downto 0);
    MVTYPE                     : in  array_2d(THREAD_POOL_SIZE-1 downto 0)(3 downto 0);
    MPSCLFAC                   : in  array_2d(THREAD_POOL_SIZE-1 downto 0)(4 downto 0);
    dsp_except_data            : out array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
  -- Program Counter Signals
    dsp_taken_branch           : out std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_except_condition       : out std_logic_vector(ACCL_NUM-1 downto 0);
    -- ID_Stage Signals
    decoded_instruction_DSP    : in  std_logic_vector(DSP_UNIT_INSTR_SET_SIZE-1 downto 0);
    harc_EXEC                  : in  natural range THREAD_POOL_SIZE-1 downto 0;
    pc_IE                      : in  std_logic_vector(31 downto 0);
    RS1_Data_IE                : in  std_logic_vector(31 downto 0);
    RS2_Data_IE                : in  std_logic_vector(31 downto 0);
    RD_Data_IE                 : in  std_logic_vector(Addr_Width -1 downto 0);
    dsp_instr_req              : in  std_logic_vector(ACCL_NUM-1 downto 0);
    spm_rs1                    : in  std_logic;
    spm_rs2                    : in  std_logic;
    vec_read_rs1_ID            : in  std_logic;
    vec_read_rs2_ID            : in  std_logic;
    vec_write_rd_ID            : in  std_logic;
    busy_dsp                   : out std_logic_vector(ACCL_NUM-1 downto 0);
  -- Scratchpad Interface Signals
    dsp_data_gnt_i             : in  std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_sci_wr_gnt             : in  std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_sc_data_read           : in  array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(SIMD_Width-1 downto 0);
    dsp_we_word                : out array_2d(ACCL_NUM-1 downto 0)(SIMD-1 downto 0);
    dsp_sc_read_addr           : out array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(Addr_Width-1 downto 0);
    dsp_to_sc                  : out array_3d(ACCL_NUM-1 downto 0)(SPM_NUM-1 downto 0)(1 downto 0);
    dsp_sc_data_write_wire     : out array_2d(ACCL_NUM-1 downto 0)(SIMD_Width-1 downto 0);
    dsp_sc_write_addr          : out array_2d(ACCL_NUM-1 downto 0)(Addr_Width-1 downto 0);
    dsp_sci_we                 : out array_2d(ACCL_NUM-1 downto 0)(SPM_NUM-1 downto 0);
    dsp_sci_req                : out array_2d(ACCL_NUM-1 downto 0)(SPM_NUM-1 downto 0);
    -- tracer signals
    state_DSP                  : out array_2d(ACCL_NUM-1 downto 0)(1 downto 0)

  );
end entity;  ------------------------------------------


architecture DSP of DSP_Unit is

  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;
  subtype accl_range is integer range ACCL_NUM-1 downto 0;
  subtype fu_range   is integer range FU_NUM-1 downto 0;


  signal nextstate_DSP : array_2d(ACCL_NUM-1 downto 0)(1 downto 0);

  -- Virtual Parallelism Signals
  signal cmp_en                          : std_logic_vector(accl_range);  -- enables the use of the shifters
  signal shift_en                        : std_logic_vector(accl_range);  -- enables the use of the shifters
  signal add_en                          : std_logic_vector(accl_range);  -- enables the use of the adders
  signal mul_en                          : std_logic_vector(accl_range);  -- enables the use of the multipliers
  signal accum_en                        : std_logic_vector(accl_range);  -- enables the use of the accumulator
  signal cmp_en_wire                     : std_logic_vector(accl_range);  -- enables the use of the shifters
  signal shift_en_wire                   : std_logic_vector(accl_range);  -- enables the use of the shifters
  signal add_en_wire                     : std_logic_vector(accl_range);  -- enables the use of the adders
  signal mul_en_wire                     : std_logic_vector(accl_range);  -- enables the use of the multipliers
  signal accum_en_wire                   : std_logic_vector(accl_range);  -- enables the use of the accumulatorss
  signal add_en_pending_wire             : std_logic_vector(accl_range);  -- signal to preserve the request to access the adder "multhithreaded mode" only
  signal shift_en_pending_wire           : std_logic_vector(accl_range);  -- signal to preserve the request to access the shifter "multhithreaded mode" only
  signal mul_en_pending_wire             : std_logic_vector(accl_range);  -- signal to preserve the request to access the multiplier "multhithreaded mode" only
  signal accum_en_pending_wire           : std_logic_vector(accl_range);  -- signal to preserve the request to access the accumulator "multhithreaded mode" only
  signal cmp_en_pending_wire             : std_logic_vector(accl_range);  -- signal to preserve the request to access the ReLU "multhithreaded mode" only
  signal add_en_pending                  : std_logic_vector(accl_range);  -- signal to preserve the request to access the adder "multhithreaded mode" only
  signal shift_en_pending                : std_logic_vector(accl_range);  -- signal to preserve the request to access the shifter "multhithreaded mode" only
  signal mul_en_pending                  : std_logic_vector(accl_range);  -- signal to preserve the request to access the multiplier "multhithreaded mode" only
  signal accum_en_pending                : std_logic_vector(accl_range);  -- signal to preserve the request to access the accumulator "multhithreaded mode" only
  signal cmp_en_pending                  : std_logic_vector(accl_range);  -- signal to preserve the request to access the ReLU "multhithreaded mode" only
  signal busy_add                        : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_mul                        : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_shf                        : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_acc                        : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_cmp                        : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_add_wire                   : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_mul_wire                   : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_shf_wire                   : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_acc_wire                   : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal busy_cmp_wire                   : std_logic;  -- busy signal active only when the FU is shared and currently in use 
  signal halt_hart                       : std_logic_vector(accl_range); -- halts the thread when the requested functional unit is in use
  signal fu_req                          : array_2d(ACCL_NUM-1 downto 0)(4 downto 0); -- Each threa has request bits equal to the total number of FUs
  signal fu_gnt                          : array_2d(ACCL_NUM-1 downto 0)(4 downto 0); -- Each threa has grant bits equal to the total number of FUs
  signal fu_gnt_wire                     : array_2d(ACCL_NUM-1 downto 0)(4 downto 0); -- Each threa has grant bits equal to the total number of FUs
  signal fu_gnt_en                       : array_2d(ACCL_NUM-1 downto 0)(4 downto 0); -- Enable the giving of the grant to the thread pointed at by the issue buffer
  signal fu_rd_ptr                       : array_2d(4 downto 0)(TPS_BUF_CEIL-1 downto 0);
  signal fu_wr_ptr                       : array_2d(4 downto 0)(TPS_BUF_CEIL-1 downto 0);
  -- five buffers for each FU times the "TPS-1" and not "TPS" since there is always one thread active, and not needing a buffer. Each buffer hold the thread_ID "TPS_CEIL"
  signal fu_issue_buffer                 : array_3d(4 downto 0)(THREAD_POOL_SIZE-2 downto 0)(TPS_CEIL-1 downto 0);

  -- Functional Unit Ports ---
  --signal dsp_in_sign_bits               : array_2d(ACCL_NUM)(4*SIMD-1 downto 0);               -- vivado unsynthesizable, but more efficient alternative
  signal dsp_in_shifter_operand          : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_in_shifter_operand_lat      : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);            -- 15 bits because i only want to latch the signed bits
  signal dsp_in_shifter_operand_lat_wire : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_int_shifter_operand         : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_out_shifter_results         : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_in_cmp_operands             : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_in_mul_operands             : array_3d(FU_NUM-1 downto 0)(1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_out_mul_results             : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_out_cmp_results             : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_in_accum_operands           : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_out_accum_results           : array_2d(FU_NUM-1 downto 0)(31 downto 0);
  signal dsp_in_adder_operands           : array_3d(FU_NUM-1 downto 0)(1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_in_adder_operands_lat       : array_3d(FU_NUM-1 downto 0)(1 downto 0)(SIMD_Width/2 -1 downto 0); -- data_Width devided by the number of pipeline stages
  signal dsp_out_adder_results           : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);

  signal carry_8_wire                    : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_8_0" signal
  signal carry_16_wire                   : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_16_8" signal
  signal carry_16                        : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_16_8" signal
  signal carry_24_wire                   : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_24_16" signal
  signal dsp_add_8_0                     : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits, contains the results of 8-bit adders
  signal dsp_add_16_8                    : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits  contains the results of 8-bit adders
  signal dsp_add_8_0_wire                : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits, contains the results of 8-bit adders
  signal dsp_add_16_8_wire               : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits  contains the results of 8-bit adders
  signal dsp_add_24_16_wire              : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits  contains the results of 8-bit adders
  signal dsp_add_32_24_wire              : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits, this should be 8 if we choose to discard the overflow of the addition of the upper byte
  signal mul_tmp_a                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
  signal mul_tmp_b                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
  signal mul_tmp_c                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
  signal mul_tmp_d                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
  signal dsp_mul_a                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers
  signal dsp_mul_b                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers
  signal dsp_mul_c                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers
  signal dsp_mul_d                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers

  signal carry_pass                      : array_2d(ACCL_NUM-1 downto 0)(2 downto 0);  -- carry enable signal, depending on it's configuration, we can do KADDV8, KADDV16, KADDV32
  signal FUNCT_SELECT_MASK               : array_2d(ACCL_NUM-1 downto 0)(31 downto 0); -- when the mask is set to "FFFFFFFF" we enable KDOTP32 execution using the 16-bit muls
  signal twos_complement                 : array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
  signal dsp_shift_enabler               : array_2d(ACCL_NUM-1 downto 0)(15 downto 0);
  signal dsp_in_shift_amount             : array_2d(ACCL_NUM-1 downto 0)(4 downto 0);

  signal dsp_sc_data_write_wire_int      : array_2d(ACCL_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_sc_data_write_int           : array_2d(ACCL_NUM-1 downto 0)(SIMD_Width-1 downto 0);

  signal MVTYPE_DSP                      : array_2d(ACCL_NUM-1 downto 0)(1 downto 0);
  signal vec_write_rd_DSP                : std_logic_vector(accl_range);  -- Indicates whether the result being written is a vector or a scalar
  signal vec_read_rs1_DSP                : std_logic_vector(accl_range);  -- Indicates whether the operand being read is a vector or a scalar
  signal vec_read_rs2_DSP                : std_logic_vector(accl_range);  -- Indicates whether the operand being read is a vector or a scalar
  signal dotp                            : std_logic_vector(accl_range);  -- indicator used in the pipeline handler to switch functional units
  signal dotpps                          : std_logic_vector(accl_range);  -- indicator used in the pipeline handler to switch functional units
  signal slt                             : std_logic_vector(accl_range);  -- indicator used in the pipeline handler to switch functional units
  signal wb_ready                        : std_logic_vector(accl_range);
  signal halt_dsp                        : std_logic_vector(accl_range);
  signal halt_dsp_lat                    : std_logic_vector(accl_range);
  signal recover_state                   : std_logic_vector(accl_range);
  signal recover_state_wires             : std_logic_vector(accl_range);
  signal dsp_data_gnt_i_lat              : std_logic_vector(accl_range);
  signal shifter_stage_1_en              : std_logic_vector(accl_range);
  signal shifter_stage_2_en              : std_logic_vector(accl_range);
  signal shifter_stage_3_en              : std_logic_vector(accl_range);
  signal adder_stage_1_en                : std_logic_vector(accl_range);
  signal adder_stage_2_en                : std_logic_vector(accl_range);
  signal adder_stage_3_en                : std_logic_vector(accl_range);
  signal mul_stage_1_en                  : std_logic_vector(accl_range);
  signal mul_stage_2_en                  : std_logic_vector(accl_range);
  signal mul_stage_3_en                  : std_logic_vector(accl_range);
  signal cmp_stage_1_en                  : std_logic_vector(accl_range);
  signal cmp_stage_2_en                  : std_logic_vector(accl_range);
  signal accum_stage_1_en                : std_logic_vector(accl_range);
  signal accum_stage_2_en                : std_logic_vector(accl_range);
  signal accum_stage_3_en                : std_logic_vector(accl_range);
  signal dsp_except_data_wire            : array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
  signal MSB_stage_1                     : array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(4*SIMD-1 downto 0);
  signal MSB_stage_2                     : array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(4*SIMD-1 downto 0);

  signal decoded_instruction_DSP_lat     : array_2d(ACCL_NUM-1 downto 0)(DSP_UNIT_INSTR_SET_SIZE -1 downto 0);
  signal overflow_rs1_sc                 : array_2d(ACCL_NUM-1 downto 0)(Addr_Width downto 0);
  signal overflow_rs2_sc                 : array_2d(ACCL_NUM-1 downto 0)(Addr_Width downto 0);
  signal overflow_rd_sc                  : array_2d(ACCL_NUM-1 downto 0)(Addr_Width downto 0);
  signal dsp_rs1_to_sc                   : array_2d(ACCL_NUM-1 downto 0)(SPM_ADDR_WID-1 downto 0);
  signal dsp_rs2_to_sc                   : array_2d(ACCL_NUM-1 downto 0)(SPM_ADDR_WID-1 downto 0);
  signal dsp_rd_to_sc                    : array_2d(ACCL_NUM-1 downto 0)(SPM_ADDR_WID-1 downto 0);
  signal dsp_sc_data_read_mask           : array_2d(ACCL_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal RS1_Data_IE_lat                 : array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
  signal RS2_Data_IE_lat                 : array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
  signal RD_Data_IE_lat                  : array_2d(ACCL_NUM-1 downto 0)(Addr_Width -1 downto 0);
  signal MVSIZE_READ                     : array_2d(ACCL_NUM-1 downto 0)(Addr_Width downto 0);  -- Bytes remaining to read
  signal MVSIZE_READ_MASK                : array_2d(ACCL_NUM-1 downto 0)(Addr_Width downto 0);  -- Bytes remaining to read
  signal MVSIZE_WRITE                    : array_2d(ACCL_NUM-1 downto 0)(Addr_Width downto 0);  -- Bytes remaining to write
  signal MPSCLFAC_DSP                    : array_2d(ACCL_NUM-1 downto 0)(4 downto 0);
  signal busy_dsp_internal               : std_logic_vector(accl_range);
  signal busy_DSP_internal_lat           : std_logic_vector(accl_range);
  signal rf_rs2                          : std_logic_vector(accl_range);
  signal relu_instr                      : std_logic_vector(accl_range);
  signal SIMD_RD_BYTES_wire              : array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
  signal SIMD_RD_BYTES                   : array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
--  signal SIMD_RD_BYTES_wire              : array_2d_int(accl_range);
--  signal SIMD_RD_BYTES                   : array_2d_int(accl_range);

  component SHIFTER is
  generic(
    multithreaded_accl_en : natural;
    SIMD                  : natural;
    --------------------------------
    ACCL_NUM              : natural;
    FU_NUM                : natural;
    SIMD_Width            : natural
  );
  port(
    -- Core Signals
    clk_i, rst_ni                   : in std_logic;
    -- inputs from DSP_pipeline_controller
    shifter_stage_1_en              : in std_logic_vector(accl_range);
    shifter_stage_2_en              : in std_logic_vector(accl_range);
    halt_dsp_lat                    : in std_logic_vector(accl_range);
    -- inputs from DSP_Exec_Unit
    MVTYPE_DSP                      : in array_2d(ACCL_NUM)(1 downto 0);
    decoded_instruction_DSP_lat     : in array_2d(ACCL_NUM)(DSP_UNIT_INSTR_SET_SIZE -1 downto 0);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(accl_range);
    -- inputs from DSP_FU_Handler
    shift_en                        : in std_logic_vector(accl_range);  -- enables the use of the shifters
    -- inputs from DSP_Mapping
    dsp_in_shifter_operand          : in array_2d(FU_NUM)(SIMD_Width-1 downto 0);
    dsp_in_shift_amount             : in array_2d(ACCL_NUM)(4 downto 0);

    --outputs for DSP_Mapping
    dsp_out_shifter_results         : out array_2d(FU_NUM)(SIMD_Width-1 downto 0)
  );
  end component SHIFTER;

  component COMPARATOR is
  generic(
    SIMD                  : natural;
    multithreaded_accl_en : natural;
    --------------------------------
    ACCL_NUM              : natural;
    FU_NUM                : natural;
    SIMD_Width            : natural
  );
  port(
    -- Core Signals
    clk_i, rst_ni                   : in std_logic;
    -- inputs from DSP_Exec_Unit
    MVTYPE_DSP                      : in array_2d(ACCL_NUM)(1 downto 0);
    relu_instr                      : in std_logic_vector(accl_range);
    -- inputs from DSP_pipeline_controller
    halt_dsp_lat                    : in std_logic_vector(accl_range);
    cmp_stage_1_en                  : in std_logic_vector(accl_range);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(accl_range);
    -- inputs from DSP_FU_Handler
    cmp_en                          : in std_logic_vector(accl_range);  -- enables the use of the shifters
    -- inputs from DSP_Mapping
    dsp_in_cmp_operands             : in array_2d(FU_NUM)(SIMD_Width-1 downto 0);
    -- inputs from adders
    MSB_stage_2                     : in array_3d(ACCL_NUM)(1 downto 0)(4*SIMD-1 downto 0);
  
    -- outputs for DSP_Mapping
    dsp_out_cmp_results             : out array_2d(FU_NUM)(SIMD_Width-1 downto 0)
  );
end component COMPARATOR;

  component ADDER is
  generic (
    multithreaded_accl_en : natural;
    SIMD                  : natural;  
    --------------------------------
    ACCL_NUM              : natural;
    FU_NUM                : natural;
    SIMD_Width            : natural;
    Data_Width            : natural
  );
  port(
    -- Core Signals
    clk_i, rst_ni                 : in std_logic;
    -- inputs from DSP_pipeline_controller
    halt_dsp_lat                    : in std_logic_vector(ACCL_NUM-1 downto 0);
    adder_stage_1_en                : in std_logic_vector(ACCL_NUM-1 downto 0); -- enables the use of the adders in stage 1
    adder_stage_2_en                : in std_logic_vector(ACCL_NUM-1 downto 0); -- enables the use of the adders in stage 2
    -- inputs from DSP_Exec_Unit
    carry_pass                      : in array_2d(ACCL_NUM-1 downto 0)(2 downto 0);  -- carry enable signal, depending on it's configuration, we can do KADDV8, KADDV16, KADDV32
    twos_complement                 : in array_2d(ACCL_NUM-1 downto 0)(31 downto 0);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(ACCL_NUM-1 downto 0); -- used to recover the state of the DSP, in case of an exception
    -- inputs from DSP_FU_Handler
    add_en                          : in std_logic_vector(ACCL_NUM-1 downto 0);  -- enables the use of the adders
    -- inputs from DSP_Mapping
    MSB_stage_1                     : in array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(4*SIMD-1 downto 0);
    dsp_in_adder_operands           : in array_3d(FU_NUM-1 downto 0)(1 downto 0)(SIMD_Width-1 downto 0);
   
    -- outputs for DSP_Mapping
    dsp_out_adder_results           : out array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
    -- outputs for comparator
    MSB_stage_2                     : out array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(4*SIMD-1 downto 0)
    );
  end component ADDER;

  component MULTIPLIER
  generic(
    SIMD                  : natural;
    multithreaded_accl_en : natural;
    --------------------------------
    ACCL_NUM              : natural;
    FU_NUM                : natural;
    SIMD_Width            : natural;
    Data_Width            : natural
  );
  port(
      clk_i                             : in  std_logic;
      rst_ni                            : in  std_logic;
      FUNCT_SELECT_MASK                 : in array_2d(ACCL_NUM-1 downto 0)(31 downto 0); -- when the mask is set to "FFFFFFFF" we enable KDOTP32 execution using the 16-bit muls
      MVTYPE_DSP                        : in  array_2d(ACCL_NUM-1 downto 0)(1 downto 0);
      recover_state_wires               : in  std_logic_vector(ACCL_NUM-1 downto 0);
      halt_dsp_lat                      : in  std_logic_vector(ACCL_NUM-1 downto 0);
      mul_stage_1_en                    : in std_logic_vector(ACCL_NUM - 1 downto 0);
      mul_stage_2_en                    : in std_logic_vector(ACCL_NUM - 1 downto 0);
      mul_en                            : in std_logic_vector(ACCL_NUM - 1 downto 0);  -- enables the use of the multipliers
      dsp_in_mul_operands               : in array_3d(FU_NUM-1 downto 0)(1 downto 0)(SIMD_Width-1 downto 0);
      dsp_out_mul_results               : out array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0)
  );
  end component MULTIPLIER;

  component ACCUMULATOR
    generic(
      multithreaded_accl_en             : natural;
      SIMD                              : natural;
      ---------------------------------------------------------
      ACCL_NUM                          : natural;
      FU_NUM                            : natural;
      Data_Width                        : natural;
      SIMD_Width                        : natural
    );
  port(
      clk_i                             : in  std_logic;
      rst_ni                            : in  std_logic;
      MVTYPE_DSP                        : in  array_2d(ACCL_NUM)(1 downto 0);
      accum_stage_1_en                  : in  std_logic_vector(accl_range);
      accum_stage_2_en                  : in  std_logic_vector(accl_range);
      recover_state_wires               : in  std_logic_vector(accl_range);
      halt_dsp_lat                      : in  std_logic_vector(accl_range);
      state_DSP                         : in  array_2d(ACCL_NUM)(1 downto 0);
      decoded_instruction_DSP_lat       : in  array_2d(ACCL_NUM)(DSP_UNIT_INSTR_SET_SIZE -1 downto 0);
      dsp_in_accum_operands             : in  array_2d(FU_NUM)(SIMD_Width-1 downto 0);
      dsp_out_accum_results             : out array_2d(FU_NUM)(31 downto 0)
  );
  end component;

--------------------------------------------------------------------------------------------------
-------------------------------- DSP BEGIN -------------------------------------------------------
begin


  busy_dsp <= busy_dsp_internal;

  DSP_replicated : for h in accl_range generate


  ------------ Sequential Stage of DSP Unit -------------------------------------------------------------------------
  DSP_Exec_Unit : process(clk_i, rst_ni)  -- single cycle unit, fully synchronous 
  begin
    if rst_ni = '0' then
      relu_instr(h) <= '0';
      rf_rs2(h)     <= '0';
      dotpps(h)     <= '0';
      dotp(h)       <= '0';
      slt(h)        <= '0';
      recover_state(h) <= '0';
    elsif rising_edge(clk_i) then
      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then  

        case state_DSP(h) is

          when dsp_init =>

            -------------------------------------------------------------
            --  ██╗███╗   ██╗██╗████████╗    ██████╗ ███████╗██████╗   --
            --  ██║████╗  ██║██║╚══██╔══╝    ██╔══██╗██╔════╝██╔══██╗  --
            --  ██║██╔██╗ ██║██║   ██║       ██║  ██║███████╗██████╔╝  --
            --  ██║██║╚██╗██║██║   ██║       ██║  ██║╚════██║██╔═══╝   --
            --  ██║██║ ╚████║██║   ██║       ██████╔╝███████║██║       --
            --  ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝       ╚═════╝ ╚══════╝╚═╝       -- 
            -------------------------------------------------------------

            FUNCT_SELECT_MASK(h) <= (others => '0');
            twos_complement(h)   <= (others => '0');
            relu_instr(h) <= '0';
            rf_rs2(h)     <= '0';
            dotpps(h)     <= '0';
            dotp(h)       <= '0';
            slt(h)        <= '0';
            -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP(KADDV_bit_position)    = '1'  or 
                decoded_instruction_DSP(KSVADDSC_bit_position) = '1') and
                MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              carry_pass(h) <= "111";
                -- pass all carry_outs
            elsif decoded_instruction_DSP(KSVADDRF_bit_position) = '1' and 
                   MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              carry_pass(h) <= "111"; 
               -- pass all carry_outs
              rf_rs2(h) <= '1';
            elsif (decoded_instruction_DSP(KADDV_bit_position)    = '1'  or
                   decoded_instruction_DSP(KSVADDSC_bit_position) = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "01" then
              carry_pass(h) <= "101"; 
               -- pass carrries 9, and 25
            elsif decoded_instruction_DSP(KSVADDRF_bit_position) = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "01" then
              carry_pass(h) <= "101"; 
               -- pass carrries 9, and 25
              rf_rs2(h) <= '1';
            elsif (decoded_instruction_DSP(KADDV_bit_position)     = '1'  or
                   decoded_instruction_DSP(KSVADDSC_bit_position)  = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "00" then
              carry_pass(h) <= "000"; 
               -- don't pass carry_outs and keep addition 8-bit
            elsif decoded_instruction_DSP(KSVADDRF_bit_position)  = '1' and 
                  MVTYPE(harc_EXEC)(3 downto 2) = "00" then
              carry_pass(h) <= "000"; 
               -- don't pass carry_outs and keep addition 8-bit
              rf_rs2(h) <= '1';
            elsif (decoded_instruction_DSP(KSUBV_bit_position)  = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              carry_pass(h) <= "111";
                -- pass all carry_outs
              twos_complement(h) <= "00010001000100010001000100010001";
            elsif (decoded_instruction_DSP(KSUBV_bit_position)  = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "01" then
              carry_pass(h) <= "101"; 
               -- pass carrries 9, and 25
              twos_complement(h) <= "01010101010101010101010101010101";
            elsif (decoded_instruction_DSP(KSUBV_bit_position)  = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "00" then
              carry_pass(h) <= "000";
                -- don't pass carry_outs and keep addition 8-bit
              twos_complement(h) <= "11111111111111111111111111111111";
            elsif (decoded_instruction_DSP(KVSLT_bit_position)  = '1'  or
                   decoded_instruction_DSP(KSVSLT_bit_position) = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              carry_pass(h) <= "111";  -- pass all carry_outs
              twos_complement(h) <= "00010001000100010001000100010001";
              slt(h) <= '1';
            elsif (decoded_instruction_DSP(KVSLT_bit_position)  = '1'  or
                   decoded_instruction_DSP(KSVSLT_bit_position) = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "01" then
              carry_pass(h) <= "101"; 
               -- pass carrries 9, and 25
              twos_complement(h) <= "01010101010101010101010101010101";
              slt(h) <= '1';
            elsif (decoded_instruction_DSP(KVSLT_bit_position)  = '1'  or
                   decoded_instruction_DSP(KSVSLT_bit_position) = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "00" then
              carry_pass(h) <= "000";  -- don't pass carry_outs and keep addition 8-bit
              twos_complement(h) <= "11111111111111111111111111111111";
              slt(h) <= '1';
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              -- KDOTP32 does not use the adders of KADDV instructions but rather adds the mul_acc results using it's own adders
              FUNCT_SELECT_MASK(h) <= (others => '1'); 
               -- This enables 32-bit multiplication with the 16-bit multipliers
              dotp(h) <= '1';
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' and 
                  MVTYPE(harc_EXEC)(3 downto 2) = "01" then
              dotp(h) <= '1';
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "00" then
              dotp(h) <= '1';
            elsif decoded_instruction_DSP(KDOTPPS_bit_position) = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              FUNCT_SELECT_MASK(h) <= (others => '1'); 
               -- This enables 32-bit multiplication with the 16-bit multipliers
              dotpps(h) <= '1';
            elsif decoded_instruction_DSP(KDOTPPS_bit_position) = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "01" then
              dotpps(h) <= '1';
            elsif decoded_instruction_DSP(KDOTPPS_bit_position)  = '1' and 
                  MVTYPE(harc_EXEC)(3 downto 2) = "00" then
              dotpps(h) <= '1';
            elsif decoded_instruction_DSP(KSVMULRF_bit_position) = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              FUNCT_SELECT_MASK(h) <= (others => '1');
              rf_rs2(h) <= '1';
            elsif decoded_instruction_DSP(KSVMULRF_bit_position) = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "01" then
              rf_rs2(h) <= '1';
            elsif decoded_instruction_DSP(KSVMULRF_bit_position)  = '1' and
                  MVTYPE(harc_EXEC)(3 downto 2) = "00" then
              rf_rs2(h)  <= '1';
            elsif (decoded_instruction_DSP(KVMUL_bit_position)    = '1'  or
                   decoded_instruction_DSP(KSVMULSC_bit_position) = '1') and
                   MVTYPE(harc_EXEC)(3 downto 2) = "10" then
              FUNCT_SELECT_MASK(h) <= (others => '1');
            elsif decoded_instruction_DSP(KRELU_bit_position) = '1' then
              relu_instr(h) <= '1';
            end if;

           -- We backup data from decode stage since they will get updated

            MVSIZE_READ_MASK(h) <= MVSIZE(harc_EXEC);
            MVSIZE_WRITE(h) <= MVSIZE(harc_EXEC);
            MPSCLFAC_DSP(h) <= MPSCLFAC(harc_EXEC);
            MVTYPE_DSP(h) <= MVTYPE(harc_EXEC)(3 downto 2);
            decoded_instruction_DSP_lat(h)  <= decoded_instruction_DSP;
            vec_write_rd_DSP(h) <= vec_write_rd_ID;
            vec_read_rs1_DSP(h) <= vec_read_rs1_ID;
            vec_read_rs2_DSP(h) <= vec_read_rs2_ID;
            dsp_rs1_to_sc(h) <= rs1_to_sc;
            dsp_rs2_to_sc(h) <= rs2_to_sc;
            dsp_rd_to_sc(h)  <= rd_to_sc;
            RD_Data_IE_lat(h) <= RD_Data_IE;
            -- Increment the read addresses
            if dsp_data_gnt_i(h) = '1' then
              if vec_read_rs1_ID = '1' then
                RS1_Data_IE_lat(h) <= std_logic_vector(resize(unsigned(RS1_Data_IE) + unsigned(SIMD_RD_BYTES_wire(h)), RS1_Data_IE_lat(h)'length)); 
                -- source 1 address increment
              else
                RS1_Data_IE_lat(h) <= RS1_Data_IE;
              end if;
              if vec_read_rs2_ID = '1' then
                RS2_Data_IE_lat(h) <= std_logic_vector(resize(unsigned(RS2_Data_IE) + unsigned(SIMD_RD_BYTES_wire(h)), RS2_Data_IE_lat(h)'length)); 
              -- source 2 address increment
              else
                RS2_Data_IE_lat(h) <= RS2_Data_IE;
              end if;
              -- Decrement the vector elements that have already been operated on
              if unsigned(MVSIZE(harc_EXEC)) >= unsigned(SIMD_RD_BYTES_wire(h)) then
                MVSIZE_READ(h) <= std_logic_vector(resize(unsigned(MVSIZE(harc_EXEC)) - unsigned(SIMD_RD_BYTES_wire(h)), MVSIZE_READ(h)'length)); 
               -- decrement by SIMD_BYTE Execution Capability
              else
                MVSIZE_READ(h) <= (others => '0');                                                     -- decrement the remaining bytes
              end if;
            else
              RS1_Data_IE_lat(h) <= RS1_Data_IE;
              RS2_Data_IE_lat(h) <= RS2_Data_IE;
              MVSIZE_READ(h) <= MVSIZE(harc_EXEC);
            end if;
            -------------------------------------------------------------------------------

          when dsp_exec =>
            recover_state(h) <= recover_state_wires(h);
            if halt_dsp(h) = '1' and halt_dsp_lat(h) = '0' then
              dsp_sc_data_write_int(h) <= dsp_sc_data_write_wire_int(h);
            end if;


            --------------------------------------------------------------------------
            --  ██╗  ██╗██╗    ██╗      ██╗      ██████╗  ██████╗ ██████╗ ███████╗  --
            --  ██║  ██║██║    ██║      ██║     ██╔═══██╗██╔═══██╗██╔══██╗██╔════╝  --
            --  ███████║██║ █╗ ██║█████╗██║     ██║   ██║██║   ██║██████╔╝███████╗  --
            --  ██╔══██║██║███╗██║╚════╝██║     ██║   ██║██║   ██║██╔═══╝ ╚════██║  --
            --  ██║  ██║╚███╔███╔╝      ███████╗╚██████╔╝╚██████╔╝██║     ███████║  --
            --  ╚═╝  ╚═╝ ╚══╝╚══╝       ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝     ╚══════╝  --            
            --------------------------------------------------------------------------

            if halt_dsp(h) = '0' then
              -- Increment the write address when we have a result as a vector
              if vec_write_rd_DSP(h) = '1' and wb_ready(h) = '1' then
                RD_Data_IE_lat(h)  <= std_logic_vector(resize(unsigned(RD_Data_IE_lat(h)) + unsigned(SIMD_RD_BYTES_wire(h)), RD_Data_IE_lat(h)'length)); -- destination address increment
              end if;
              if wb_ready(h) = '1' then
                if to_integer(unsigned(MVSIZE_WRITE(h))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(h))) then
                  MVSIZE_WRITE(h) <= std_logic_vector(resize(unsigned(MVSIZE_WRITE(h)) - unsigned(SIMD_RD_BYTES_wire(h)), MVSIZE_WRITE(h)'length));
                else
                  MVSIZE_WRITE(h) <= (others => '0');                                                -- decrement the remaining bytes
                end if;
              end if;
              -- Increment the read addresses
              if to_integer(unsigned(MVSIZE_READ(h))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(h))) and dsp_data_gnt_i(h) = '1' then -- Increment the addresses untill all the vector elements are operated fetched
                if vec_read_rs1_DSP(h) = '1' then
                  RS1_Data_IE_lat(h) <= std_logic_vector(resize(unsigned(RS1_Data_IE_lat(h)) + unsigned(SIMD_RD_BYTES_wire(h)), RS1_Data_IE_lat(h)'length));
                end if;
                if vec_read_rs2_DSP(h) = '1' then
                  RS2_Data_IE_lat(h) <= std_logic_vector(resize(unsigned(RS2_Data_IE_lat(h)) + unsigned(SIMD_RD_BYTES_wire(h)), RS2_Data_IE_lat(h)'length));
                end if;
              end if;
              -- Decrement the vector elements that have already been operated on
              if dsp_data_gnt_i(h) = '1' then
                if to_integer(unsigned(MVSIZE_READ(h))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(h))) then
                  MVSIZE_READ(h) <= std_logic_vector(resize(unsigned(MVSIZE_READ(h)) - unsigned(SIMD_RD_BYTES_wire(h)), MVSIZE_READ(h)'length));
                else
                  MVSIZE_READ(h) <= (others => '0');                                               -- decrement the remaining bytes
                end if;
              end if;
              dsp_sc_data_read_mask(h) <= (others => '0');
              if dsp_data_gnt_i_lat(h) = '1' then
                if to_integer(unsigned(MVSIZE_READ_MASK(h))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(h))) then
                  dsp_sc_data_read_mask(h) <= (others => '1');
                  MVSIZE_READ_MASK(h) <= std_logic_vector(resize(unsigned(MVSIZE_READ_MASK(h)) - unsigned(SIMD_RD_BYTES_wire(h)), MVSIZE_READ_MASK(h)'length)); -- decrement by SIMD_BYTE Execution Capability 
                else
                  MVSIZE_READ_MASK(h) <= (others => '0');
                  dsp_sc_data_read_mask(h)(to_integer(unsigned(MVSIZE_READ_MASK(h)))*8 - 1 downto 0) <= (others => '1');
                end if;
              end if;
            end if;

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

  ------------ Combinational Stage of DSP Unit ----------------------------------------------------------------------
  DSP_Excpt_Cntrl_Unit_comb : process(all)
  
  variable busy_DSP_internal_wires : std_logic;
  variable dsp_except_condition_wires : std_logic_vector(harc_range);
  variable dsp_taken_branch_wires : std_logic_vector(harc_range);  
      
  begin

    busy_DSP_internal_wires        := '0';
    dsp_except_condition_wires(h)  := '0';
    dsp_taken_branch_wires(h)      := '0';
    wb_ready(h)                    <= '0';
    halt_dsp(h)                    <= '0';
    nextstate_DSP(h)               <= dsp_init;
    recover_state_wires(h)         <= recover_state(h);
    dsp_except_data_wire(h)        <= dsp_except_data(h);
    overflow_rs1_sc(h)             <= (others => '0');
    overflow_rs2_sc(h)             <= (others => '0');
    overflow_rd_sc(h)              <= (others => '0');
    dsp_we_word(h)                 <= (others => '0');
    dsp_sci_req(h)                 <= (others => '0');
    dsp_sci_we(h)                  <= (others => '0');
    dsp_sc_write_addr(h)           <= (others => '0');
    dsp_sc_read_addr(h)            <= (others => (others => '0'));
    dsp_to_sc(h)                   <= (others => (others => '0'));

    if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
      case state_DSP(h) is

        when dsp_init =>

          ---------------------------------------------------------------------------------------------------------------------
          --  ███████╗██╗  ██╗ ██████╗██████╗ ████████╗    ██╗  ██╗ █████╗ ███╗   ██╗██████╗ ██╗     ██╗███╗   ██╗ ██████╗   --
          --  ██╔════╝╚██╗██╔╝██╔════╝██╔══██╗╚══██╔══╝    ██║  ██║██╔══██╗████╗  ██║██╔══██╗██║     ██║████╗  ██║██╔════╝   --
          --  █████╗   ╚███╔╝ ██║     ██████╔╝   ██║       ███████║███████║██╔██╗ ██║██║  ██║██║     ██║██╔██╗ ██║██║  ███╗  --
          --  ██╔══╝   ██╔██╗ ██║     ██╔═══╝    ██║       ██╔══██║██╔══██║██║╚██╗██║██║  ██║██║     ██║██║╚██╗██║██║   ██║  -- 
          --  ███████╗██╔╝ ██╗╚██████╗██║        ██║       ██║  ██║██║  ██║██║ ╚████║██████╔╝███████╗██║██║ ╚████║╚██████╔╝  --
          --  ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝        ╚═╝       ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝   --
          ---------------------------------------------------------------------------------------------------------------------

          overflow_rs1_sc(h) <= std_logic_vector('0' & unsigned(RS1_Data_IE(Addr_Width -1 downto 0)) + unsigned(MVSIZE(harc_EXEC)) -1);
          overflow_rs2_sc(h) <= std_logic_vector('0' & unsigned(RS2_Data_IE(Addr_Width -1 downto 0)) + unsigned(MVSIZE(harc_EXEC)) -1);
          overflow_rd_sc(h)  <= std_logic_vector('0' & unsigned(RD_Data_IE(Addr_Width  -1 downto 0)) + unsigned(MVSIZE(harc_EXEC)) -1);
          if MVSIZE(harc_EXEC) = (0 to Addr_Width => '0') then
            null;
          elsif MVSIZE(harc_EXEC)(1 downto 0) /= "00" and MVTYPE(harc_EXEC)(3 downto 2) = "10" then  -- Set exception if the number of bytes are not divisible by four
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(h) <= ILLEGAL_VECTOR_SIZE_EXCEPT_CODE;
          elsif MVSIZE(harc_EXEC)(0) /= '0' and MVTYPE(harc_EXEC)(3 downto 2) = "01" then            -- Set exception if the number of bytes are not divisible by two
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';
            dsp_except_data_wire(h) <= ILLEGAL_VECTOR_SIZE_EXCEPT_CODE;
          elsif (rs1_to_sc  = "100" and vec_read_rs1_ID = '1') or
            (rs2_to_sc  = "100" and vec_read_rs2_ID = '1') or
             rd_to_sc   = "100" then     -- Set exception for non scratchpad access
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(h) <= ILLEGAL_ADDRESS_EXCEPT_CODE;
          elsif rs1_to_sc = rs2_to_sc and vec_read_rs1_ID = '1' and vec_read_rs2_ID = '1' then               -- Set exception for same read access
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(h) <= READ_SAME_SCARTCHPAD_EXCEPT_CODE;    
          elsif (overflow_rs1_sc(h)(Addr_Width) = '1' and vec_read_rs1_ID = '1') or (overflow_rs2_sc(h)(Addr_Width) = '1' and  vec_read_rs2_ID = '1') then -- Set exception if reading overflows the scratchpad's address
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(h) <= SCRATCHPAD_OVERFLOW_EXCEPT_CODE;
          elsif overflow_rd_sc(h)(Addr_Width) = '1'  and vec_write_rd_ID = '1' then           -- Set exception if reading overflows the scratchpad's address, scalar writes are excluded
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(h) <= SCRATCHPAD_OVERFLOW_EXCEPT_CODE;
          else
            if halt_hart(h) = '0' then
              nextstate_DSP(h) <= dsp_exec;
            else
              nextstate_DSP(h) <= dsp_halt_hart;
            end if;
            busy_DSP_internal_wires := '1';
          end if;

          if rs1_to_sc /= "100" and spm_rs1 = '1' and halt_hart(h) = '0' then
            dsp_sci_req(h)(to_integer(unsigned(rs1_to_sc))) <= '1';
            dsp_to_sc(h)(to_integer(unsigned(rs1_to_sc)))(0) <= '1';
            dsp_sc_read_addr(h)(0) <= RS1_Data_IE(Addr_Width-1 downto 0);
          end if;
          if rs2_to_sc /= "100" and spm_rs2 = '1' and rs1_to_Sc /= rs2_to_sc and halt_hart(h) = '0' then   -- Do not send a read request if the second operand accesses the same spm as the first, 
            dsp_sci_req(h)(to_integer(unsigned(rs2_to_sc))) <= '1';
            dsp_to_sc(h)(to_integer(unsigned(rs2_to_sc)))(1) <= '1';
            dsp_sc_read_addr(h)(1) <= RS2_Data_IE(Addr_Width-1 downto 0);
          end if;
        
         when dsp_halt_hart =>

           if halt_hart(h) = '0' then
             nextstate_DSP(h) <= dsp_exec;
           else
             nextstate_DSP(h) <= dsp_halt_hart;
           end if;
           busy_DSP_internal_wires := '1';

         when dsp_exec =>

           -----------------------------------------------------------------------------------------------------------------------
           --   ██████╗███╗   ██╗████████╗██████╗ ██╗         ██╗  ██╗ █████╗ ███╗   ██╗██████╗ ██╗     ██╗███╗   ██╗ ██████╗   --
           --  ██╔════╝████╗  ██║╚══██╔══╝██╔══██╗██║         ██║  ██║██╔══██╗████╗  ██║██╔══██╗██║     ██║████╗  ██║██╔════╝   --
           --  ██║     ██╔██╗ ██║   ██║   ██████╔╝██║         ███████║███████║██╔██╗ ██║██║  ██║██║     ██║██╔██╗ ██║██║  ███╗  --
           --  ██║     ██║╚██╗██║   ██║   ██╔══██╗██║         ██╔══██║██╔══██║██║╚██╗██║██║  ██║██║     ██║██║╚██╗██║██║   ██║  --
           --  ╚██████╗██║ ╚████║   ██║   ██║  ██║███████╗    ██║  ██║██║  ██║██║ ╚████║██████╔╝███████╗██║██║ ╚████║╚██████╔╝  --
           --   ╚═════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝   --
           -----------------------------------------------------------------------------------------------------------------------

           ------ SMP BANK ENABLER --------------------------------------------------------------------------------------------------
           -- the following enables the appropriate banks to write the SIMD output, depending whether the result is a vector or a  --
           -- scalar, and adjusts the enabler appropriately based on the SIMD size. If the bytes to write are greater than SIMD*4  --
           -- then all banks are enabaled, else we perform the selective bank enabling as shown below under the 'elsif' clause     --
           --------------------------------------------------------------------------------------------------------------------------

           if (dsp_sci_wr_gnt(h) = '0' and wb_ready(h) = '1') then
             halt_dsp(h) <= '1';
             recover_state_wires(h) <= '1';
           elsif unsigned(MVSIZE_WRITE(h)) <= unsigned(SIMD_RD_BYTES(h)) then
             recover_state_wires(h) <= '0';
           end if;

           if vec_write_rd_DSP(h) = '1' and  dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) = '1' then
             if unsigned(MVSIZE_WRITE(h)) >= (SIMD)*4+1 then  -- 
               dsp_we_word(h) <= (others => '1');
             elsif  unsigned(MVSIZE_WRITE(h)) >= 1 then
               for i in 0 to SIMD-1 loop
                 if i <= to_integer(unsigned(MVSIZE_WRITE(h))-1)/4 then -- Four because of the number of bytes per word
                   if to_integer(unsigned(dsp_sc_write_addr(h)(SIMD_BITS+1 downto 0))/4 + i) < SIMD then
                     dsp_we_word(h)(to_integer(unsigned(dsp_sc_write_addr(h)(SIMD_BITS+1 downto 0))/4 + i)) <= '1';
                   elsif to_integer(unsigned(dsp_sc_write_addr(h)(SIMD_BITS+1 downto 0))/4 + i) >= SIMD then
                     dsp_we_word(h)(to_integer(unsigned(dsp_sc_write_addr(h)(SIMD_BITS+1 downto 0))/4 + i - SIMD)) <= '1';
                   end if;
                 end if;
               end loop;
             end if;
           elsif vec_write_rd_DSP(h) = '0' and  dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) = '1' then
             dsp_we_word(h)(to_integer(unsigned(dsp_sc_write_addr(h)(SIMD_BITS+1 downto 0))/4)) <= '1';
           end if;
           -------------------------------------------------------------------------------------------------------------------------


           if decoded_instruction_DSP_lat(h)(KBCAST_bit_position)  = '1' then
             -- KBCAST signals are handeled here
             if MVSIZE_WRITE(h) > (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             wb_ready(h) <= '1';
             dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) <= '1';
             dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
           end if;

           if decoded_instruction_DSP_lat(h)(KVCP_bit_position)  = '1' then
             -- KVCP signals are handeled here
             if adder_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))  <= '1';
               dsp_sc_read_addr(h)(0) <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
             end if;
             if MVSIZE_WRITE(h) > (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;

           if decoded_instruction_DSP_lat(h)(KRELU_bit_position) = '1' then
             -- KRELU signals are handeled here
             if cmp_stage_2_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))  <= '1';
               dsp_sc_read_addr(h)(0) <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
             end if;
             if MVSIZE_WRITE(h) > (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;

           if decoded_instruction_DSP_lat(h)(KVSLT_bit_position)  = '1' then
             -- KADDV and KSUBV signals are handeled here
             if cmp_stage_2_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs2_to_sc(h))))(1) <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))  <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs2_to_sc(h))))  <= '1';
               dsp_sc_read_addr(h)(0)  <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
               dsp_sc_read_addr(h)(1)  <= RS2_Data_IE_lat(h)(Addr_Width - 1 downto 0);
             end if;
             if MVSIZE_WRITE(h) > (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;

           if decoded_instruction_DSP_lat(h)(KSVSLT_bit_position) = '1' then
             -- KADDV and KSUBV signals are handeled here
             if cmp_stage_2_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))  <= '1';
               dsp_sc_read_addr(h)(0)  <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
             end if;
             if MVSIZE_WRITE(h) > (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;

           if decoded_instruction_DSP_lat(h)(KSRAV_bit_position)  = '1' or
              decoded_instruction_DSP_lat(h)(KSRLV_bit_position)  = '1' then
             -- KSRAV signals are handeled here
             if shifter_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))  <= '1';
               dsp_sc_read_addr(h)(0)  <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
             end if;
             if MVSIZE_WRITE(h) > (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;

           if decoded_instruction_DSP_lat(h)(KADDV_bit_position)  = '1' or
              decoded_instruction_DSP_lat(h)(KSUBV_bit_position)  = '1' then
             -- KADDV and KSUBV signals are handeled here
             if adder_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs2_to_sc(h))))(1) <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))  <= '1';
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs2_to_sc(h))))  <= '1';
               dsp_sc_read_addr(h)(0)  <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
               dsp_sc_read_addr(h)(1)  <= RS2_Data_IE_lat(h)(Addr_Width - 1 downto 0);
             end if;
             if MVSIZE_WRITE(h) > (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h))))    <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;
    
           if decoded_instruction_DSP_lat(h)(KVRED_bit_position)   = '1' or
              decoded_instruction_DSP_lat(h)(KDOTP_bit_position)   = '1' or
              decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1' then
             -- KDOTP signals are handeled here
             if accum_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               if vec_read_rs2_DSP(h) = '1' then
                 dsp_sci_req(h)(to_integer(unsigned(dsp_rs2_to_sc(h)))) <= '1';
                 dsp_to_sc(h)(to_integer(unsigned(dsp_rs2_to_sc(h))))(1) <= '1';
                 dsp_sc_read_addr(h)(1)  <= RS2_Data_IE_lat(h)(Addr_Width - 1 downto 0);
               end if;
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h)))) <= '1';
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_sc_read_addr(h)(0)  <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             elsif MVSIZE_WRITE(h) = (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_init;
             else
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h))))    <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;

           if decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1' or 
              decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1' or 
              decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1' or 
              decoded_instruction_DSP_lat(h)(KSVADDSC_bit_position) = '1' or 
              decoded_instruction_DSP_lat(h)(KSVADDRF_bit_position) = '1' then
             -- KMUL signals are handeled here
             if mul_stage_3_en(h) = '1' or adder_stage_3_en(h) = '1' then 
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';
             end if;
             if MVSIZE_READ(h) > (0 to Addr_Width => '0') then
               dsp_sci_req(h)(to_integer(unsigned(dsp_rs1_to_sc(h)))) <= '1';
               if rf_rs2(h) = '0' then -- if the scalar does not come from the regfile
                 dsp_sci_req(h)(to_integer(unsigned(dsp_rs2_to_sc(h)))) <= '1';
                 dsp_to_sc(h)(to_integer(unsigned(dsp_rs2_to_sc(h))))(1) <= '1';
                 dsp_sc_read_addr(h)(1)  <= RS2_Data_IE_lat(h)(Addr_Width - 1 downto 0);
               end if;
               dsp_to_sc(h)(to_integer(unsigned(dsp_rs1_to_sc(h))))(0) <= '1';
               dsp_sc_read_addr(h)(0)  <= RS1_Data_IE_lat(h)(Addr_Width - 1 downto 0);
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             elsif MVSIZE_WRITE(h) = (0 to Addr_Width => '0') then
               nextstate_DSP(h) <= dsp_init;
             else
               nextstate_DSP(h) <= dsp_exec;
               busy_DSP_internal_wires := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we(h)(to_integer(unsigned(dsp_rd_to_sc(h)))) <= '1';
               dsp_sc_write_addr(h) <= RD_Data_IE_lat(h);
             end if;
           end if;

         when others =>
           null;
       end case;
     end if;
      
    busy_DSP_internal(h)    <= busy_DSP_internal_wires;
    dsp_except_condition(h) <= dsp_except_condition_wires(h);
    dsp_taken_branch(h)     <= dsp_taken_branch_wires(h);
      
  end process;

  ---------------------------------------------------------------------------------------------------------------------------------------------------------
  --  ██████╗ ██╗██████╗ ███████╗██╗     ██╗███╗   ██╗███████╗     ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  ██████╗ ██╗     ██╗     ███████╗██████╗   --
  --  ██╔══██╗██║██╔══██╗██╔════╝██║     ██║████╗  ██║██╔════╝    ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔═══██╗██║     ██║     ██╔════╝██╔══██╗  --
  --  ██████╔╝██║██████╔╝█████╗  ██║     ██║██╔██╗ ██║█████╗      ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝██║   ██║██║     ██║     █████╗  ██████╔╝  --
  --  ██╔═══╝ ██║██╔═══╝ ██╔══╝  ██║     ██║██║╚██╗██║██╔══╝      ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██║   ██║██║     ██║     ██╔══╝  ██╔══██╗  --
  --  ██║     ██║██║     ███████╗███████╗██║██║ ╚████║███████╗    ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║╚██████╔╝███████╗███████╗███████╗██║  ██║  --
  --  ╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝  --
  ---------------------------------------------------------------------------------------------------------------------------------------------------------

  fsm_DSP_pipeline_controller : process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      dsp_data_gnt_i_lat(h)    <= '0';
      adder_stage_1_en(h)      <= '0';
      adder_stage_2_en(h)      <= '0';
      adder_stage_3_en(h)      <= '0';
      shifter_stage_1_en(h)    <= '0';
      shifter_stage_2_en(h)    <= '0';
      mul_stage_1_en(h)        <= '0';
      mul_stage_2_en(h)        <= '0';
      mul_stage_3_en(h)        <= '0';
      accum_stage_1_en(h)      <= '0';
      accum_stage_2_en(h)      <= '0';
      accum_stage_3_en(h)      <= '0';
      cmp_stage_1_en(h)        <= '0';
      cmp_stage_2_en(h)        <= '0';
      busy_DSP_internal_lat(h) <= '0';
      state_DSP(h)             <= dsp_init;
      dsp_except_data(h)       <= (others => '0');
    elsif rising_edge(clk_i) then
      dsp_data_gnt_i_lat(h)   <= dsp_data_gnt_i(h);
      adder_stage_1_en(h)     <= dsp_data_gnt_i_lat(h) and add_en(h);
      adder_stage_2_en(h)     <= adder_stage_1_en(h);
      adder_stage_3_en(h)     <= adder_stage_2_en(h);
      mul_stage_1_en(h)       <= dsp_data_gnt_i_lat(h) and mul_en(h);
      mul_stage_2_en(h)       <= mul_stage_1_en(h);
      mul_stage_3_en(h)       <= mul_stage_2_en(h);
      accum_stage_2_en(h)     <= accum_stage_1_en(h);
      accum_stage_3_en(h)     <= accum_stage_2_en(h);
      shifter_stage_2_en(h)   <= shifter_stage_1_en(h);
      shifter_stage_3_en(h)   <= shifter_stage_2_en(h);
      cmp_stage_2_en(h)       <= cmp_stage_1_en(h);
      if dotpps(h) = '1' then
        shifter_stage_1_en(h) <= mul_stage_2_en(h);
        accum_stage_1_en(h)   <= shifter_stage_2_en(h);
      elsif dotp(h) = '1' then
        accum_stage_1_en(h)   <= mul_stage_2_en(h);
      elsif slt(h) = '1' then
        cmp_stage_1_en(h)     <= adder_stage_2_en(h);
      else
        shifter_stage_1_en(h) <= dsp_data_gnt_i_lat(h) and shift_en(h);
        accum_stage_1_en(h)   <= dsp_data_gnt_i_lat(h) and accum_en(h);
        cmp_stage_1_en(h)     <= dsp_data_gnt_i_lat(h) and cmp_en(h);
      end if;
      halt_dsp_lat(h)          <= halt_dsp(h);
      state_DSP(h)             <= nextstate_DSP(h);
      busy_DSP_internal_lat(h) <= busy_DSP_internal(h);
      SIMD_RD_BYTES(h)         <= SIMD_RD_BYTES_wire(h);
      dsp_except_data(h)       <= dsp_except_data_wire(h);
    end if;
  end process;

  DSP_FU_ENABLER_SYNC : process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      shift_en(h)         <= '0'; 
      add_en(h)           <= '0'; 
      cmp_en(h)           <= '0';
      accum_en(h)         <= '0'; 
      mul_en(h)           <= '0';
      add_en_pending(h)   <= '0';
      shift_en_pending(h) <= '0';
      mul_en_pending(h)   <= '0';
      accum_en_pending(h) <= '0';
      cmp_en_pending(h)   <= '0';
    elsif rising_edge(clk_i) then
      shift_en(h)         <= shift_en_wire(h); 
      add_en(h)           <= add_en_wire(h); 
      cmp_en(h)           <= cmp_en_wire(h); 
      accum_en(h)         <= accum_en_wire(h); 
      mul_en(h)           <= mul_en_wire(h); 
      add_en_pending(h)   <= add_en_pending_wire(h);
      shift_en_pending(h) <= shift_en_pending_wire(h);
      mul_en_pending(h)   <= mul_en_pending_wire(h);
      accum_en_pending(h) <= accum_en_pending_wire(h);
      cmp_en_pending(h)   <= cmp_en_pending_wire(h);
    end if;

  end process;

end generate DSP_replicated;

  -------------------------------------------------------------------------------------------------------------------------------------------
  --  ███████╗██╗   ██╗     █████╗  ██████╗ ██████╗███████╗███████╗███████╗    ██╗  ██╗ █████╗ ███╗   ██╗██████╗ ██╗     ███████╗██████╗   --
  --  ██╔════╝██║   ██║    ██╔══██╗██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝    ██║  ██║██╔══██╗████╗  ██║██╔══██╗██║     ██╔════╝██╔══██╗  --
  --  █████╗  ██║   ██║    ███████║██║     ██║     █████╗  ███████╗███████╗    ███████║███████║██╔██╗ ██║██║  ██║██║     █████╗  ██████╔╝  --
  --  ██╔══╝  ██║   ██║    ██╔══██║██║     ██║     ██╔══╝  ╚════██║╚════██║    ██╔══██║██╔══██║██║╚██╗██║██║  ██║██║     ██╔══╝  ██╔══██╗  --
  --  ██║     ╚██████╔╝    ██║  ██║╚██████╗╚██████╗███████╗███████║███████║    ██║  ██║██║  ██║██║ ╚████║██████╔╝███████╗███████╗██║  ██║  --
  --  ╚═╝      ╚═════╝     ╚═╝  ╚═╝ ╚═════╝ ╚═════╝╚══════╝╚══════╝╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝  --
  -------------------------------------------------------------------------------------------------------------------------------------------

FU_HANDLER_MC : if multithreaded_accl_en = 0 generate
  DSP_FU_ENABLER_comb : process(all)
  begin
    for h in accl_range loop
      shift_en_wire(h) <= shift_en(h); 
      add_en_wire(h)   <= add_en(h); 
      cmp_en_wire(h)   <= cmp_en(h); 
      accum_en_wire(h) <= accum_en(h); 
      mul_en_wire(h)   <= mul_en(h); 
      halt_hart(h)     <= '0';

      if add_en(h) = '1' and busy_DSP_internal(h) = '0' then
        add_en_wire(h) <= '0';
      end if;
      if mul_en(h) = '1' and busy_DSP_internal(h) = '0' then
        mul_en_wire(h) <= '0';
      end if;
      if shift_en(h) = '1' and busy_DSP_internal(h) = '0' then
        shift_en_wire(h) <= '0';
      end if;
      if accum_en(h) = '1' and busy_DSP_internal(h) = '0' then
        accum_en_wire(h) <= '0';
      end if;
      if cmp_en(h) = '1' and busy_DSP_internal(h) = '0' then
        cmp_en_wire(h) <= '0';
      end if;

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then

        case state_DSP(h) is

          when dsp_init =>

            -- Set signals to enable correct virtual parallelism operation
            if decoded_instruction_DSP(KADDV_bit_position)    = '1' or 
               decoded_instruction_DSP(KSVADDSC_bit_position) = '1' or
               decoded_instruction_DSP(KSVADDRF_bit_position) = '1' or
               decoded_instruction_DSP(KSUBV_bit_position)    = '1' or
               decoded_instruction_DSP(KVCP_bit_position)     = '1' then
              add_en_wire(h) <= '1';
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' then
              mul_en_wire(h)   <= '1';
              accum_en_wire(h) <= '1';
            elsif decoded_instruction_DSP(KDOTPPS_bit_position) = '1' then
              mul_en_wire(h)   <= '1';
              shift_en_wire(h) <= '1';
              accum_en_wire(h) <= '1';
            elsif decoded_instruction_DSP(KVSLT_bit_position)  = '1' or
                  decoded_instruction_DSP(KSVSLT_bit_position) = '1' then
              add_en_wire(h) <= '1';
              cmp_en_wire(h) <= '1';
            elsif decoded_instruction_DSP(KVRED_bit_position) = '1' then
              accum_en_wire(h) <= '1';
            elsif decoded_instruction_DSP(KSVMULRF_bit_position) = '1' or
                  decoded_instruction_DSP(KSVMULSC_bit_position) = '1' or
                  decoded_instruction_DSP(KVMUL_bit_position)    = '1' then
              mul_en_wire(h) <= '1';
            elsif decoded_instruction_DSP(KSRAV_bit_position) = '1' or
                  decoded_instruction_DSP(KSRLV_bit_position) = '1' then
              shift_en_wire(h) <= '1';
            elsif decoded_instruction_DSP(KRELU_bit_position)  = '1' then
              cmp_en_wire(h) <= '1';
            end if;
          when others =>
            null;
        end case;
      end if;
    end loop;
  end process;
end generate FU_HANDLER_MC;

FU_HANDLER_MT : if multithreaded_accl_en = 1 generate
  DSP_FU_ENABLER_comb : process(all)
  begin

    for h in accl_range loop

      shift_en_wire(h)               <= shift_en(h); 
      add_en_wire(h)                 <= add_en(h); 
      cmp_en_wire(h)                 <= cmp_en(h); 
      accum_en_wire(h)               <= accum_en(h); 
      mul_en_wire(h)                 <= mul_en(h); 
      add_en_pending_wire(h)         <= add_en_pending(h);
      shift_en_pending_wire(h)       <= shift_en_pending(h);
      mul_en_pending_wire(h)         <= mul_en_pending(h);
      accum_en_pending_wire(h)       <= accum_en_pending(h);
      cmp_en_pending_wire(h)         <= cmp_en_pending(h);
      fu_req(h)                      <= (others => '0');
      halt_hart(h)                   <= '0';


      if add_en(h) = '1' and busy_DSP_internal(h) = '0' then
        add_en_wire(h) <= '0';
      end if;
      if mul_en(h) = '1' and busy_DSP_internal(h) = '0' then
        mul_en_wire(h) <= '0';
      end if;
      if shift_en(h) = '1' and busy_DSP_internal(h) = '0' then
        shift_en_wire(h) <= '0';
      end if;
      if accum_en(h) = '1' and busy_DSP_internal(h) = '0' then
        accum_en_wire(h) <= '0';
      end if;
      if cmp_en(h) = '1' and busy_DSP_internal(h) = '0' then
        cmp_en_wire(h) <= '0';
      end if;

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then

        case state_DSP(h) is

          when dsp_init =>

            -- Set signals to enable correct virtual parallelism operation
            if decoded_instruction_DSP(KADDV_bit_position)    = '1' or 
               decoded_instruction_DSP(KSVADDSC_bit_position) = '1' or
               decoded_instruction_DSP(KSVADDRF_bit_position) = '1' or
               decoded_instruction_DSP(KSUBV_bit_position)    = '1' or
               decoded_instruction_DSP(KVCP_bit_position)     = '1' then
              if busy_add = '0' and add_en_pending = (accl_range => '0') then 
                add_en_wire(h) <= '1';
              else
                add_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(0) <= '1';
              end if;
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' then
              if busy_mul = '0' and busy_acc = '0' and mul_en_pending = (accl_range => '0') and accum_en_pending = (accl_range => '0') then 
                mul_en_wire(h)   <= '1';
                accum_en_wire(h) <= '1';
              else
                mul_en_pending_wire(h)   <= '1';
                accum_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(2) <= '1';
                fu_req(h)(3) <= '1';
              end if;
            elsif decoded_instruction_DSP(KDOTPPS_bit_position) = '1' then
              if busy_mul = '0' and busy_acc = '0' and busy_shf = '0'  and mul_en_pending = (accl_range => '0') and accum_en_pending = (accl_range => '0') and shift_en_pending = (accl_range => '0') then 
                mul_en_wire(h)   <= '1';
                shift_en_wire(h) <= '1';
                accum_en_wire(h) <= '1';
              else
                mul_en_pending_wire(h)   <= '1';
                shift_en_pending_wire(h) <= '1';
                accum_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(2) <= '1';
                fu_req(h)(1) <= '1';
                fu_req(h)(3) <= '1';
              end if;
            elsif decoded_instruction_DSP(KVRED_bit_position) = '1' then
              if busy_acc = '0' and accum_en_pending = (accl_range => '0') then 
                accum_en_wire(h) <= '1';
              else
                accum_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(3) <= '1';
              end if;
            elsif decoded_instruction_DSP(KSVMULRF_bit_position) = '1' or
                  decoded_instruction_DSP(KSVMULSC_bit_position) = '1' or
                  decoded_instruction_DSP(KVMUL_bit_position)    = '1' then
              if busy_mul = '0' and mul_en_pending = (accl_range => '0') then 
                mul_en_wire(h) <= '1';
              else
                mul_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(2) <= '1';
              end if;
            elsif decoded_instruction_DSP(KSRAV_bit_position) = '1' or
                  decoded_instruction_DSP(KSRLV_bit_position) = '1' then
              if busy_shf = '0' and shift_en_pending = (accl_range => '0') then 
                shift_en_wire(h) <= '1';
              else
                shift_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(1) <= '1';
              end if;
            elsif decoded_instruction_DSP(KRELU_bit_position) = '1' then
              if busy_cmp = '0' and cmp_en_pending = (accl_range => '0') then 
                cmp_en_wire(h) <= '1';
              else
                cmp_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(4) <= '1';
              end if;
            elsif decoded_instruction_DSP(KVSLT_bit_position)  = '1' or
                  decoded_instruction_DSP(KSVSLT_bit_position) = '1' then
              if busy_cmp = '0' and busy_add = '0' and cmp_en_pending = (accl_range => '0') and add_en_pending = (accl_range => '0') then 
                add_en_wire(h)   <= '1';
                cmp_en_wire(h) <= '1';
              else
                add_en_pending_wire(h) <= '1';
                cmp_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req(h)(0) <= '1';
                fu_req(h)(4) <= '1';
              end if;
            end if;

          when dsp_halt_hart =>
  
            if fu_gnt(h)(0) = '1' then
              add_en_wire(h) <= '1';
              add_en_pending_wire(h) <= '0';
            elsif add_en_pending(h) = '1' and fu_gnt(h)(0) = '0'  then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt(h)(1) = '1' then
              shift_en_wire(h) <= '1';
              shift_en_pending_wire(h) <= '0';
            elsif shift_en_pending(h) = '1' and fu_gnt(h)(1) = '0' then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt(h)(2) = '1' then
              mul_en_wire(h) <= '1';
              mul_en_pending_wire(h) <= '0';
            elsif mul_en_pending(h) = '1' and fu_gnt(h)(2) = '0'  then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt(h)(3) = '1' then
              accum_en_wire(h) <= '1';
              accum_en_pending_wire(h) <= '0';
            elsif accum_en_pending(h) = '1' and fu_gnt(h)(3) = '0'  then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt(h)(4) = '1' then
              cmp_en_wire(h) <= '1';
              cmp_en_pending_wire(h) <= '0';
            elsif cmp_en_pending(h) = '1' and fu_gnt(h)(4) = '0'  then
              halt_hart(h) <= '1';
            end if;

          when others =>
            null;
        end case;
      end if;
    end loop;
  end process;

  FU_Issue_Buffer_sync : process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      fu_rd_ptr  <= (others => (others => '0'));
      fu_wr_ptr  <= (others => (others => '0'));
      fu_gnt     <= (others => (others => '0'));
    elsif rising_edge(clk_i) then
      fu_gnt <= fu_gnt_wire;
      for h in accl_range loop
        for i in 0 to 4 loop  -- Loop index 'i' is for the total number of different functional units (regardless what SIMD config is set)
          if fu_req(h)(i) = '1' then  -- if a reservation was made, to use a functional unit
            --to_integer(unsigned(fu_issue_buffer(i)(to_integer(unsigned(fu_wr_ptr(i)))))) <= h;  -- store the thread_ID in its corresponding buffer at the fu_wr_ptr position
            --fu_issue_buffer(to_integer(unsigned(fu_wr_ptr(i))))(i) <= std_logic_vector(unsigned(h));  -- store the thread_ID in its corresponding buffer at the fu_wr_ptr position
            fu_issue_buffer(i)(to_integer(unsigned(fu_wr_ptr(i))))  <= std_logic_vector(to_unsigned(h,TPS_CEIL));
            if unsigned(fu_wr_ptr(i)) = THREAD_POOL_SIZE - 2 then -- increment the pointer wr logic
              fu_wr_ptr(i) <= (others => '0');
            else
              fu_wr_ptr(i) <= std_logic_vector(unsigned(fu_wr_ptr(i)) + 1);
            end if;
          end if;
          case state_DSP(h) is
            when dsp_halt_hart =>
              if fu_gnt_en(h)(i) = '1' then
                if unsigned(fu_rd_ptr(i)) = THREAD_POOL_SIZE - 2 then  -- increment the read pointer
                  fu_rd_ptr(i) <= (others => '0');
                else
                  fu_rd_ptr(i) <= std_logic_vector(unsigned(fu_rd_ptr(i)) + 1);
                end if;
              end if;
            when others =>
             null;
          end case;
        end loop;
      end loop;
    end if;
  end process;

  FU_Issue_Buffer_comb : process(all)
  begin
    for h in accl_range loop
      fu_gnt_wire(h) <= (others => '0');
      fu_gnt_en(h)   <= (others => '0');
      if add_en_pending_wire(h) = '1' and busy_add_wire = '0' then
        fu_gnt_en(h)(0) <= '1';
      end if;
      if shift_en_pending_wire(h) = '1' and busy_shf_wire = '0' then
        fu_gnt_en(h)(1) <= '1';
      end if;
      if mul_en_pending_wire(h) = '1' and busy_mul_wire = '0' then
        fu_gnt_en(h)(2) <= '1';
      end if;
      if accum_en_pending_wire(h) = '1' and busy_acc_wire = '0' then
        fu_gnt_en(h)(3) <= '1';
      end if;
      if cmp_en_pending_wire(h) = '1' and busy_cmp_wire = '0' then
        fu_gnt_en(h)(4) <= '1';
      end if;
      case state_DSP(h) is
        when dsp_halt_hart =>
          for i in 0 to 4 loop 
            if fu_gnt_en(h)(i) = '1' then
              fu_gnt_wire(to_integer(unsigned(fu_issue_buffer(i)(to_integer(unsigned(fu_rd_ptr(i)))))))(i) <= '1';
               -- give a grant to fu_gnt(h)(i), such that the 'h' index points to the thread in "fu_issue_buffer"
            end if;
          end loop;
        when others =>
          null;
      end case;
    end loop;
  end process;


  DSP_BUSY_FU_SYNC : process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
    elsif rising_edge(clk_i) then
      busy_add    <= busy_add_wire;
      busy_mul    <= busy_mul_wire;
      busy_shf    <= busy_shf_wire;
      busy_acc    <= busy_acc_wire;
      busy_cmp    <= busy_cmp_wire;
    end if;
  end process;

end generate FU_HANDLER_MT;

busy_add_wire <= '1' when multithreaded_accl_en = 1 and add_en_wire   /= (accl_range => '0') else '0';
busy_mul_wire <= '1' when multithreaded_accl_en = 1 and mul_en_wire   /= (accl_range => '0') else '0';
busy_shf_wire <= '1' when multithreaded_accl_en = 1 and shift_en_wire /= (accl_range => '0') else '0';
busy_acc_wire <= '1' when multithreaded_accl_en = 1 and accum_en_wire /= (accl_range => '0') else '0';
busy_cmp_wire <= '1' when multithreaded_accl_en = 1 and cmp_en_wire   /= (accl_range => '0') else '0';


  -----------------------------------------------------------------
  --  ███╗   ███╗ █████╗ ██████╗ ██████╗ ██╗███╗   ██╗ ██████╗   --
  --  ████╗ ████║██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║██╔════╝   --
  --  ██╔████╔██║███████║██████╔╝██████╔╝██║██╔██╗ ██║██║  ███╗  --
  --  ██║╚██╔╝██║██╔══██║██╔═══╝ ██╔═══╝ ██║██║╚██╗██║██║   ██║  --
  --  ██║ ╚═╝ ██║██║  ██║██║     ██║     ██║██║ ╚████║╚██████╔╝  --
  --  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝   --
  -----------------------------------------------------------------

MULTICORE_OUT_MAPPER : if multithreaded_accl_en = 0 generate
MAPPER_replicated : for h in fu_range generate

  MAPPING_OUT_UNIT_comb : process(all)
  begin
      dsp_sc_data_write_wire_int(h)  <= (others => '0');
      dsp_sc_data_write_wire(h)      <= dsp_sc_data_write_wire_int(h);
      SIMD_RD_BYTES_wire(h)          <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8), 32));

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
        case state_DSP(h) is
          when dsp_init =>

            -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP(KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP(KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP(KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP(KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULSC_bit_position) = '1') and 
              MVTYPE(h)(3 downto 2) = "00" then
              SIMD_RD_BYTES_wire(h) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

          when dsp_exec =>

           -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP_lat(h)(KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP_lat(h)(KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
                (MVTYPE_DSP(h) = "00") then
              SIMD_RD_BYTES_wire(h) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

            if decoded_instruction_DSP_lat(h)(KDOTP_bit_position)   = '1' or 
               decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1' or
               decoded_instruction_DSP_lat(h)(KDOTP_bit_position)   = '1' or
               decoded_instruction_DSP_lat(h)(KVRED_bit_position)   = '1' then
              dsp_sc_data_write_wire_int(h)(31 downto 0) <= dsp_out_accum_results(h); 
               -- AAA add a mask in order to store the lower half word when 16-bit or entire word when 32-bit
            end if;

            if (decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
               MVTYPE_DSP(h) = "00" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(7+8*(i) downto 8*(i)) <= dsp_out_mul_results(h)(7+8*(2*i) downto 8*(2*i));
              end loop;
            end if;

            if (decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
               (MVTYPE_DSP(h) = "01" or  MVTYPE_DSP(h) = "10") then
              dsp_sc_data_write_wire_int(h) <= dsp_out_mul_results(h);
            end if;

            if decoded_instruction_DSP_lat(h)(KSRAV_bit_position)   = '1' or
               decoded_instruction_DSP_lat(h)(KSRLV_bit_position)   = '1' then
              dsp_sc_data_write_wire_int(h)  <= dsp_out_shifter_results(h);
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDSC_bit_position)   = '1' or
               decoded_instruction_DSP_lat(h)(KSVADDRF_bit_position)   = '1' or
               decoded_instruction_DSP_lat(h)(KADDV_bit_position)      = '1' or
               decoded_instruction_DSP_lat(h)(KSUBV_bit_position)      = '1' or
               decoded_instruction_DSP_lat(h)(KVCP_bit_position)       = '1' then
              dsp_sc_data_write_wire_int(h) <= dsp_out_adder_results(h);
            end if;


            if decoded_instruction_DSP_lat(h)(KRELU_bit_position)  = '1' or
               decoded_instruction_DSP_lat(h)(KVSLT_bit_position)  = '1' or
               decoded_instruction_DSP_lat(h)(KSVSLT_bit_position) = '1' then
              dsp_sc_data_write_wire_int(h) <= dsp_out_cmp_results(h);
            end if;

            if    decoded_instruction_DSP_lat(h)(KBCAST_bit_position) = '1' and MVTYPE_DSP(h) = "10" then
              for i in 0 to SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(31+32*(i) downto 32*(i)) <= RS1_Data_IE_lat(h);
              end loop;
            elsif decoded_instruction_DSP_lat(h)(KBCAST_bit_position) = '1' and MVTYPE_DSP(h) = "01" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(15+16*(i) downto 16*(i)) <= RS1_Data_IE_lat(h)(15 downto 0);
              end loop;
            elsif decoded_instruction_DSP_lat(h)(KBCAST_bit_position) = '1' and MVTYPE_DSP(h) = "00" then
              for i in 0 to 4*SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(7+8*(i)   downto 8*(i))  <= RS1_Data_IE_lat(h)(7 downto 0);
              end loop;
            end if;

            if halt_dsp(h) = '0' and halt_dsp_lat(h) = '1' then
              dsp_sc_data_write_wire(h) <= dsp_sc_data_write_int(h);
            end if;
          when others =>
            null;
        end case;
      end if;
  end process;

end generate;
end generate;

MULTITHREAD_OUT_MAPPER : if multithreaded_accl_en = 1 generate
  MAPPING_OUT_UNIT_comb : process(all)
  begin
    for h in 0 to (ACCL_NUM - FU_NUM) loop
      dsp_sc_data_write_wire_int(h)  <= (others => '0');
      dsp_sc_data_write_wire(h)      <= dsp_sc_data_write_wire_int(h);
      SIMD_RD_BYTES_wire(h) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8), 32));

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
        case state_DSP(h) is
          when dsp_init =>

            -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP(KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP(KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP(KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP(KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULSC_bit_position) = '1') and
                MVTYPE(h)(3 downto 2) = "00" then
              SIMD_RD_BYTES_wire(h) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

          when dsp_exec =>

           -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP_lat(h)(KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP_lat(h)(KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(h) = "00" then
              SIMD_RD_BYTES_wire(h) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

            if decoded_instruction_DSP_lat(h)(KDOTP_bit_position)   = '1' or 
               decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1' or
               decoded_instruction_DSP_lat(h)(KVRED_bit_position)   = '1' then
              dsp_sc_data_write_wire_int(h)(31 downto 0) <= dsp_out_accum_results(0); 
               -- AAA add a mask in order to store the lower half word when 16-bit or entire word when 32-bit
            end if;

            if (decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(h) = "00" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(7+8*(i) downto 8*(i)) <= dsp_out_mul_results(0)(7+8*(2*i) downto 8*(2*i));
              end loop;
            end if;

            if (decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
               (MVTYPE_DSP(h) = "01" or MVTYPE_DSP(h) = "10") then
              dsp_sc_data_write_wire_int(h) <= dsp_out_mul_results(0);
            end if;

            if decoded_instruction_DSP_lat(h)(KSRAV_bit_position)   = '1' or
               decoded_instruction_DSP_lat(h)(KSRLV_bit_position)   = '1' then
              dsp_sc_data_write_wire_int(h)  <= dsp_out_shifter_results(0);
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDSC_bit_position)   = '1' or
               decoded_instruction_DSP_lat(h)(KSVADDRF_bit_position)   = '1' or
               decoded_instruction_DSP_lat(h)(KADDV_bit_position)      = '1' or
               decoded_instruction_DSP_lat(h)(KSUBV_bit_position)      = '1' or
               decoded_instruction_DSP_lat(h)(KVCP_bit_position)        = '1' then
              dsp_sc_data_write_wire_int(h) <= dsp_out_adder_results(0);
            end if;


            if decoded_instruction_DSP_lat(h)(KRELU_bit_position)  = '1' or
               decoded_instruction_DSP_lat(h)(KVSLT_bit_position)  = '1' or
               decoded_instruction_DSP_lat(h)(KSVSLT_bit_position) = '1' then
              dsp_sc_data_write_wire_int(h) <= dsp_out_cmp_results(0);
            end if;

            if decoded_instruction_DSP_lat(h)(KBCAST_bit_position) = '1' and MVTYPE_DSP(h) = "10" then
              for i in 0 to SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(31+32*(i) downto 32*(i)) <= RS1_Data_IE_lat(h);
              end loop;
            elsif decoded_instruction_DSP_lat(h)(KBCAST_bit_position) = '1' and MVTYPE_DSP(h) = "01" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(15+16*(i) downto 16*(i)) <= RS1_Data_IE_lat(h)(15 downto 0);
              end loop;
            elsif decoded_instruction_DSP_lat(h)(KBCAST_bit_position)  = '1' and MVTYPE_DSP(h) = "00" then
              for i in 0 to 4*SIMD-1 loop
                dsp_sc_data_write_wire_int(h)(7+8*(i)   downto 8*(i))  <= RS1_Data_IE_lat(h)(7 downto 0);
              end loop;
            end if;

            if halt_dsp(h) = '0' and halt_dsp_lat(h) = '1' then
              dsp_sc_data_write_wire(h) <= dsp_sc_data_write_int(h);
            end if;
          when others =>
            null;
        end case;
      end if;
    end loop;
  end process;
end generate;

--FU_IN_MAPPER_replicated : for f in accl_range generate
--FU_IN_MAPPER  : if (multithreaded_accl_en = 0 or (multithreaded_accl_en = 1 and f = 0)) generate

FU_replicated : for f in fu_range generate

  DSP_MAPPING_IN_UNIT_comb : process(all)
  variable h : integer;
  begin

    MSB_stage_1(f)                 <= (others => (others => '0')); 
    dsp_in_mul_operands(f)         <= (others => (others => '0'));
    dsp_in_adder_operands(f)       <= (others => (others => '0'));
    dsp_in_shift_amount(f)         <= (others => '0');
    dsp_in_shifter_operand(f)      <= (others => '0');
    dsp_in_accum_operands(f)       <= (others => '0');
    dsp_in_cmp_operands(f)         <= (others => '0');

    for g in 0 to (ACCL_NUM - FU_NUM) loop

      if multithreaded_accl_en = 1 then
        h := g;  -- set the spm rd/wr ports equal to the "for-loop"
      elsif multithreaded_accl_en = 0 then
        h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
      end if;

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
        case state_DSP(h) is

          when dsp_exec =>

            if (decoded_instruction_DSP_lat(h)(KDOTP_bit_position)   = '1' or 
                decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1') and
                MVTYPE_DSP(h) = "00" then
              for i in 0 to 2*SIMD-1 loop
                  dsp_in_mul_operands(f)(0)(15+16*(i) downto 16*(i)) <= (x"00" & (dsp_sc_data_read(h)(0)(7+8*(i) downto 8*(i)) and dsp_sc_data_read_mask(h)(7+8*(i) downto 8*(i))));
                  dsp_in_mul_operands(f)(1)(15+16*(i) downto 16*(i)) <= (x"00" & (dsp_sc_data_read(h)(1)(7+8*(i) downto 8*(i)) and dsp_sc_data_read_mask(h)(7+8*(i) downto 8*(i))));
                if dotp(h) = '1' then
                  dsp_in_accum_operands(f) <= dsp_out_mul_results(f);
                elsif dotpps(h) = '1' then
                  dsp_in_shift_amount(f)    <= MPSCLFAC_DSP(h);
                  dsp_in_shifter_operand(f) <= dsp_out_mul_results(f);
                  dsp_in_accum_operands(f)  <= dsp_out_shifter_results(f);
                end if;
              end loop;
            end if;

            if (decoded_instruction_DSP_lat(h)(KDOTP_bit_position)   = '1'  or
                decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1') and
               (MVTYPE_DSP(h) = "01" or MVTYPE_DSP(h) = "10") then
              dsp_in_mul_operands(f)(0) <= dsp_sc_data_read(h)(0) and dsp_sc_data_read_mask(h);
              dsp_in_mul_operands(f)(1) <= dsp_sc_data_read(h)(1) and dsp_sc_data_read_mask(h);
              if dotp(h) = '1' then
                dsp_in_accum_operands(f)  <= dsp_out_mul_results(f);
              elsif dotpps(h) = '1' then
                dsp_in_shift_amount(f)    <= MPSCLFAC_DSP(h);
                dsp_in_shifter_operand(f) <= dsp_out_mul_results(f);
                dsp_in_accum_operands(f)  <= dsp_out_shifter_results(f);
              end if;
            end if;

            if (decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(h) = "00" then
              for i in 0 to 2*SIMD-1 loop
                if vec_read_rs2_DSP(h) = '0' then
                  if rf_rs2(h) = '1' then
                    dsp_in_mul_operands(f)(1)(15+16*(i) downto 16*(i)) <= x"00" & RS2_Data_IE_lat(h)(7 downto 0); 
                    -- map the scalar value
                  elsif rf_rs2(h) = '0' then
                    dsp_in_mul_operands(f)(1)(15+16*(i) downto 16*(i)) <= x"00" & dsp_sc_data_read(h)(1)(7 downto 0); 
                    -- map the scalar value
                  end if;
                else
                  dsp_in_mul_operands(f)(1)(15+16*(i) downto 16*(i)) <= x"00" & dsp_sc_data_read(h)(1)(7+8*(i) downto 8*(i));
                end if;
                dsp_in_mul_operands(f)(0)(15+16*(i) downto 16*(i))  <= x"00" & dsp_sc_data_read(h)(0)(7+8*(i) downto 8*(i));
              end loop;
            end if;

            if (decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(h) = "01" then
              if vec_read_rs2_DSP(h) = '0' then
                if rf_rs2(h) = '1' then
                  for i in 0 to 2*SIMD-1 loop
                    dsp_in_mul_operands(f)(1)(15+16*(i) downto 16*(i)) <= RS2_Data_IE_lat(h)(15 downto 0); 
                    -- map the scalar value
                  end loop;
                elsif rf_rs2(h) = '0' then
                  for i in 0 to 2*SIMD-1 loop
                    dsp_in_mul_operands(f)(1)(15+16*(i) downto 16*(i)) <= dsp_sc_data_read(h)(1)(15 downto 0); 
                    -- map the scalar value
                  end loop;         
                end if;
              else
                dsp_in_mul_operands(f)(1) <= dsp_sc_data_read(h)(1);
              end if;
              dsp_in_mul_operands(f)(0)     <= dsp_sc_data_read(h)(0);
            end if;

            if (decoded_instruction_DSP_lat(h)(KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat(h)(KSVMULSC_bit_position) = '1') and
               MVTYPE_DSP(h) = "10" then
              if vec_read_rs2_DSP(h) = '0' then
                if rf_rs2(h) = '1' then
                  for i in 0 to SIMD-1 loop
                    dsp_in_mul_operands(f)(1)(31+32*(i) downto 32*(i)) <= RS2_Data_IE_lat(h)(31 downto 0); 
                    -- map the scalar value
                  end loop;
                elsif rf_rs2(h) = '0' then
                  for i in 0 to SIMD-1 loop
                    dsp_in_mul_operands(f)(1)(31+32*(i) downto 32*(i)) <= dsp_sc_data_read(h)(1)(31 downto 0); 
                    -- map the scalar value
                  end loop;
                end if;
              else
                dsp_in_mul_operands(f)(1) <= dsp_sc_data_read(h)(1);
              end if;
              dsp_in_mul_operands(f)(0) <= dsp_sc_data_read(h)(0);
            end if;

            if decoded_instruction_DSP_lat(h)(KADDV_bit_position) = '1' then 
              dsp_in_adder_operands(f)(0)   <= dsp_sc_data_read(h)(0);
              dsp_in_adder_operands(f)(1)   <= dsp_sc_data_read(h)(1);
            end if;

            if decoded_instruction_DSP_lat(h)(KSRAV_bit_position) = '1' or
               decoded_instruction_DSP_lat(h)(KSRLV_bit_position) = '1' then 
              dsp_in_shifter_operand(f)      <= dsp_sc_data_read(h)(0);
              dsp_in_shift_amount(f)         <= RS2_Data_IE_lat(h)(4 downto 0); 
              -- map the scalar value (shift amount)
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDSC_bit_position)  = '1' and MVTYPE_DSP(h) = "10" then
              dsp_in_adder_operands(f)(0)   <= dsp_sc_data_read(h)(0);
              for i in 0 to SIMD-1 loop
                dsp_in_adder_operands(f)(1)(31+32*(i) downto 32*(i))   <= dsp_sc_data_read(h)(1)(31 downto 0);
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDSC_bit_position)  = '1' and MVTYPE_DSP(h) = "01" then
              dsp_in_adder_operands(f)(0)   <= dsp_sc_data_read(h)(0);
              for i in 0 to 2*SIMD-1 loop
                dsp_in_adder_operands(f)(1)(15+16*(i) downto 16*(i))   <= dsp_sc_data_read(h)(1)(15 downto 0);
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDSC_bit_position)  = '1' and MVTYPE_DSP(h) = "00" then
              dsp_in_adder_operands(f)(0) <= dsp_sc_data_read(h)(0);
              for i in 0 to 4*SIMD-1 loop
                dsp_in_adder_operands(f)(1)(7+8*(i) downto 8*(i)) <= dsp_sc_data_read(h)(1)(7 downto 0);
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDRF_bit_position) = '1' and MVTYPE_DSP(h) = "10" then
              dsp_in_adder_operands(f)(0)   <= dsp_sc_data_read(h)(0);
              for i in 0 to SIMD-1 loop
                dsp_in_adder_operands(f)(1)(31+32*(i) downto 32*(i))   <= RS2_Data_IE_lat(h)(31 downto 0);
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDRF_bit_position) = '1' and MVTYPE_DSP(h) = "01" then
              dsp_in_adder_operands(f)(0)   <= dsp_sc_data_read(h)(0);
              for i in 0 to 2*SIMD-1 loop
                dsp_in_adder_operands(f)(1)(15+16*(i) downto 16*(i))   <= RS2_Data_IE_lat(h)(15 downto 0);
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KSVADDRF_bit_position) = '1' and MVTYPE_DSP(h) = "00" then
              dsp_in_adder_operands(f)(0)   <= dsp_sc_data_read(h)(0);
              for i in 0 to 4*SIMD-1 loop
                dsp_in_adder_operands(f)(1)(7+8*(i) downto 8*(i))   <= RS2_Data_IE_lat(h)(7 downto 0);
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KSUBV_bit_position)  = '1' then
              dsp_in_adder_operands(f)(0) <= dsp_sc_data_read(h)(0);
              dsp_in_adder_operands(f)(1) <= (not dsp_sc_data_read(h)(1));
            end if;

            if decoded_instruction_DSP_lat(h)(KVRED_bit_position)  = '1' and MVTYPE_DSP(h) = "00" then
              for i in 0 to 2*SIMD-1 loop
                dsp_in_accum_operands(f)(15+16*(i) downto 16*(i)) <= x"00" & (dsp_sc_data_read(h)(0)(7+8*(i) downto 8*(i)) and dsp_sc_data_read_mask(h)(7+8*(i) downto 8*(i)));
              end loop;
            end if;
            if decoded_instruction_DSP_lat(h)(KVRED_bit_position) = '1' and (MVTYPE_DSP(h) = "01" or MVTYPE_DSP(h) = "10") then
              dsp_in_accum_operands(f) <= dsp_sc_data_read(h)(0) and dsp_sc_data_read_mask(h);
            end if;

            if decoded_instruction_DSP_lat(h)(KRELU_bit_position)  = '1' then
              dsp_in_cmp_operands(f) <= dsp_sc_data_read(h)(0);
            end if;

            if decoded_instruction_DSP_lat(h)(KVSLT_bit_position) = '1' then
              dsp_in_adder_operands(f)(0) <= dsp_sc_data_read(h)(0);
              dsp_in_adder_operands(f)(1) <= (not dsp_sc_data_read(h)(1));
              dsp_in_cmp_operands(f)      <= dsp_out_adder_results(f);
              for i in 0 to 1 loop -- loops through both read busses for operands rs1, and rs2
                for j in 0 to 4*SIMD-1 loop -- loop transfers all the MSBs from the input to the output
                  MSB_stage_1(f)(i)(j) <= dsp_sc_data_read(h)(i)(7+8*(j));
                end loop;
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KSVSLT_bit_position) = '1'then
              dsp_in_adder_operands(f)(0) <= dsp_sc_data_read(h)(0);
              dsp_in_cmp_operands(f)      <= dsp_out_adder_results(f);
              if MVTYPE_DSP(h) = "10" then
                for i in 0 to SIMD-1 loop
                  dsp_in_adder_operands(f)(1)(31+32*(i) downto 32*(i)) <= not(RS2_Data_IE_lat(h)(31 downto 0));
                end loop;
                for j in 0 to SIMD-1 loop -- this index loops throughout the SIMD lanes
                  MSB_stage_1(f)(1)(4*(j)+3) <= RS2_Data_IE_lat(h)(31); 
                  -- Save the MSB in an array to be used for comparator results
                end loop;
              elsif MVTYPE_DSP(h) = "01" then
                for i in 0 to 2*SIMD-1 loop
                  dsp_in_adder_operands(f)(1)(15+16*(i) downto 16*(i)) <= not(RS2_Data_IE_lat(h)(15 downto 0));
                end loop;
                for i in 0 to 1 loop -- this index loops throughout the MSBs in the 8-bit subwords in the 32-bit word "RS2_Data_IE_lat"
                  for j in 0 to SIMD-1 loop -- this index loops throughout the SIMD lanes
                    MSB_stage_1(f)(1)(4*(j)+1+2*(i)) <= RS2_Data_IE_lat(h)(15);
                   -- Save the MSB in an array to be used for comparator results
                  end loop;
                end loop;
              elsif MVTYPE_DSP(h) = "00" then
                for i in 0 to 4*SIMD-1 loop
                  dsp_in_adder_operands(f)(1)(7+8*(i)   downto 8*(i))  <= not(RS2_Data_IE_lat(h)(7 downto 0));
                end loop;
                for i in 0 to 3 loop -- this index loops throughout the MSBs in the 8-bit subwords in the 32-bit word "RS2_Data_IE_lat"
                  for j in 0 to SIMD-1 loop -- this index loops throughout the SIMD lanes
                    MSB_stage_1(f)(1)(4*(j)+i) <= RS2_Data_IE_lat(h)(7); 
                  -- Save the MSB in an array to be used for comparator results
                  end loop;
                end loop;
              end if;
              for i in 0 to 4*SIMD-1 loop -- loop transfers all the MSBs from the input to the output
                MSB_stage_1(f)(0)(i) <= dsp_sc_data_read(h)(0)(7+8*(i));
              end loop;
            end if;

            if decoded_instruction_DSP_lat(h)(KVCP_bit_position) = '1' then
              dsp_in_adder_operands(f)(0) <= dsp_sc_data_read(h)(0);
            end if;

          when others =>
            null;
        end case;
      end if;
    end loop;
  end process;

--end generate;
--end generate;

--FU_IN_MAPPER  : if (multithreaded_accl_en = 0 or (multithreaded_accl_en = 1 and f = 0) generate

end generate FU_replicated;
  

  -- Shifters
  SHIF_STG: SHIFTER
    generic map(
      multithreaded_accl_en => multithreaded_accl_en,
      SIMD                  => SIMD,
      --------------------------------
      ACCL_NUM              => ACCL_NUM,
      FU_NUM                => FU_NUM,
      SIMD_Width            => SIMD_Width
    )
    port map(
      clk_i                             => clk_i,
      rst_ni                            => rst_ni,
      shifter_stage_1_en                => shifter_stage_1_en,
      shifter_stage_2_en                => shifter_stage_2_en,
      halt_dsp_lat                      => halt_dsp_lat,
      MVTYPE_DSP                        => MVTYPE_DSP,
      decoded_instruction_DSP_lat       => decoded_instruction_DSP_lat,
      recover_state_wires               => recover_state_wires,
      shift_en                          => shift_en,
      dsp_in_shifter_operand            => dsp_in_shifter_operand,
      dsp_in_shift_amount               => dsp_in_shift_amount,

      dsp_out_shifter_results           => dsp_out_shifter_results
    );

  -- Comparators
  COMP_STG: COMPARATOR
    generic map(
      SIMD                  => SIMD,
      multithreaded_accl_en => multithreaded_accl_en,
      --------------------------------
      ACCL_NUM              => ACCL_NUM,
      FU_NUM                => FU_NUM,
      SIMD_Width            => SIMD_Width
    )
    port map(
      clk_i                             => clk_i,
      rst_ni                            => rst_ni,
      MVTYPE_DSP                        => MVTYPE_DSP,
      relu_instr                        => relu_instr,
      halt_dsp_lat                      => halt_dsp_lat,
      cmp_stage_1_en                    => cmp_stage_1_en,
      recover_state_wires               => recover_state_wires,
      cmp_en                            => cmp_en,
      dsp_in_cmp_operands               => dsp_in_cmp_operands,
      MSB_stage_2                       => MSB_stage_2,

      dsp_out_cmp_results               => dsp_out_cmp_results
  );

  -- Adders
  ADD_STG: ADDER
    generic map(
      multithreaded_accl_en => multithreaded_accl_en,
      SIMD                  => SIMD,
      --------------------------------
      ACCL_NUM              => ACCL_NUM,
      FU_NUM                => FU_NUM,
      SIMD_Width            => SIMD_Width,
      Data_Width            => Data_Width
    )
    port map(
      clk_i                             => clk_i,
      rst_ni                            => rst_ni,
      halt_dsp_lat                      => halt_dsp_lat,
      adder_stage_1_en                  => adder_stage_1_en,
      adder_stage_2_en                  => adder_stage_2_en,
      carry_pass                        => carry_pass,
      twos_complement                   => twos_complement,
      recover_state_wires               => recover_state_wires,
      add_en                            => add_en,
      MSB_stage_1                       => MSB_stage_1,
      dsp_in_adder_operands             => dsp_in_adder_operands,

      dsp_out_adder_results             => dsp_out_adder_results,
      MSB_stage_2                       => MSB_stage_2
    );

  -- Multipliers
  MULT_STG: MULTIPLIER
    generic map(
      SIMD                  => SIMD,
      multithreaded_accl_en => multithreaded_accl_en,
      --------------------------------
      ACCL_NUM              => ACCL_NUM,
      FU_NUM                => FU_NUM,
      SIMD_Width            => SIMD_Width,
      Data_Width            => Data_Width
    )
    port map(
      clk_i                             => clk_i,
      rst_ni                            => rst_ni,
      FUNCT_SELECT_MASK                 => FUNCT_SELECT_MASK,
      MVTYPE_DSP                        => MVTYPE_DSP,
      recover_state_wires               => recover_state_wires,
      halt_dsp_lat                      => halt_dsp_lat,
      mul_stage_1_en                    => mul_stage_1_en,
      mul_stage_2_en                    => mul_stage_2_en,
      mul_en                            => mul_en,
      dsp_in_mul_operands               => dsp_in_mul_operands,

      dsp_out_mul_results               => dsp_out_mul_results
    );

  ----------------------------------------------------
  --   █████╗  ██████╗ ██████╗██╗   ██╗███╗   ███╗  --
  --  ██╔══██╗██╔════╝██╔════╝██║   ██║████╗ ████║  --
  --  ███████║██║     ██║     ██║   ██║██╔████╔██║  --
  --  ██╔══██║██║     ██║     ██║   ██║██║╚██╔╝██║  --
  --  ██║  ██║╚██████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║  --
  --  ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝  --
  ----------------------------------------------------

 ACCUM_STG : ACCUMULATOR
    generic map(
      multithreaded_accl_en              => multithreaded_accl_en, 
      SIMD                               => SIMD, 
      -------------------------------------------------
      ACCL_NUM                           => ACCL_NUM, 
      FU_NUM                             => FU_NUM, 
      Data_Width                         => Data_Width, 
      SIMD_Width                         => SIMD_Width
    )
  port map(
      clk_i                             => clk_i,
      rst_ni                            => rst_ni,
      MVTYPE_DSP                        => MVTYPE_DSP,
      accum_stage_1_en                  => accum_stage_1_en,
      accum_stage_2_en                  => accum_stage_2_en,
      recover_state_wires               => recover_state_wires,
      halt_dsp_lat                      => halt_dsp_lat,
      state_DSP                         => state_DSP,
      decoded_instruction_DSP_lat       => decoded_instruction_DSP_lat,
      dsp_in_accum_operands             => dsp_in_accum_operands,
      dsp_out_accum_results             => dsp_out_accum_results
  );


------------------------------------------------------------------------ end of DSP Unit ---------
--------------------------------------------------------------------------------------------------  

end DSP;
--------------------------------------------------------------------------------------------------
-- END of DSP architecture -----------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
