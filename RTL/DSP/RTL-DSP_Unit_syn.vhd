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
use IEEE.math_real.all;

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
    MVSIZE                     : in  std_logic_vector(((THREAD_POOL_SIZE)*(Addr_Width + 1))-1 downto 0);
    MVTYPE                     : in  std_logic_vector(((THREAD_POOL_SIZE)*(4))-1 downto 0);
    MPSCLFAC                   : in  std_logic_vector(((THREAD_POOL_SIZE)*(5))-1 downto 0);
    dsp_except_data            : out std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
  -- Program Counter Signals
    dsp_taken_branch           : out std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_except_condition       : out std_logic_vector(ACCL_NUM-1 downto 0);
    -- ID_Stage Signals
    decoded_instruction_DSP    : in  std_logic_vector(DSP_UNIT_INSTR_SET_SIZE-1 downto 0);
--  harc_EXEC                  : in  integer range THREAD_POOL_SIZE-1 downto 0;
    harc_EXEC                  : in  std_logic_vector(natural(ceil(log2(real(THREAD_POOL_SIZE))))-1 downto 0);
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
    dsp_sc_data_read           : in  std_logic_vector(((ACCL_NUM)*(2)*(SIMD_Width))-1 downto 0);
    dsp_we_word                : out std_logic_vector(((ACCL_NUM)*(SIMD))-1 downto 0);
    dsp_sc_read_addr           : out std_logic_vector(((ACCL_NUM)*(2)*(Addr_Width))-1 downto 0);
    dsp_to_sc                  : out std_logic_vector(((ACCL_NUM)*(SPM_NUM)*(2))-1 downto 0);
    dsp_sc_data_write_wire     : out std_logic_vector(((ACCL_NUM)*(SIMD_Width))-1 downto 0);
    dsp_sc_write_addr          : out std_logic_vector(((ACCL_NUM)*(Addr_Width))-1 downto 0);
    dsp_sci_we                 : out std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
    dsp_sci_req                : out std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
    -- tracer signals
    state_DSP                  : out std_logic_vector(((ACCL_NUM)*(2))-1 downto 0)

  );
end entity;  ------------------------------------------


architecture DSP of DSP_Unit is

  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;
  subtype accl_range is integer range ACCL_NUM-1 downto 0;
  subtype fu_range   is integer range FU_NUM-1 downto 0;

  --outputs
  signal dsp_except_data_out            : std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
  signal state_DSP_out                  : std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
  signal dsp_sc_write_addr_out          : std_logic_vector(((ACCL_NUM)*(Addr_Width))-1 downto 0);
  signal dsp_sci_we_out                 :  std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);

  signal dsp_sci_req_exc_out                :  std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
  signal dsp_to_sc_exc_out                  :  std_logic_vector(((ACCL_NUM)*(SPM_NUM)*(2))-1 downto 0);
  signal dsp_sc_read_addr_exc_out           :  std_logic_vector(((ACCL_NUM)*(2)*(Addr_Width))-1 downto 0);
  signal nextstate_DSP_exc_out : std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
  signal busy_excp_hand: std_logic_vector(ACCL_NUM-1 downto 0);

  signal nextstate_DSP : std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);

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
  signal fu_req                          : std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);
  signal fu_gnt                          : std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);
  signal fu_gnt_wire                     : std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);
  signal fu_gnt_en                       : std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);
  signal fu_rd_ptr                       : std_logic_vector(((5)*(TPS_BUF_CEIL))-1 downto 0);
  signal fu_wr_ptr                       : std_logic_vector(((5)*(TPS_BUF_CEIL))-1 downto 0);
  -- five buffers for each FU times the "TPS-1" and not "TPS" since there is always one thread active, and not needing a buffer. Each buffer hold the thread_ID "TPS_CEIL"
  signal fu_issue_buffer                 : std_logic_vector(((5)*(THREAD_POOL_SIZE)*(TPS_CEIL))-1 downto 0);

  -- Functional Unit Ports ---
  --signal dsp_in_sign_bits               : std_logic_vector(((ACCL_NUM)*(4*SIMD))-1 downto 0);
  signal dsp_in_shifter_operand          : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_out_shifter_results         : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_in_cmp_operands             : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_in_mul_operands             : std_logic_vector(((FU_NUM)*(2)*(SIMD_Width))-1 downto 0);
  signal dsp_out_mul_results             : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_out_cmp_results             : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_in_accum_operands           : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_out_accum_results           : std_logic_vector(((FU_NUM)*(32))-1 downto 0);
  signal dsp_in_adder_operands           : std_logic_vector(((FU_NUM)*(2)*(SIMD_Width))-1 downto 0);
  signal dsp_out_adder_results           : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);

  signal carry_8_wire                    : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal carry_16_wire                   : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal carry_16                        : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal carry_24_wire                   : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal dsp_add_8_0                     : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_16_8                    : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_8_0_wire                : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_16_8_wire               : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_24_16_wire              : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_32_24_wire              : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal mul_tmp_a                       : std_logic_vector(((FU_NUM)*(SIMD)*(Data_Width))-1 downto 0);
  signal mul_tmp_b                       : std_logic_vector(((FU_NUM)*(SIMD)*(Data_Width))-1 downto 0);
  signal mul_tmp_c                       : std_logic_vector(((FU_NUM)*(SIMD)*(Data_Width))-1 downto 0);
  signal mul_tmp_d                       : std_logic_vector(((FU_NUM)*(SIMD)*(Data_Width))-1 downto 0);
  signal dsp_mul_a                       : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_mul_b                       : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_mul_c                       : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_mul_d                       : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);

  signal carry_pass                      : std_logic_vector(((ACCL_NUM)*(3))-1 downto 0);
  signal FUNCT_SELECT_MASK               : std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
  signal twos_complement                 : std_logic_vector(((ACCL_NUM)*(64))-1 downto 0);
  signal dsp_shift_enabler               : std_logic_vector(((ACCL_NUM)*(16))-1 downto 0);
  signal dsp_in_shift_amount             : std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);

  signal dsp_sc_data_write_wire_int      : std_logic_vector(((ACCL_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_sc_data_write_int           : std_logic_vector(((ACCL_NUM)*(SIMD_Width))-1 downto 0);

  signal MVTYPE_DSP                      : std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
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
  signal dsp_except_data_wire            : std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
  signal MSB_stage_1                     : std_logic_vector(((ACCL_NUM)*(2)*(4*SIMD))-1 downto 0);
  signal MSB_stage_2                     : std_logic_vector(((ACCL_NUM)*(2)*(4*SIMD))-1 downto 0);

  signal decoded_instruction_DSP_lat     : std_logic_vector(((ACCL_NUM)*(DSP_UNIT_INSTR_SET_SIZE))-1 downto 0);
  signal dsp_rs1_to_sc                   : std_logic_vector(((ACCL_NUM)*(SPM_ADDR_WID))-1 downto 0);
  signal dsp_rs2_to_sc                   : std_logic_vector(((ACCL_NUM)*(SPM_ADDR_WID))-1 downto 0);
  signal dsp_rd_to_sc                    : std_logic_vector(((ACCL_NUM)*(SPM_ADDR_WID))-1 downto 0);
  signal dsp_sc_data_read_mask           : std_logic_vector(((ACCL_NUM)*(SIMD_Width))-1 downto 0);
  signal RS1_Data_IE_lat                 : std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
  signal RS2_Data_IE_lat                 : std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
  signal RD_Data_IE_lat                  : std_logic_vector(((ACCL_NUM)*(Addr_Width))-1 downto 0);
  signal MVSIZE_READ                     : std_logic_vector(((ACCL_NUM)*(Addr_Width + 1))-1 downto 0);
  signal MVSIZE_READ_MASK                : std_logic_vector(((ACCL_NUM)*(Addr_Width + 1))-1 downto 0);
  signal MVSIZE_WRITE                    : std_logic_vector(((ACCL_NUM)*(Addr_Width + 1))-1 downto 0);
  signal MPSCLFAC_DSP                    : std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);
  signal busy_dsp_internal               : std_logic_vector(accl_range);
  signal busy_DSP_internal_lat           : std_logic_vector(accl_range);
  signal rf_rs2                          : std_logic_vector(accl_range);
  signal relu_instr                      : std_logic_vector(accl_range);
  signal SIMD_RD_BYTES_wire              : std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
  signal SIMD_RD_BYTES                   : std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
--  signal SIMD_RD_BYTES_wire              : std_logic_vector(((accl_range))-1 downto 0);
--  signal SIMD_RD_BYTES                   : std_logic_vector(((accl_range))-1 downto 0);
  
--  signal MVTYPE_exec                     : std_logic_vector(1 downto 0);
--  signal MVSIZE_exec                     : std_logic_vector(Addr_Width downto 0);
--  signal SIMD_RD_BYTES_exec                : std_logic_vector(31 downto 0);

--  signal harc_EXEC_nat                   : natural range THREAD_POOL_SIZE-1 downto 0;

component EXCPT_HANDLING is
  generic(
    ACCL_NUM              : natural;
    SPM_ADDR_WID          : natural;
    THREAD_POOL_SIZE      : natural;
    Addr_Width            : natural;
    SPM_NUM               : natural 
  );
  port(
    rs1_to_sc                  : in  std_logic_vector(SPM_ADDR_WID-1 downto 0);
    rs2_to_sc                  : in  std_logic_vector(SPM_ADDR_WID-1 downto 0);
    rd_to_sc                   : in  std_logic_vector(SPM_ADDR_WID-1 downto 0);
    MVSIZE                     : in  std_logic_vector(((THREAD_POOL_SIZE)*(Addr_Width + 1))-1 downto 0);
    harc_EXEC                  : in  std_logic_vector(natural(ceil(log2(real(THREAD_POOL_SIZE))))-1 downto 0);
    MVTYPE                     : in  std_logic_vector(((THREAD_POOL_SIZE)*(4))-1 downto 0);
    vec_read_rs1_ID            : in  std_logic;
    vec_write_rd_ID            : in  std_logic;
    spm_rs1                    : in  std_logic;
    spm_rs2                    : in  std_logic;
    halt_hart                  : in std_logic_vector(ACCL_NUM-1 downto 0); -- halts the thread when the requested functional unit is in use
    RS1_Data_IE                : in  std_logic_vector(31 downto 0);
    RS2_Data_IE                : in  std_logic_vector(31 downto 0);
    RD_Data_IE                 : in  std_logic_vector(Addr_Width -1 downto 0);
    vec_read_rs2_ID            : in  std_logic;
  dsp_except_data_in            : in std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);

    state_DSP                  : in std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
    dsp_instr_req              : in  std_logic_vector(ACCL_NUM-1 downto 0);
  busy_DSP_internal_lat           : in std_logic_vector(accl_range);

  dsp_except_data_wire            : out std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
    dsp_taken_branch           : out std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_except_condition       : out std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_sci_req                : out std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
    dsp_to_sc                  : out std_logic_vector(((ACCL_NUM)*(SPM_NUM)*(2))-1 downto 0);
    dsp_sc_read_addr           : out std_logic_vector(((ACCL_NUM)*(2)*(Addr_Width))-1 downto 0);
  nextstate_DSP : out std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
  busy_excp_hand : out std_logic_vector(ACCL_NUM-1 downto 0)
  );
end component EXCPT_HANDLING;


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
    MVTYPE_DSP                      : in std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
    decoded_instruction_DSP_lat     : in std_logic_vector(((ACCL_NUM)*(DSP_UNIT_INSTR_SET_SIZE))-1 downto 0);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(accl_range);
    -- inputs from DSP_FU_Handler
    shift_en                        : in std_logic_vector(accl_range);  -- enables the use of the shifters
    -- inputs from DSP_Mapping
    dsp_in_shifter_operand          : in std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
    dsp_in_shift_amount             : in std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);

    --outputs for DSP_Mapping
    dsp_out_shifter_results         : out std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0)
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
    MVTYPE_DSP                      : in std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
    relu_instr                      : in std_logic_vector(accl_range);
    -- inputs from DSP_pipeline_controller
    halt_dsp_lat                    : in std_logic_vector(accl_range);
    cmp_stage_1_en                  : in std_logic_vector(accl_range);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(accl_range);
    -- inputs from DSP_FU_Handler
    cmp_en                          : in std_logic_vector(accl_range);  -- enables the use of the shifters
    -- inputs from DSP_Mapping
    dsp_in_cmp_operands             : in std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
    -- inputs from adders
    MSB_stage_2                     : in std_logic_vector(((ACCL_NUM)*(2)*(4*SIMD))-1 downto 0);
  
    -- outputs for DSP_Mapping
    dsp_out_cmp_results             : out std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0)
  );
end component COMPARATOR;

  component ADDER is
  generic (
    multithreaded_accl_en : natural;
    SIMD                  : natural;  
    --------------------------------
    ACCL_NUM              : natural;
    FU_NUM                : natural;
    SIMD_Width            : natural
  );
  port(
    -- Core Signals
    clk_i, rst_ni                 : in std_logic;
    -- inputs from DSP_pipeline_controller
    halt_dsp_lat                    : in std_logic_vector(ACCL_NUM-1 downto 0);
    adder_stage_1_en                : in std_logic_vector(ACCL_NUM-1 downto 0); -- enables the use of the adders in stage 1
    adder_stage_2_en                : in std_logic_vector(ACCL_NUM-1 downto 0); -- enables the use of the adders in stage 2
    -- inputs from DSP_Exec_Unit
    carry_pass                      : in std_logic_vector(((ACCL_NUM)*(3))-1 downto 0);
    twos_complement                 : in std_logic_vector(((ACCL_NUM)*(64))-1 downto 0);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(ACCL_NUM-1 downto 0); -- used to recover the state of the DSP, in case of an exception
    -- inputs from DSP_FU_Handler
    add_en                          : in std_logic_vector(ACCL_NUM-1 downto 0);  -- enables the use of the adders
    -- inputs from DSP_Mapping
    MSB_stage_1                     : in std_logic_vector(((ACCL_NUM)*(2)*(4*SIMD))-1 downto 0);
    dsp_in_adder_operands           : in std_logic_vector(((FU_NUM)*(2)*(SIMD_Width))-1 downto 0);
   
    -- outputs for DSP_Mapping
    dsp_out_adder_results           : out std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
    -- outputs for comparator
    MSB_stage_2                     : out std_logic_vector(((ACCL_NUM)*(2)*(4*SIMD))-1 downto 0)
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
      FUNCT_SELECT_MASK                 : in std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
      MVTYPE_DSP                        : in  std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
      recover_state_wires               : in  std_logic_vector(ACCL_NUM-1 downto 0);
      halt_dsp_lat                      : in  std_logic_vector(ACCL_NUM-1 downto 0);
      mul_stage_1_en                    : in std_logic_vector(ACCL_NUM - 1 downto 0);
      mul_stage_2_en                    : in std_logic_vector(ACCL_NUM - 1 downto 0);
      mul_en                            : in std_logic_vector(ACCL_NUM - 1 downto 0);  -- enables the use of the multipliers
      dsp_in_mul_operands               : in std_logic_vector(((FU_NUM)*(2)*(SIMD_Width))-1 downto 0);
      dsp_out_mul_results               : out std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0)
  );
  end component MULTIPLIER;

  component ACCUMULATOR
    generic(
      multithreaded_accl_en             : natural;
      SIMD                              : natural;
      ---------------------------------------------------------
      ACCL_NUM                          : natural;
      FU_NUM                            : natural;
      SIMD_Width                        : natural
    );
  port(
      clk_i                             : in  std_logic;
      rst_ni                            : in  std_logic;
      MVTYPE_DSP                        : in  std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
      accum_stage_1_en                  : in  std_logic_vector(accl_range);
      accum_stage_2_en                  : in  std_logic_vector(accl_range);
      recover_state_wires               : in  std_logic_vector(accl_range);
      halt_dsp_lat                      : in  std_logic_vector(accl_range);
      state_DSP                         : in  std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
      decoded_instruction_DSP_lat       : in  std_logic_vector(((ACCL_NUM)*(DSP_UNIT_INSTR_SET_SIZE))-1 downto 0);
      dsp_in_accum_operands             : in  std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
      dsp_out_accum_results             : out std_logic_vector(((FU_NUM)*(32))-1 downto 0)
  );
  end component;

--------------------------------------------------------------------------------------------------
-------------------------------- DSP BEGIN -------------------------------------------------------
begin


  busy_dsp <= busy_dsp_internal;
  --busy_dsp <= busy_dsp_internal or busy_excp_hand;

  DSP_replicated : for h in accl_range generate


  ------------ Sequential Stage of DSP Unit -------------------------------------------------------------------------
  DSP_Exec_Unit : process(clk_i, rst_ni)  -- single cycle unit, fully synchronous 
  variable dsp_sc_data_read_mask_tmp : std_logic_vector((SIMD_Width)-1 downto 0);
  variable harc_EXEC_nat: integer;
  variable MVTYPE_exec: std_logic_vector(1 downto 0);
  variable MVSIZE_exec: std_logic_vector(Addr_Width downto 0);
  begin
  harc_EXEC_nat := to_integer(unsigned(harc_EXEC));

  MVTYPE_exec := MVTYPE(3  + (harc_EXEC_nat)*(4) downto  2 + (harc_EXEC_nat)*(4));
  MVSIZE_exec := MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));
    if rst_ni = '0' then
      relu_instr(h) <= '0';
      rf_rs2(h)     <= '0';
      dotpps(h)     <= '0';
      dotp(h)       <= '0';
      slt(h)        <= '0';
      recover_state(h) <= '0';
      MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= (others => '0');
      MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= (others => '0');
      MPSCLFAC_DSP(((h+1)*(5))-1 downto (5)*(h)) <= (others => '0');
      MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) <= (others => '0');
      decoded_instruction_DSP_lat(((h+1)*(DSP_UNIT_INSTR_SET_SIZE))-1 downto (DSP_UNIT_INSTR_SET_SIZE)*(h)) <= (others => '0');
      RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= (others => '0');
      RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= (others => '0');
      RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= (others => '0');
      dsp_sc_data_read_mask(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= (others => '0');
      dsp_sc_data_write_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= (others => '0');
      MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= (others => '0');
      FUNCT_SELECT_MASK(((h+1)*(32))-1 downto (32)*(h)) <= (others => '0');
      twos_complement(((h+1)*(64))-1 downto (64)*(h)) <= (others => '0');
      dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)) <= (others => '0');
      dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)) <= (others => '0');
      dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)) <= (others => '0');
      vec_read_rs1_DSP(h) <= '0';
      vec_read_rs2_DSP(h) <= '0';
      vec_write_rd_DSP(h) <= '0';
      carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= (others => '0');
    elsif rising_edge(clk_i) then
      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then  

        if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_init then

            -------------------------------------------------------------
            --  ██╗███╗   ██╗██╗████████╗    ██████╗ ███████╗██████╗   --
            --  ██║████╗  ██║██║╚══██╔══╝    ██╔══██╗██╔════╝██╔══██╗  --
            --  ██║██╔██╗ ██║██║   ██║       ██║  ██║███████╗██████╔╝  --
            --  ██║██║╚██╗██║██║   ██║       ██║  ██║╚════██║██╔═══╝   --
            --  ██║██║ ╚████║██║   ██║       ██████╔╝███████║██║       --
            --  ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝       ╚═════╝ ╚══════╝╚═╝       -- 
            -------------------------------------------------------------

            FUNCT_SELECT_MASK(((h+1)*(32))-1 downto (32)*(h)) <= (others => '0');
            twos_complement(((h+1)*(64))-1 downto (64)*(h))   <= (others => '0');
            relu_instr(h) <= '0';
            rf_rs2(h)     <= '0';
            dotpps(h)     <= '0';
            dotp(h)       <= '0';
            slt(h)        <= '0';
            -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP(KADDV_bit_position)    = '1'  or 
                decoded_instruction_DSP(KSVADDSC_bit_position) = '1') and
                MVTYPE_exec = "10" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "111";
                -- pass all carry_outs
            elsif decoded_instruction_DSP(KSVADDRF_bit_position) = '1' and 
                  MVTYPE_exec = "10" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "111"; 
               -- pass all carry_outs
              rf_rs2(h) <= '1';
            elsif (decoded_instruction_DSP(KADDV_bit_position)    = '1'  or
                   decoded_instruction_DSP(KSVADDSC_bit_position) = '1') and
                  MVTYPE_exec = "01" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "101"; 
               -- pass carrries 9, and 25
            elsif decoded_instruction_DSP(KSVADDRF_bit_position) = '1' and
                 MVTYPE_exec = "01" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "101"; 
               -- pass carrries 9, and 25
              rf_rs2(h) <= '1';
            elsif (decoded_instruction_DSP(KADDV_bit_position)     = '1'  or
                   decoded_instruction_DSP(KSVADDSC_bit_position)  = '1') and
                  MVTYPE_exec = "00" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "000"; 
               -- don't pass carry_outs and keep addition 8-bit
            elsif decoded_instruction_DSP(KSVADDRF_bit_position)  = '1' and 
                 MVTYPE_exec = "00" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "000"; 
               -- don't pass carry_outs and keep addition 8-bit
              rf_rs2(h) <= '1';
            elsif (decoded_instruction_DSP(KSUBV_bit_position)  = '1') and
                  MVTYPE_exec = "10" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "111";
                -- pass all carry_outs
              twos_complement(((h+1)*(64))-1 downto (64)*(h)) <= "0001000100010001000100010001000100010001000100010001000100010001";
            elsif (decoded_instruction_DSP(KSUBV_bit_position)  = '1') and
                  MVTYPE_exec = "01" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "101"; 
               -- pass carrries 9, and 25
              twos_complement(((h+1)*(64))-1 downto (64)*(h)) <= "0101010101010101010101010101010101010101010101010101010101010101";
            elsif (decoded_instruction_DSP(KSUBV_bit_position)  = '1') and
                  MVTYPE_exec = "00" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "000";
                -- don't pass carry_outs and keep addition 8-bit
              twos_complement(((h+1)*(64))-1 downto (64)*(h)) <= "1111111111111111111111111111111111111111111111111111111111111111";
            elsif (decoded_instruction_DSP(KVSLT_bit_position)  = '1'  or
                   decoded_instruction_DSP(KSVSLT_bit_position) = '1') and
                  MVTYPE_exec = "10" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "111";  -- pass all carry_outs
              twos_complement(((h+1)*(64))-1 downto (64)*(h)) <= "0001000100010001000100010001000100010001000100010001000100010001";
              slt(h) <= '1';
            elsif (decoded_instruction_DSP(KVSLT_bit_position)  = '1'  or
                   decoded_instruction_DSP(KSVSLT_bit_position) = '1') and
                  MVTYPE_exec = "01" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "101"; 
               -- pass carrries 9, and 25
              twos_complement(((h+1)*(64))-1 downto (64)*(h)) <= "0101010101010101010101010101010101010101010101010101010101010101";
              slt(h) <= '1';
            elsif (decoded_instruction_DSP(KVSLT_bit_position)  = '1'  or
                   decoded_instruction_DSP(KSVSLT_bit_position) = '1') and
                  MVTYPE_exec = "00" then
              carry_pass(((h+1)*(3))-1 downto (3)*(h)) <= "000";  -- don't pass carry_outs and keep addition 8-bit
              twos_complement(((h+1)*(64))-1 downto (64)*(h)) <= "1111111111111111111111111111111111111111111111111111111111111111";
              slt(h) <= '1';
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' and
                 MVTYPE_exec = "10" then
              -- KDOTP32 does not use the adders of KADDV instructions but rather adds the mul_acc results using it's own adders
              FUNCT_SELECT_MASK(((h+1)*(32))-1 downto (32)*(h)) <= (others => '1'); 
               -- This enables 32-bit multiplication with the 16-bit multipliers
              dotp(h) <= '1';
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' and 
                 MVTYPE_exec = "01" then
              dotp(h) <= '1';
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' and
                 MVTYPE_exec = "00" then
              dotp(h) <= '1';
            elsif decoded_instruction_DSP(KDOTPPS_bit_position) = '1' and
                 MVTYPE_exec = "10" then
              FUNCT_SELECT_MASK(((h+1)*(32))-1 downto (32)*(h)) <= (others => '1'); 
               -- This enables 32-bit multiplication with the 16-bit multipliers
              dotpps(h) <= '1';
            elsif decoded_instruction_DSP(KDOTPPS_bit_position) = '1' and
                 MVTYPE_exec = "01" then
              dotpps(h) <= '1';
            elsif decoded_instruction_DSP(KDOTPPS_bit_position)  = '1' and 
                 MVTYPE_exec = "00" then
              dotpps(h) <= '1';
            elsif decoded_instruction_DSP(KSVMULRF_bit_position) = '1' and
                 MVTYPE_exec = "10" then
              FUNCT_SELECT_MASK(((h+1)*(32))-1 downto (32)*(h)) <= (others => '1');
              rf_rs2(h) <= '1';
            elsif decoded_instruction_DSP(KSVMULRF_bit_position) = '1' and
                 MVTYPE_exec = "01" then
              rf_rs2(h) <= '1';
            elsif decoded_instruction_DSP(KSVMULRF_bit_position)  = '1' and
                 MVTYPE_exec = "00" then
              rf_rs2(h)  <= '1';
            elsif (decoded_instruction_DSP(KVMUL_bit_position)    = '1'  or
                   decoded_instruction_DSP(KSVMULSC_bit_position) = '1') and
                  MVTYPE_exec = "10" then
              FUNCT_SELECT_MASK(((h+1)*(32))-1 downto (32)*(h)) <= (others => '1');
            elsif decoded_instruction_DSP(KRELU_bit_position) = '1' then
              relu_instr(h) <= '1';
            end if;

           -- We backup data from decode stage since they will get updated

            MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));
            MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));
            MPSCLFAC_DSP(((h+1)*(5))-1 downto (5)*(h)) <= MPSCLFAC(((harc_EXEC_nat+1)*(5))-1 downto (5)*(harc_EXEC_nat));
            MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) <= MVTYPE(3  + (harc_EXEC_nat)*(4) downto  2 + (harc_EXEC_nat)*(4));
            decoded_instruction_DSP_lat(((h+1)*(DSP_UNIT_INSTR_SET_SIZE))-1 downto (DSP_UNIT_INSTR_SET_SIZE)*(h))  <= decoded_instruction_DSP;
            vec_write_rd_DSP(h) <= vec_write_rd_ID;
            vec_read_rs1_DSP(h) <= vec_read_rs1_ID;
            vec_read_rs2_DSP(h) <= vec_read_rs2_ID;
            dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)) <= rs1_to_sc;
            dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)) <= rs2_to_sc;
            dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))  <= rd_to_sc;
            RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE;
            -- Increment the read addresses
            if dsp_data_gnt_i(h) = '1' then
              if vec_read_rs1_ID = '1' then
                RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(resize(unsigned(RS1_Data_IE) + unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h))'length)); 
                -- source 1 address increment
              else
                RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= RS1_Data_IE;
              end if;
              if vec_read_rs2_ID = '1' then
                RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(resize(unsigned(RS2_Data_IE) + unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h))'length)); 
              -- source 2 address increment
              else
                RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= RS2_Data_IE;
              end if;
              -- Decrement the vector elements that have already been operated on
              if unsigned(MVSIZE_exec) >= unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))) then
                MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= std_logic_vector(resize(unsigned(MVSIZE_exec) - unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))'length)); 
               -- decrement by SIMD_BYTE Execution Capability
              else
                MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= (others => '0');                                                     -- decrement the remaining bytes
              end if;
              --report "Thread " & integer'image(h) & " MVSIZE_READ after decrement: " & integer'image(to_integer(unsigned(MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)))));
            else
              RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= RS1_Data_IE;
              RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= RS2_Data_IE;
              MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));
            end if;
            -------------------------------------------------------------------------------

          elsif state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_exec then
            recover_state(h) <= recover_state_wires(h);
            if halt_dsp(h) = '1' and halt_dsp_lat(h) = '0' then
              dsp_sc_data_write_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
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
                RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h))  <= std_logic_vector(resize(unsigned(RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h))) + unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h))'length)); -- destination address increment
              end if;
              if wb_ready(h) = '1' then
                if to_integer(unsigned(MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)))) then
                  MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= std_logic_vector(resize(unsigned(MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))) - unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))'length));
                else
                  MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= (others => '0');                                                -- decrement the remaining bytes
                end if;
              end if;
              -- Increment the read addresses
              if to_integer(unsigned(MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)))) and dsp_data_gnt_i(h) = '1' then -- Increment the addresses untill all the vector elements are operated fetched
                if vec_read_rs1_DSP(h) = '1' then
                  RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(resize(unsigned(RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h))) + unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h))'length));
                end if;
                if vec_read_rs2_DSP(h) = '1' then
                  RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(resize(unsigned(RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h))) + unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), RS2_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h))'length));
                end if;
              end if;
              -- Decrement the vector elements that have already been operated on
              if dsp_data_gnt_i(h) = '1' then
                if to_integer(unsigned(MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)))) then
                  MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= std_logic_vector(resize(unsigned(MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))) - unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))'length));
                else
                  MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= (others => '0');                                               -- decrement the remaining bytes
                end if;
              end if;
              if dsp_data_gnt_i_lat(h) = '1' then
                if to_integer(unsigned(MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)))) >= to_integer(unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)))) then
                  dsp_sc_data_read_mask(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= (others => '1');
                  MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= std_logic_vector(resize(unsigned(MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))) - unsigned(SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))), MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))'length)); -- decrement by SIMD_BYTE Execution Capability 
                else
                  MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= (others => '0');
                  dsp_sc_data_read_mask_tmp := (others => '0');
                  for i in 0 to (SIMD_Width)-1 loop
                    if i < to_integer(unsigned(MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))))*8 then
                      dsp_sc_data_read_mask_tmp(i) := '1';
                    else
                      dsp_sc_data_read_mask_tmp(i) := '0';
                    end if;
                  end loop;
                  dsp_sc_data_read_mask(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= dsp_sc_data_read_mask_tmp;
                 -- for i in 0 to (SIMD_Width)-1 loop
                 --   if i < to_integer(unsigned(MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))))*8 then
                 --     dsp_sc_data_read_mask(i + (h)*(SIMD_Width)) <= '1';
                 --   else
                 --     dsp_sc_data_read_mask(i + (h)*(SIMD_Width)) <= '0';
                 --   end if;
                 -- end loop;
                  --dsp_sc_data_read_mask(to_integer(unsigned(MVSIZE_READ_MASK(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))))*8 - 1  + (h)*(SIMD_Width) downto  0 + (h)*(SIMD_Width)) <= (others => '1');
                end if;
              else
                dsp_sc_data_read_mask(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= (others => '0');
              end if;
            end if;

        end if;
      end if;
    end if;
  end process;

  ------------ Combinational Stage of DSP Unit ----------------------------------------------------------------------
  DSP_Excpt_Cntrl_Unit_comb : process(all)
  
  variable busy_DSP_internal_wires : std_logic_vector(accl_range);
  variable harc_EXEC_nat : integer;
  variable MVTYPE_exec: std_logic_vector(1 downto 0);
  variable MVSIZE_exec: std_logic_vector(Addr_Width downto 0);
  variable dsp_sci_req_lat                : std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
  variable dsp_to_sc_lat                  : std_logic_vector(((ACCL_NUM)*(SPM_NUM)*(2))-1 downto 0);

  variable dsp_we_word_lat                : std_logic_vector(((ACCL_NUM)*(SIMD))-1 downto 0);
  variable dsp_sci_we_lat                 :  std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
      
  begin
  harc_EXEC_nat := to_integer(unsigned(harc_EXEC));

  MVTYPE_exec := MVTYPE(3  + (harc_EXEC_nat)*(4) downto  2 + (harc_EXEC_nat)*(4));
  MVSIZE_exec := MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));

    busy_DSP_internal_wires(h)        := '0';
    wb_ready(h)                    <= '0';
    halt_dsp(h)                    <= '0';
    nextstate_DSP(((h+1)*(2))-1 downto (2)*(h))               <= dsp_init;
    recover_state_wires(h)         <= recover_state(h);
    dsp_we_word_lat(((h+1)*(SIMD))-1 downto (SIMD)*(h))                 := (others => '0');
    dsp_sci_req_lat(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h))                 := (others => '0');
    dsp_to_sc_lat((((h)+1)*(SPM_NUM)*(2))-1 downto (SPM_NUM)*(2)*((h)))                   := (others => '0');
    dsp_sci_we_lat(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h))                  := (others => '0');
    dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h))           <= (others => '0');
    dsp_sc_read_addr((((h)+1)*(2)*(Addr_Width))-1 downto (2)*(Addr_Width)*((h)))            <= (others => '0');
    busy_DSP_internal(h)                    <= '0';

    if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
      if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_init then
          dsp_sci_req_lat(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h)) := dsp_sci_req_exc_out(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h));
          dsp_to_sc_lat((((h)+1)*(SPM_NUM)*(2))-1 downto (SPM_NUM)*(2)*((h))) := dsp_to_sc_exc_out((((h)+1)*(SPM_NUM)*(2))-1 downto (SPM_NUM)*(2)*((h)));
          dsp_sc_read_addr((((h)+1)*(2)*(Addr_Width))-1 downto (2)*(Addr_Width)*((h))) <= dsp_sc_read_addr_exc_out((((h)+1)*(2)*(Addr_Width))-1 downto (2)*(Addr_Width)*((h)));

          nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= nextstate_DSP_exc_out(((h+1)*(2))-1 downto (2)*(h));
        
         elsif state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_halt_hart then 

           if halt_hart(h) = '0' then
             nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
           else
             nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_halt_hart;
           end if;
           busy_DSP_internal_wires(h) := '1';

         elsif state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_exec then

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
           elsif unsigned(MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))) <= unsigned(SIMD_RD_BYTES(((h+1)*(32))-1 downto (32)*(h))) then
             recover_state_wires(h) <= '0';
           end if;

           if vec_write_rd_DSP(h) = '1' and  dsp_sci_we_out((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) = '1' then
             if unsigned(MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))) >= (SIMD)*4+1 then  -- 
               dsp_we_word_lat(((h+1)*(SIMD))-1 downto (SIMD)*(h)) := (others => '1');
             elsif  unsigned(MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))) >= 1 then
               for i in 0 to SIMD-1 loop
                 if i <= to_integer(unsigned(MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)))-1)/4 then -- Four because of the number of bytes per word
                   if to_integer(unsigned(dsp_sc_write_addr_out(SIMD_BITS+1  + (h)*(Addr_Width) downto  0 + (h)*(Addr_Width)))/4 + i) < SIMD then
                     dsp_we_word_lat(to_integer(unsigned(dsp_sc_write_addr_out(SIMD_BITS+1  + (h)*(Addr_Width) downto   0 + (h)*(Addr_Width)))/4 + i) + (h)*(SIMD)) := '1';
                   elsif to_integer(unsigned(dsp_sc_write_addr_out(SIMD_BITS+1  + (h)*(Addr_Width) downto  0 + (h)*(Addr_Width)))/4 + i) >= SIMD then
                     dsp_we_word_lat(to_integer(unsigned(dsp_sc_write_addr_out(SIMD_BITS+1  + (h)*(Addr_Width) downto   0 + (h)*(Addr_Width)))/4 + i - SIMD) + (h)*(SIMD)) := '1';
                   end if;
                 end if;
               end loop;
             end if;
           elsif vec_write_rd_DSP(h) = '0' and  dsp_sci_we_out((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) = '1' then
             dsp_we_word_lat(to_integer(unsigned(dsp_sc_write_addr_out(SIMD_BITS+1  + (h)*(Addr_Width) downto   0 + (h)*(Addr_Width)))/4) + (h)*(SIMD)) := '1';
           end if;
           -------------------------------------------------------------------------------------------------------------------------


           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KBCAST_bit_position)  = '1' then
             -- KBCAST signals are handeled here
             if MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             wb_ready(h) <= '1';
             dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
             dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
           end if;

           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVCP_bit_position)  = '1' then
             -- KVCP signals are handeled here
             if adder_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width)) <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
             end if;
             if MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;

           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KRELU_bit_position) = '1' then
             -- KRELU signals are handeled here
             if cmp_stage_2_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width)) <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
             end if;
             if MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;

           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVSLT_bit_position)  = '1' then
             -- KADDV and KSUBV signals are handeled here
             if cmp_stage_2_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 1) := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width))  <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
               dsp_sc_read_addr(((1+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(1) + (h)*(2)*(Addr_Width))  <= RS2_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
             end if;
             if MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;

           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVSLT_bit_position) = '1' then
             -- KADDV and KSUBV signals are handeled here
             if cmp_stage_2_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width))  <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
             end if;
             if MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;

           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRAV_bit_position)  = '1' or
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRLV_bit_position)  = '1' then
             -- KSRAV signals are handeled here
             if shifter_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width))  <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
             end if;
             if MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;

           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KADDV_bit_position)  = '1' or
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSUBV_bit_position)  = '1' then
             -- KADDV and KSUBV signals are handeled here
             if adder_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 1) := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))  := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width))  <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
               dsp_sc_read_addr(((1+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(1) + (h)*(2)*(Addr_Width))  <= RS2_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
             end if;
             if MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))    := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;
    
           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1' or
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1' or
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1' then
             -- KDOTP signals are handeled here
             if accum_stage_3_en(h) = '1' then
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';  
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               if vec_read_rs2_DSP(h) = '1' then
                 dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
                 dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 1) := '1';
                 dsp_sc_read_addr(((1+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(1) + (h)*(2)*(Addr_Width))  <= RS2_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
               end if;
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width))  <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             elsif MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) = (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_init;
             else
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))    := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;

           if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1' or 
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1' or 
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1' or 
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDSC_bit_position) = '1' or 
              decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDRF_bit_position) = '1' then
             -- KMUL signals are handeled here
             if mul_stage_3_en(h) = '1' or adder_stage_3_en(h) = '1' then 
               wb_ready(h) <= '1';
             elsif recover_state(h) = '1' then
               wb_ready(h) <= '1';
             end if;
             if MVSIZE_READ(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) > (0 to Addr_Width => '0') then
               dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               if rf_rs2(h) = '0' then -- if the scalar does not come from the regfile
                 dsp_sci_req_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
                 dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs2_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 1) := '1';
                 dsp_sc_read_addr(((1+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(1) + (h)*(2)*(Addr_Width))  <= RS2_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
               end if;
               dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (to_integer(unsigned(dsp_rs1_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h)))))*(2) + 0) := '1';
               dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width))  <= RS1_Data_IE_lat(Addr_Width - 1  + (h)*(32) downto  0 + (h)*(32));
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             elsif MVSIZE_WRITE(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) = (0 to Addr_Width => '0') then
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_init;
             else
               nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
               busy_DSP_internal_wires(h) := '1';
             end if;
             if wb_ready(h) = '1' then
               dsp_sci_we_lat((h)*(SPM_NUM) + to_integer(unsigned(dsp_rd_to_sc(((h+1)*(SPM_ADDR_WID))-1 downto (SPM_ADDR_WID)*(h))))) := '1';
               dsp_sc_write_addr_out(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h)) <= RD_Data_IE_lat(((h+1)*(Addr_Width))-1 downto (Addr_Width)*(h));
             end if;
           end if;
       end if;
     end if;
      
    busy_DSP_internal(h)    <= busy_DSP_internal_wires(h) or busy_excp_hand(h);
    dsp_sci_req(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h)) <= dsp_sci_req_lat(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h));
    dsp_to_sc(((h+1)*(SPM_NUM)*(2))-1 downto (h)*(SPM_NUM)*(2)) <= dsp_to_sc_lat((h+1)*(SPM_NUM)*(2) -1 downto (h)*(SPM_NUM)*(2));
    dsp_we_word(((h+1)*(SIMD))-1 downto (SIMD)*(h)) <= dsp_we_word_lat(((h+1)*(SIMD))-1 downto (SIMD)*(h));

    dsp_sci_we(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h)) <= dsp_sci_we_lat(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h));
    dsp_sci_we_out(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h)) <= dsp_sci_we_lat(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h));
      
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
      state_DSP_out(((h+1)*(2))-1 downto (2)*(h))             <= dsp_init;
      dsp_except_data_out(((h+1)*(32))-1 downto (32)*(h))       <= (others => '0');
      SIMD_RD_BYTES(((h+1)*(32))-1 downto (32)*(h))         <= (others => '0');
      halt_dsp_lat(h)           <= '0';
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
      state_DSP_out(((h+1)*(2))-1 downto (2)*(h))             <= nextstate_DSP(((h+1)*(2))-1 downto (2)*(h));
      busy_DSP_internal_lat(h) <= busy_DSP_internal(h);
      SIMD_RD_BYTES(((h+1)*(32))-1 downto (32)*(h))         <= SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h));
      dsp_except_data_out(((h+1)*(32))-1 downto (32)*(h))       <= dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h));
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

        if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_init then

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
        end if;
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
      fu_req(((h+1)*(5))-1 downto (5)*(h))                      <= (others => '0');
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

        if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_init then

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
                fu_req((h)*(5) + 0) <= '1';
              end if;
            elsif decoded_instruction_DSP(KDOTP_bit_position) = '1' then
              if busy_mul = '0' and busy_acc = '0' and mul_en_pending = (accl_range => '0') and accum_en_pending = (accl_range => '0') then 
                mul_en_wire(h)   <= '1';
                accum_en_wire(h) <= '1';
              else
                mul_en_pending_wire(h)   <= '1';
                accum_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req((h)*(5) + 2) <= '1';
                fu_req((h)*(5) + 3) <= '1';
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
                fu_req((h)*(5) + 2) <= '1';
                fu_req((h)*(5) + 1) <= '1';
                fu_req((h)*(5) + 3) <= '1';
              end if;
            elsif decoded_instruction_DSP(KVRED_bit_position) = '1' then
              if busy_acc = '0' and accum_en_pending = (accl_range => '0') then 
                accum_en_wire(h) <= '1';
              else
                accum_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req((h)*(5) + 3) <= '1';
              end if;
            elsif decoded_instruction_DSP(KSVMULRF_bit_position) = '1' or
                  decoded_instruction_DSP(KSVMULSC_bit_position) = '1' or
                  decoded_instruction_DSP(KVMUL_bit_position)    = '1' then
              if busy_mul = '0' and mul_en_pending = (accl_range => '0') then 
                mul_en_wire(h) <= '1';
              else
                mul_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req((h)*(5) + 2) <= '1';
              end if;
            elsif decoded_instruction_DSP(KSRAV_bit_position) = '1' or
                  decoded_instruction_DSP(KSRLV_bit_position) = '1' then
              if busy_shf = '0' and shift_en_pending = (accl_range => '0') then 
                shift_en_wire(h) <= '1';
              else
                shift_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req((h)*(5) + 1) <= '1';
              end if;
            elsif decoded_instruction_DSP(KRELU_bit_position) = '1' then
              if busy_cmp = '0' and cmp_en_pending = (accl_range => '0') then 
                cmp_en_wire(h) <= '1';
              else
                cmp_en_pending_wire(h) <= '1';
                halt_hart(h) <= '1';
                fu_req((h)*(5) + 4) <= '1';
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
                fu_req((h)*(5) + 0) <= '1';
                fu_req((h)*(5) + 4) <= '1';
              end if;
            end if;

          elsif state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_halt_hart then
  
            if fu_gnt((h)*(5) + 0) = '1' then
              add_en_wire(h) <= '1';
              add_en_pending_wire(h) <= '0';
            elsif add_en_pending(h) = '1' and fu_gnt((h)*(5) + 0) = '0'  then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt((h)*(5) + 1) = '1' then
              shift_en_wire(h) <= '1';
              shift_en_pending_wire(h) <= '0';
            elsif shift_en_pending(h) = '1' and fu_gnt((h)*(5) + 1) = '0' then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt((h)*(5) + 2) = '1' then
              mul_en_wire(h) <= '1';
              mul_en_pending_wire(h) <= '0';
            elsif mul_en_pending(h) = '1' and fu_gnt((h)*(5) + 2) = '0'  then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt((h)*(5) + 3) = '1' then
              accum_en_wire(h) <= '1';
              accum_en_pending_wire(h) <= '0';
            elsif accum_en_pending(h) = '1' and fu_gnt((h)*(5) + 3) = '0'  then
              halt_hart(h) <= '1';
            end if;

            if fu_gnt((h)*(5) + 4) = '1' then
              cmp_en_wire(h) <= '1';
              cmp_en_pending_wire(h) <= '0';
            elsif cmp_en_pending(h) = '1' and fu_gnt((h)*(5) + 4) = '0'  then
              halt_hart(h) <= '1';
            end if;

        end if;
      end if;
    end loop;
  end process;

  FU_Issue_Buffer_sync : process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      fu_rd_ptr  <= (others => '0');
      fu_wr_ptr  <= (others => '0');
      fu_gnt     <= (others => '0');
    elsif rising_edge(clk_i) then
      fu_gnt <= fu_gnt_wire;
      for h in accl_range loop
        for i in 0 to 4 loop  -- Loop index 'i' is for the total number of different functional units (regardless what SIMD config is set)
          if fu_req((h)*(5) + i) = '1' then  -- if a reservation was made, to use a functional unit
            --to_integer(unsigned(fu_issue_buffer(i)(to_integer(unsigned(fu_wr_ptr(i)))))) <= h;  -- store the thread_ID in its corresponding buffer at the fu_wr_ptr position
            --fu_issue_buffer(to_integer(unsigned(fu_wr_ptr(i))))(i) <= std_logic_vector(unsigned(h));  -- store the thread_ID in its corresponding buffer at the fu_wr_ptr position
            fu_issue_buffer(((to_integer(unsigned(fu_wr_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))))+1)*(TPS_CEIL))-1 + (i)*(THREAD_POOL_SIZE)*(TPS_CEIL) downto (TPS_CEIL)*(to_integer(unsigned(fu_wr_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))))) + (i)*(THREAD_POOL_SIZE)*(TPS_CEIL))  <= std_logic_vector(to_unsigned(h,TPS_CEIL));
            if unsigned(fu_wr_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))) = THREAD_POOL_SIZE - 2 then -- increment the pointer wr logic
              fu_wr_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i)) <= (others => '0');
            else
              fu_wr_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i)) <= std_logic_vector(unsigned(fu_wr_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))) + 1);
            end if;
          end if;
          if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_halt_hart then
              if fu_gnt_en((h)*(5) + i) = '1' then
                if unsigned(fu_rd_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))) = THREAD_POOL_SIZE - 2 then  -- increment the read pointer
                  fu_rd_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i)) <= (others => '0');
                else
                  fu_rd_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i)) <= std_logic_vector(unsigned(fu_rd_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))) + 1);
                end if;
              end if;
          end if;
        end loop;
      end loop;
    end if;
  end process;

  FU_Issue_Buffer_comb : process(all)
  begin
    for h in accl_range loop
      fu_gnt_wire(((h+1)*(5))-1 downto (5)*(h)) <= (others => '0');
      fu_gnt_en(((h+1)*(5))-1 downto (5)*(h))   <= (others => '0');
      if add_en_pending_wire(h) = '1' and busy_add_wire = '0' then
        fu_gnt_en((h)*(5) + 0) <= '1';
      end if;
      if shift_en_pending_wire(h) = '1' and busy_shf_wire = '0' then
        fu_gnt_en((h)*(5) + 1) <= '1';
      end if;
      if mul_en_pending_wire(h) = '1' and busy_mul_wire = '0' then
        fu_gnt_en((h)*(5) + 2) <= '1';
      end if;
      if accum_en_pending_wire(h) = '1' and busy_acc_wire = '0' then
        fu_gnt_en((h)*(5) + 3) <= '1';
      end if;
      if cmp_en_pending_wire(h) = '1' and busy_cmp_wire = '0' then
        fu_gnt_en((h)*(5) + 4) <= '1';
      end if;
      if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_halt_hart then
          for i in 0 to 4 loop 
            if fu_gnt_en((h)*(5) + i) = '1' then
              fu_gnt_wire((to_integer(unsigned(fu_issue_buffer(((to_integer(unsigned(fu_rd_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))))+1)*(TPS_CEIL))-1 + (i)*(THREAD_POOL_SIZE)*(TPS_CEIL) downto (TPS_CEIL)*(to_integer(unsigned(fu_rd_ptr(((i+1)*(TPS_BUF_CEIL))-1 downto (TPS_BUF_CEIL)*(i))))) + (i)*(THREAD_POOL_SIZE)*(TPS_CEIL)))))*(5) + i) <= '1';
               -- give a grant to fu_gnt(h)(i), such that the 'h' index points to the thread in "fu_issue_buffer"
            end if;
          end loop;
      end if;
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
  variable MVTYPE_exec : std_logic_vector(1 downto 0);
  variable harc_EXEC_nat : integer;
  variable dsp_sc_data_write_wire_var : std_logic_vector((ACCL_NUM)*(SIMD_Width)-1 downto 0);
  variable dsp_sc_data_write_wire_int_var : std_logic_vector((ACCL_NUM)*(SIMD_Width)-1 downto 0);
  begin
      harc_EXEC_nat := to_integer(unsigned(harc_EXEC));
      MVTYPE_exec := MVTYPE(3  + (harc_EXEC_nat)*(4) downto  2 + (harc_EXEC_nat)*(4));
      dsp_sc_data_write_wire_int_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h))  := (others => '0');
      dsp_sc_data_write_wire_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h))      := dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
      SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h))          <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8), 32));

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
        if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_init then

            -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP(KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP(KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP(KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP(KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULSC_bit_position) = '1') and 
--              MVTYPE(3  + (h)*(4) downto  2 + (h)*(4)) = "00" then
              MVTYPE_exec = "00" then
              SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

          elsif state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_exec then

           -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
                (MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00") then
              SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1' or 
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1' then
              dsp_sc_data_write_wire_int_var(31  + (h)*(SIMD_Width) downto  0 + (h)*(SIMD_Width)) := dsp_out_accum_results(((h+1)*(32))-1 downto (32)*(h)) ;
               -- AAA add a mask in order to store the lower half word when 16-bit or entire word when 32-bit
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
               MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int_var(7+8*(i)  + (h)*(SIMD_Width) downto  8*(i) + (h)*(SIMD_Width)) := dsp_out_mul_results(7+8*(2*i)  + (h)*(SIMD_Width) downto  8*(2*i) + (h)*(SIMD_Width));
              end loop;
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
               (MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" or  MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10") then
              dsp_sc_data_write_wire_int_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) := dsp_out_mul_results(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRAV_bit_position)   = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRLV_bit_position)   = '1' then
              dsp_sc_data_write_wire_int_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h))  := dsp_out_shifter_results(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDSC_bit_position)   = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDRF_bit_position)   = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KADDV_bit_position)      = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSUBV_bit_position)      = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVCP_bit_position)       = '1' then
              dsp_sc_data_write_wire_int_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) := dsp_out_adder_results(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
            end if;


            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KRELU_bit_position)  = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVSLT_bit_position)  = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVSLT_bit_position) = '1' then
              dsp_sc_data_write_wire_int_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) := dsp_out_cmp_results(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
            end if;

            if    decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KBCAST_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10" then
              for i in 0 to SIMD-1 loop
                dsp_sc_data_write_wire_int_var(31+32*(i)  + (h)*(SIMD_Width) downto  32*(i) + (h)*(SIMD_Width)) := RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h));
              end loop;
            elsif decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KBCAST_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int_var(15+16*(i)  + (h)*(SIMD_Width) downto  16*(i) + (h)*(SIMD_Width)) := RS1_Data_IE_lat(15  + (h)*(32) downto  0 + (h)*(32));
              end loop;
            elsif decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KBCAST_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              for i in 0 to 4*SIMD-1 loop
                dsp_sc_data_write_wire_int_var(7+8*(i)    + (h)*(SIMD_Width) downto  8*(i) + (h)*(SIMD_Width))  := RS1_Data_IE_lat(7  + (h)*(32) downto  0 + (h)*(32));
              end loop;
            end if;

            if halt_dsp(h) = '0' and halt_dsp_lat(h) = '1' then
              dsp_sc_data_write_wire_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) := dsp_sc_data_write_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
            end if;
        end if;
      end if;
      dsp_sc_data_write_wire(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= dsp_sc_data_write_wire_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
      dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h))  <= dsp_sc_data_write_wire_int_var(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
  end process;

end generate;
end generate;

MULTITHREAD_OUT_MAPPER : if multithreaded_accl_en = 1 generate
  MAPPING_OUT_UNIT_comb : process(all)
  begin
    for h in 0 to (ACCL_NUM - FU_NUM) loop
      dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h))  <= (others => '0');
      dsp_sc_data_write_wire(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h))      <= dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
      SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8), 32));

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
        if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_init then

            -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP(KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP(KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP(KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP(KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP(KSVMULSC_bit_position) = '1') and
                MVTYPE(3  + (h)*(4) downto  2 + (h)*(4)) = "00" then
              SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

          elsif state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_exec then

           -- Set signals to enable correct virtual parallelism operation
            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)    = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position)  = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)    = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              SIMD_RD_BYTES_wire(((h+1)*(32))-1 downto (32)*(h)) <= std_logic_vector(to_unsigned(SIMD*(Data_Width/8)/2, 32));
            end if; 

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1' or 
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1' then
              dsp_sc_data_write_wire_int(31  + (h)*(SIMD_Width) downto  0 + (h)*(SIMD_Width)) <= dsp_out_accum_results(((0+1)*(32))-1 downto (32)*(0)) ;
               -- AAA add a mask in order to store the lower half word when 16-bit or entire word when 32-bit
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int(7+8*(i)  + (h)*(SIMD_Width) downto  8*(i) + (h)*(SIMD_Width)) <= dsp_out_mul_results(7+8*(2*i)  + (0)*(SIMD_Width) downto  8*(2*i) + (0)*(SIMD_Width));
              end loop;
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
               (MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" or MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10") then
              dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= dsp_out_mul_results(((0+1)*(SIMD_Width))-1 downto (SIMD_Width)*(0));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRAV_bit_position)   = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRLV_bit_position)   = '1' then
              dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h))  <= dsp_out_shifter_results(((0+1)*(SIMD_Width))-1 downto (SIMD_Width)*(0));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDSC_bit_position)   = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDRF_bit_position)   = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KADDV_bit_position)      = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSUBV_bit_position)      = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVCP_bit_position)        = '1' then
              dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= dsp_out_adder_results(((0+1)*(SIMD_Width))-1 downto (SIMD_Width)*(0));
            end if;


            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KRELU_bit_position)  = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVSLT_bit_position)  = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVSLT_bit_position) = '1' then
              dsp_sc_data_write_wire_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= dsp_out_cmp_results(((0+1)*(SIMD_Width))-1 downto (SIMD_Width)*(0));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KBCAST_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10" then
              for i in 0 to SIMD-1 loop
                dsp_sc_data_write_wire_int(31+32*(i)  + (h)*(SIMD_Width) downto  32*(i) + (h)*(SIMD_Width)) <= RS1_Data_IE_lat(((h+1)*(32))-1 downto (32)*(h));
              end loop;
            elsif decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KBCAST_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" then
              for i in 0 to 2*SIMD-1 loop
                dsp_sc_data_write_wire_int(15+16*(i)  + (h)*(SIMD_Width) downto  16*(i) + (h)*(SIMD_Width)) <= RS1_Data_IE_lat(15  + (h)*(32) downto  0 + (h)*(32));
              end loop;
            elsif decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KBCAST_bit_position)  = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              for i in 0 to 4*SIMD-1 loop
                dsp_sc_data_write_wire_int(7+8*(i)    + (h)*(SIMD_Width) downto  8*(i) + (h)*(SIMD_Width))  <= RS1_Data_IE_lat(7  + (h)*(32) downto  0 + (h)*(32));
              end loop;
            end if;

            if halt_dsp(h) = '0' and halt_dsp_lat(h) = '1' then
              dsp_sc_data_write_wire(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h)) <= dsp_sc_data_write_int(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
            end if;
        end if;
      end if;
    end loop;
  end process;
end generate;

--FU_IN_MAPPER_replicated : for f in accl_range generate
--FU_IN_MAPPER  : if (multithreaded_accl_en = 0 or (multithreaded_accl_en = 1 and f = 0)) generate

FU_replicated : for f in fu_range generate

  DSP_MAPPING_IN_UNIT_comb : process(all)
  variable h : integer;
  variable MSB_stage_1_lat : std_logic_vector((FU_NUM)*(2)*(4*SIMD)-1 downto 0);
  variable dsp_in_adder_operands_lat : std_logic_vector((FU_NUM)*(2)*(SIMD_Width)-1 downto 0);
  variable dsp_in_mul_operands_lat           : std_logic_vector(((FU_NUM)*(2)*(SIMD_Width))-1 downto 0);
  variable dsp_in_shift_amount_lat         : std_logic_vector(((FU_NUM)*(5))-1 downto 0);
  variable dsp_in_shifter_operand_lat         : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  variable dsp_in_accum_operands_lat          : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  variable dsp_in_cmp_operands_lat            : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  begin

    dsp_in_mul_operands_lat(((f+1)*(2)*(SIMD_Width))-1 downto (2)*(SIMD_Width)*((f)))         := (others => '0');
    dsp_in_shift_amount_lat(((f+1)*(5))-1 downto (5)*(f))         := (others => '0');
    dsp_in_shifter_operand_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))      := (others => '0');
    dsp_in_accum_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))       := (others => '0');
    dsp_in_cmp_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))         := (others => '0');

      MSB_stage_1_lat((((f)+1)*(2)*(4*SIMD))-1 downto (2)*(4*SIMD)*((f)))                 := (others => '0'); 
      dsp_in_adder_operands_lat((((f)+1)*(2)*(SIMD_Width))-1 downto (2)*(SIMD_Width)*((f)))       := (others => '0');

    for g in 0 to (ACCL_NUM - FU_NUM) loop

      if multithreaded_accl_en = 1 then
        h := g;  -- set the spm rd/wr ports equal to the "for-loop"
      elsif multithreaded_accl_en = 0 then
        h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
      end if;

      if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
        if state_DSP_out(((h+1)*(2))-1 downto (2)*(h)) = dsp_exec then

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1' or 
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1') and
                MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              for i in 0 to 2*SIMD-1 loop
                  dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width)) := (x"00" & (dsp_sc_data_read(7+8*(i)  + (h)*(2)*(SIMD_Width) + (0)*(SIMD_Width) downto  8*(i) + (h)*(2)*(SIMD_Width) + (0)*(SIMD_Width)) and dsp_sc_data_read_mask(7+8*(i)  + (h)*(SIMD_Width) downto  8*(i) + (h)*(SIMD_Width))));
                  dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := (x"00" & (dsp_sc_data_read(7+8*(i)  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  8*(i) + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) and dsp_sc_data_read_mask(7+8*(i)  + (h)*(SIMD_Width) downto  8*(i) + (h)*(SIMD_Width))));
              end loop;
                if dotp(h) = '1' then
                  dsp_in_accum_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f)) := dsp_out_mul_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
                elsif dotpps(h) = '1' then
                  dsp_in_shift_amount_lat(((f+1)*(5))-1 downto (5)*(f))    := MPSCLFAC_DSP(((h+1)*(5))-1 downto (5)*(h));
                  dsp_in_shifter_operand_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f)) := dsp_out_mul_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
                  dsp_in_accum_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))  := dsp_out_shifter_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
                end if;
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1') and
               (MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" or MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10") then
              dsp_in_mul_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width)) and dsp_sc_data_read_mask(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
              dsp_in_mul_operands_lat(((1+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((1+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (h)*(2)*(SIMD_Width)) and dsp_sc_data_read_mask(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
              if dotp(h) = '1' then
                dsp_in_accum_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))  := dsp_out_mul_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
              elsif dotpps(h) = '1' then
                dsp_in_shift_amount_lat(((f+1)*(5))-1 downto (5)*(f))    := MPSCLFAC_DSP(((h+1)*(5))-1 downto (5)*(h));
                dsp_in_shifter_operand_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f)) := dsp_out_mul_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
                dsp_in_accum_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))  := dsp_out_shifter_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
              end if;
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              for i in 0 to 2*SIMD-1 loop
                if vec_read_rs2_DSP(h) = '0' then
                  if rf_rs2(h) = '1' then
                    dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := x"00" & RS2_Data_IE_lat(7  + (h)*(32) downto  0 + (h)*(32)) ;
                    -- map the scalar value
                  elsif rf_rs2(h) = '0' then
                    dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := x"00" & dsp_sc_data_read(7  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  0 + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) ;
                    -- map the scalar value
                  end if;
                else
                  dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := x"00" & dsp_sc_data_read(7+8*(i)  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  8*(i) + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width));
                end if;
                dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width))  := x"00" & dsp_sc_data_read(7+8*(i)  + (h)*(2)*(SIMD_Width) + (0)*(SIMD_Width) downto  8*(i) + (h)*(2)*(SIMD_Width) + (0)*(SIMD_Width));
              end loop;
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
                MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" then
              if vec_read_rs2_DSP(h) = '0' then
                if rf_rs2(h) = '1' then
                  for i in 0 to 2*SIMD-1 loop
                    dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := RS2_Data_IE_lat(15  + (h)*(32) downto  0 + (h)*(32)) ;
                    -- map the scalar value
                  end loop;
                elsif rf_rs2(h) = '0' then
                  for i in 0 to 2*SIMD-1 loop
                    dsp_in_mul_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := dsp_sc_data_read(15  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  0 + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) ;
                    -- map the scalar value
                  end loop;         
                end if;
              else
                dsp_in_mul_operands_lat(((1+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((1+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (h)*(2)*(SIMD_Width));
              end if;
              dsp_in_mul_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width))     := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
            end if;

            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVMUL_bit_position)    = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULRF_bit_position) = '1'  or  
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVMULSC_bit_position) = '1') and
               MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10" then
              if vec_read_rs2_DSP(h) = '0' then
                if rf_rs2(h) = '1' then
                  for i in 0 to SIMD-1 loop
                    dsp_in_mul_operands_lat(31+32*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  32*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := RS2_Data_IE_lat(31  + (h)*(32) downto  0 + (h)*(32)) ;
                    -- map the scalar value
                  end loop;
                elsif rf_rs2(h) = '0' then
                  for i in 0 to SIMD-1 loop
                    dsp_in_mul_operands_lat(31+32*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  32*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := dsp_sc_data_read(31  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  0 + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) ;
                    -- map the scalar value
                  end loop;
                end if;
              else
                dsp_in_mul_operands_lat(((1+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((1+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (h)*(2)*(SIMD_Width));
              end if;
              dsp_in_mul_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KADDV_bit_position) = '1' then 
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width))   := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              dsp_in_adder_operands_lat(((1+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (f)*(2)*(SIMD_Width))   := dsp_sc_data_read(((1+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (h)*(2)*(SIMD_Width));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRAV_bit_position) = '1' or
               decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRLV_bit_position) = '1' then 
              dsp_in_shifter_operand_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))      := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              dsp_in_shift_amount_lat(((f+1)*(5))-1 downto (5)*(f))         := RS2_Data_IE_lat(4  + (h)*(32) downto  0 + (h)*(32)) ;
              -- map the scalar value (shift amount)
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDSC_bit_position)  = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10" then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width))   := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              for i in 0 to SIMD-1 loop
                dsp_in_adder_operands_lat(31+32*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  32*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))   := dsp_sc_data_read(31  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  0 + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width));
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDSC_bit_position)  = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width))   := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              for i in 0 to 2*SIMD-1 loop
                dsp_in_adder_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))   := dsp_sc_data_read(15  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  0 + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width));
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDSC_bit_position)  = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              for i in 0 to 4*SIMD-1 loop
                dsp_in_adder_operands_lat(7+8*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  8*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := dsp_sc_data_read(7  + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  0 + (h)*(2)*(SIMD_Width) + (1)*(SIMD_Width));
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDRF_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10" then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width))   := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              for i in 0 to SIMD-1 loop
                dsp_in_adder_operands_lat(31+32*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  32*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))   := RS2_Data_IE_lat(31  + (h)*(32) downto  0 + (h)*(32));
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDRF_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width))   := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              for i in 0 to 2*SIMD-1 loop
                dsp_in_adder_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))   := RS2_Data_IE_lat(15  + (h)*(32) downto  0 + (h)*(32));
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVADDRF_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width))   := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              for i in 0 to 4*SIMD-1 loop
                dsp_in_adder_operands_lat(7+8*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  8*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))   := RS2_Data_IE_lat(7  + (h)*(32) downto  0 + (h)*(32));
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSUBV_bit_position)  = '1' then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              dsp_in_adder_operands_lat(((1+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (f)*(2)*(SIMD_Width)) := (not dsp_sc_data_read(((1+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (h)*(2)*(SIMD_Width)));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)  = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
              for i in 0 to 2*SIMD-1 loop
                dsp_in_accum_operands_lat(15+16*(i)  + (f)*(SIMD_Width) downto  16*(i) + (f)*(SIMD_Width)) := x"00" & (dsp_sc_data_read(7+8*(i)  + (h)*(2)*(SIMD_Width) + (0)*(SIMD_Width) downto  8*(i) + (h)*(2)*(SIMD_Width) + (0)*(SIMD_Width)) and dsp_sc_data_read_mask(7+8*(i)  + (h)*(SIMD_Width) downto  8*(i) + (h)*(SIMD_Width)));
              end loop;
            end if;
            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position) = '1' and (MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" or MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10") then
              dsp_in_accum_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width)) and dsp_sc_data_read_mask(((h+1)*(SIMD_Width))-1 downto (SIMD_Width)*(h));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KRELU_bit_position)  = '1' then
              dsp_in_cmp_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVSLT_bit_position) = '1' then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              dsp_in_adder_operands_lat(((1+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (f)*(2)*(SIMD_Width)) := (not dsp_sc_data_read(((1+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(1) + (h)*(2)*(SIMD_Width)));
              dsp_in_cmp_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))      := dsp_out_adder_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
              for i in 0 to 1 loop -- loops through both read busses for operands rs1, and rs2
                for j in 0 to 4*SIMD-1 loop -- loop transfers all the MSBs from the input to the output
                  MSB_stage_1_lat((f)*(2)*(4*SIMD) + (i)*(4*SIMD) + j) := dsp_sc_data_read((h)*(2)*(SIMD_Width) + (i)*(SIMD_Width) + 7+8*(j));
                end loop;
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSVSLT_bit_position) = '1'then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
              dsp_in_cmp_operands_lat(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f))      := dsp_out_adder_results(((f+1)*(SIMD_Width))-1 downto (SIMD_Width)*(f));
              if MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "10" then
                for i in 0 to SIMD-1 loop
                  dsp_in_adder_operands_lat(31+32*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  32*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := not(RS2_Data_IE_lat(31  + (h)*(32) downto  0 + (h)*(32)));
                end loop;
                for j in 0 to SIMD-1 loop -- this index loops throughout the SIMD lanes
                  MSB_stage_1_lat((f)*(2)*(4*SIMD) + (1)*(4*SIMD) + 4*(j)+3) := RS2_Data_IE_lat((h)*(32) + 31) ;
                  -- Save the MSB in an array to be used for comparator results
                end loop;
              elsif MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "01" then
                for i in 0 to 2*SIMD-1 loop
                  dsp_in_adder_operands_lat(15+16*(i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  16*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width)) := not(RS2_Data_IE_lat(15  + (h)*(32) downto  0 + (h)*(32)));
                end loop;
                for i in 0 to 1 loop -- this index loops throughout the MSBs in the 8-bit subwords in the 32-bit word "RS2_Data_IE_lat"
                  for j in 0 to SIMD-1 loop -- this index loops throughout the SIMD lanes
                    MSB_stage_1_lat((f)*(2)*(4*SIMD) + (1)*(4*SIMD) + 4*(j)+1+2*(i)) := RS2_Data_IE_lat((h)*(32) + 15);
                   -- Save the MSB in an array to be used for comparator results
                  end loop;
                end loop;
              elsif MVTYPE_DSP(((h+1)*(2))-1 downto (2)*(h)) = "00" then
                for i in 0 to 4*SIMD-1 loop
                  dsp_in_adder_operands_lat(7+8*(i)    + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  8*(i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))  := not(RS2_Data_IE_lat(7  + (h)*(32) downto  0 + (h)*(32)));
                end loop;
                for i in 0 to 3 loop -- this index loops throughout the MSBs in the 8-bit subwords in the 32-bit word "RS2_Data_IE_lat"
                  for j in 0 to SIMD-1 loop -- this index loops throughout the SIMD lanes
                    MSB_stage_1_lat((f)*(2)*(4*SIMD) + (1)*(4*SIMD) + 4*(j)+i) := RS2_Data_IE_lat((h)*(32) + 7) ;
                  -- Save the MSB in an array to be used for comparator results
                  end loop;
                end loop;
              end if;
              for i in 0 to 4*SIMD-1 loop -- loop transfers all the MSBs from the input to the output
                MSB_stage_1_lat((f)*(2)*(4*SIMD) + (0)*(4*SIMD) + i) := dsp_sc_data_read((h)*(2)*(SIMD_Width) + (0)*(SIMD_Width) + 7+8*(i));
              end loop;
            end if;

            if decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVCP_bit_position) = '1' then
              dsp_in_adder_operands_lat(((0+1)*(SIMD_Width))-1 + (f)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (f)*(2)*(SIMD_Width)) := dsp_sc_data_read(((0+1)*(SIMD_Width))-1 + (h)*(2)*(SIMD_Width) downto (SIMD_Width)*(0) + (h)*(2)*(SIMD_Width));
            end if;

        end if;
      end if;
    end loop;
    MSB_stage_1((f+1)*(2)*(4*SIMD)-1 downto (f)*(2)*(4*SIMD)) <= MSB_stage_1_lat((f+1)*(2)*(4*SIMD)-1 downto (f)*(2)*(4*SIMD));
    dsp_in_adder_operands(((f+1)*(2)*(SIMD_Width))-1 downto (f)*(2)*(SIMD_Width)) <= dsp_in_adder_operands_lat(((f+1)*(2)*(SIMD_Width))-1 downto (f)*(2)*(SIMD_Width));
    dsp_in_mul_operands(((f+1)*(2)*(SIMD_Width))-1 downto (f)*(2)*(SIMD_Width)) <= dsp_in_mul_operands_lat(((f+1)*(2)*(SIMD_Width))-1 downto (f)*(2)*(SIMD_Width));
    dsp_in_cmp_operands(((f+1)*(SIMD_Width))-1 downto (f)*(SIMD_Width)) <= dsp_in_cmp_operands_lat(((f+1)*(SIMD_Width))-1 downto (f)*(SIMD_Width));
    dsp_in_shifter_operand(((f+1)*(SIMD_Width))-1 downto (f)*(SIMD_Width)) <= dsp_in_shifter_operand_lat(((f+1)*(SIMD_Width))-1 downto (f)*(SIMD_Width));
    dsp_in_shift_amount(((f+1)*(5))-1 downto (f)*(5)) <= dsp_in_shift_amount_lat(((f+1)*(5))-1 downto (f)*(5));
    dsp_in_accum_operands(((f+1)*(SIMD_Width))-1 downto (f)*(SIMD_Width)) <= dsp_in_accum_operands_lat(((f+1)*(SIMD_Width))-1 downto (f)*(SIMD_Width));
--  end generate;
  end process;

--end generate;
--end generate;

--FU_IN_MAPPER  : if (multithreaded_accl_en = 0 or (multithreaded_accl_en = 1 and f = 0) generate

end generate FU_replicated;
  
-- Exception Handling
EXCP_STG: EXCPT_HANDLING
  generic map(
    ACCL_NUM              => ACCL_NUM,
    SPM_ADDR_WID        => SPM_ADDR_WID,
    THREAD_POOL_SIZE     => THREAD_POOL_SIZE,
    Addr_Width            => Addr_Width,
    SPM_NUM               => SPM_NUM
  )
  port map(
    rs1_to_sc            => rs1_to_sc,
    rs2_to_sc            => rs2_to_sc,
    rd_to_sc             => rd_to_sc,
    MVSIZE               => MVSIZE,
    harc_EXEC            => harc_EXEC,
    MVTYPE               => MVTYPE,
    vec_read_rs1_ID      => vec_read_rs1_ID,
    vec_write_rd_ID      => vec_write_rd_ID,
    spm_rs1              => spm_rs1,
    spm_rs2              => spm_rs2,
    halt_hart            => halt_hart,

    RS1_Data_IE         => RS1_Data_IE,
    RS2_Data_IE         => RS2_Data_IE,
    RD_Data_IE          => RD_Data_IE,
    vec_read_rs2_ID      => vec_read_rs2_ID,
    dsp_except_data_in => dsp_except_data_out,

    state_DSP           => state_DSP_out,
    dsp_instr_req       => dsp_instr_req,
    busy_DSP_internal_lat => busy_DSP_internal_lat,

    dsp_except_data_wire => dsp_except_data_wire,
    dsp_taken_branch     => dsp_taken_branch,
    dsp_except_condition => dsp_except_condition,
    dsp_sci_req          => dsp_sci_req_exc_out,
    dsp_to_sc            => dsp_to_sc_exc_out,
    dsp_sc_read_addr     => dsp_sc_read_addr_exc_out,
    nextstate_DSP        => nextstate_DSP_exc_out,
    busy_excp_hand       => busy_excp_hand
  );

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
      SIMD_Width            => SIMD_Width
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
      state_DSP                         => state_DSP_out,
      decoded_instruction_DSP_lat       => decoded_instruction_DSP_lat,
      dsp_in_accum_operands             => dsp_in_accum_operands,
      dsp_out_accum_results             => dsp_out_accum_results
  );


------------------------------------------------------------------------ end of DSP Unit ---------
--------------------------------------------------------------------------------------------------  

-- outputs and general assigns
gen_assigns: process(all)
--variable harc_EXEC_nat : integer;
begin
  dsp_except_data   <= dsp_except_data_out;
  state_DSP         <= state_DSP_out;
  dsp_sc_write_addr <= dsp_sc_write_addr_out;

 -- harc_EXEC_nat := to_integer(unsigned(harc_EXEC));

 -- MVTYPE_exec := MVTYPE(3  + (harc_EXEC_nat)*(4) downto  2 + (harc_EXEC_nat)*(4));
 -- MVSIZE_exec := MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));

  --SIMD_RD_BYTES_exec <= SIMD_RD_BYTES((harc_EXEC_nat+1)*(32)-1 downto (harc_EXEC_nat)*(32));
end process;

end DSP;
--------------------------------------------------------------------------------------------------
-- END of DSP architecture -----------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
