--------------------------------------------------------------------------------------------------------
--  Accumulator --                                                                                    --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                  --
--                                                                                                    --
--  Date Modified: 17-11-2019                                                                         --
--------------------------------------------------------------------------------------------------------
--  The accumuator performs a a reduction using addition on three instructions. KVRED, KDOTP, and     --
--  KDOTPPS. Eacj SIMD configuration has it's own accumulator, repllicating the dsp will also         --
--  replicate the accumulator as well.                                                                --
--------------------------------------------------------------------------------------------------------


-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

entity ACCUMULATOR is
    generic(
      multithreaded_accl_en : natural;
      SIMD                  : natural;
      --------------------------------
      ACCL_NUM              : natural;
      FU_NUM                : natural;
      SIMD_Width            : natural
    );
	port(
      clk_i                             : in  std_logic;
      rst_ni                            : in  std_logic;
      MVTYPE_DSP                        : in  std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
      accum_stage_1_en                  : in  std_logic_vector(ACCL_NUM-1 downto 0);
      accum_stage_2_en                  : in  std_logic_vector(ACCL_NUM-1 downto 0);
      recover_state_wires               : in  std_logic_vector(ACCL_NUM-1 downto 0);
      halt_dsp_lat                      : in  std_logic_vector(ACCL_NUM-1 downto 0);
      state_DSP                         : in  std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
      decoded_instruction_DSP_lat       : in  std_logic_vector(((ACCL_NUM)*(DSP_UNIT_INSTR_SET_SIZE))-1 downto 0);
      dsp_in_accum_operands             : in  std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
      dsp_out_accum_results             : out std_logic_vector(((FU_NUM)*(32))-1 downto 0)
	);
end entity;
architecture ACCUM_STG of ACCUMULATOR is
  
  subtype accl_range is integer range ACCL_NUM-1 downto 0;
  subtype fu_range   is integer range FU_NUM-1 downto 0;

  signal accum_partial_results_stg_1 : std_logic_vector(((FU_NUM)*(128))-1 downto 0);
  signal accum_results       : std_logic_vector(((FU_NUM)*(32))-1 downto 0);
begin

  -- The accumulator for the DSP unit written below for all SIMD widths

  ACCUM_replicated : for f in fu_range generate

  ACCUM_SIMD_1 : if SIMD=1 generate
    fsm_ACCUM_STAGE : process(clk_i, rst_ni)
      variable h : integer;
    begin
      if rst_ni = '0' then
        accum_partial_results_stg_1((f+1)*128 -1 downto f*128) <= (others => '0');
        accum_results(((f+1)*(32))-1 downto 32*f) <= (others => '0');
      elsif rising_edge(clk_i) then
        accum_results(((f+1)*(32))-1 downto 32*f) <= (others => '0');
        for g in 0 to (ACCL_NUM - FU_NUM) loop
          if multithreaded_accl_en = 1 then
            h := g;  -- set the spm rd/wr ports equal to the "for-loop"
          elsif multithreaded_accl_en = 0 then
            h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
          end if;
          if state_DSP(((h+1)*(2))-1 downto 2*h) = dsp_exec then
              if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1'  or -- acccumulate 32-bit types
                  decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1'  or
                  decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1') and
                  MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "10" then
                if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_partial_results_stg_1(31  + (f)*(128) downto  0 + (f)*(128))  <= dsp_in_accum_operands(31  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width));
                end if;
                if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(31  + (f)*(128) downto  0 + (f)*(128))) +
                                                            unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));
                end if;
              elsif (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1'  or  -- acccumulate 8-bit and 16-bit types
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1'  or 
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1') and
                    (MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" or MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00") then
                if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_partial_results_stg_1(15  + (f)*(128) downto  0 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(15  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width)))   + unsigned(dsp_in_accum_operands(31   + (f)*(SIMD_Width) downto  16 + (f)*(SIMD_Width))));
                end if;
                if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(15  + (f)*(128) downto  0 + (f)*(128)))  + 
                                                            unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));                
                end if;
              end if;
          end if;
        end loop;
      end if;
    end process;
  end generate ACCUM_SIMD_1;

  ACCUM_SIMD_2 : if SIMD=2 generate
    fsm_ACCUM_STAGE : process(clk_i, rst_ni)
      variable h : integer;
    begin
      if rst_ni = '0' then
        accum_partial_results_stg_1((f+1)*128 -1 downto f*128) <= (others => '0');
        accum_results(((f+1)*(32))-1 downto 32*f) <= (others => '0');
      elsif rising_edge(clk_i) then
        accum_results(((f+1)*(32))-1 downto 32*f) <= (others => '0');
        for g in 0 to (ACCL_NUM - FU_NUM) loop
          if multithreaded_accl_en = 1 then
            h := g;  -- set the spm rd/wr ports equal to the "for-loop"
          elsif multithreaded_accl_en = 0 then
            h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
          end if;
          if state_DSP(((h+1)*(2))-1 downto 2*h) = dsp_exec then
              if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1'  or -- acccumulate 32-bit types
                  decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1'  or
                  decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1') and
                  MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "10" then
                if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_partial_results_stg_1(31  + (f)*(128) downto  0 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(31  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width)))  + unsigned(dsp_in_accum_operands(63   + (f)*(SIMD_Width) downto  32 + (f)*(SIMD_Width))));
                end if;
                if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(31  + (f)*(128) downto  0 + (f)*(128))) +
                                                            unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));
                end if;
              elsif (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)    = '1'  or  -- acccumulate 8-bit and 16-bit types
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position)  = '1'  or 
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)    = '1') and
                    (MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" or MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00") then
                if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_partial_results_stg_1(15  + (f)*(128) downto  0 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(15  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width)))   + unsigned(dsp_in_accum_operands(31   + (f)*(SIMD_Width) downto  16 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(31  + (f)*(128) downto  16 + (f)*(128)) <= std_logic_vector(unsigned(dsp_in_accum_operands(47  + (f)*(SIMD_Width) downto  32 + (f)*(SIMD_Width)))  + unsigned(dsp_in_accum_operands(63  + (f)*(SIMD_Width) downto  48 + (f)*(SIMD_Width))));
                end if;
                if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(15  + (f)*(128) downto  0 + (f)*(128)))  + 
                                                            unsigned(accum_partial_results_stg_1(31  + (f)*(128) downto  16 + (f)*(128))) +
                                                            unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));                
                end if;
              end if;
          end if;
        end loop;
      end if;
    end process; 
  end generate ACCUM_SIMD_2;

  ACCUM_SIMD_4 : if SIMD=4 generate
    fsm_ACCUM_STAGE : process(clk_i, rst_ni)
      variable h : integer;
    begin
      if rst_ni = '0' then
        accum_partial_results_stg_1((f+1)*128 -1 downto f*128) <= (others => '0');
      elsif rising_edge(clk_i) then
        accum_results(((f+1)*(32))-1 downto 32*f) <= (others => '0');
        for g in 0 to (ACCL_NUM - FU_NUM) loop
          if multithreaded_accl_en = 1 then
            h := g;  -- set the spm rd/wr ports equal to the "for-loop"
          elsif multithreaded_accl_en = 0 then
            h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
          end if;
          if state_DSP(((h+1)*(2))-1 downto 2*h) = dsp_exec then
            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1'  or -- acccumulate 32-bit types
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1') and
                MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "10" then
                if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_partial_results_stg_1(31  + (f)*(128) downto  0 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(31  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width)))  + unsigned(dsp_in_accum_operands(63   + (f)*(SIMD_Width) downto  32 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(63  + (f)*(128) downto  32 + (f)*(128)) <= std_logic_vector(unsigned(dsp_in_accum_operands(95  + (f)*(SIMD_Width) downto  64 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(127  + (f)*(SIMD_Width) downto  96 + (f)*(SIMD_Width))));
                end if;
                if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(31  + (f)*(128) downto  0 + (f)*(128))) + 
                                                            unsigned(accum_partial_results_stg_1(63  + (f)*(128) downto  32 + (f)*(128))) +
                                                            unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));
                end if;
              elsif (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)    = '1'  or  -- acccumulate 8-bit and 16-bit types
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position)  = '1'  or 
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)    = '1') and
                    (MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" or MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00") then
                if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_partial_results_stg_1(15  + (f)*(128) downto  0 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(15  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width)))   + unsigned(dsp_in_accum_operands(31   + (f)*(SIMD_Width) downto  16 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(31  + (f)*(128) downto  16 + (f)*(128)) <= std_logic_vector(unsigned(dsp_in_accum_operands(47  + (f)*(SIMD_Width) downto  32 + (f)*(SIMD_Width)))  + unsigned(dsp_in_accum_operands(63  + (f)*(SIMD_Width) downto  48 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(47  + (f)*(128) downto  32 + (f)*(128)) <= std_logic_vector(unsigned(dsp_in_accum_operands(79  + (f)*(SIMD_Width) downto  64 + (f)*(SIMD_Width)))  + unsigned(dsp_in_accum_operands(95  + (f)*(SIMD_Width) downto  80 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(63  + (f)*(128) downto  48 + (f)*(128)) <= std_logic_vector(unsigned(dsp_in_accum_operands(111  + (f)*(SIMD_Width) downto  96 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(127  + (f)*(SIMD_Width) downto  112 + (f)*(SIMD_Width))));
                end if;
                if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(15  + (f)*(128) downto  0 + (f)*(128)))  + 
                                                            unsigned(accum_partial_results_stg_1(31  + (f)*(128) downto  16 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(47  + (f)*(128) downto  32 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(63  + (f)*(128) downto  48 + (f)*(128))) +
                                                            unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));                
                end if;
              end if;
          end if;
        end loop;
      end if;
    end process;
  end generate ACCUM_SIMD_4;

  ACCUM_SIMD_8 : if SIMD=8 generate
    fsm_ACCUM_STAGE : process(clk_i, rst_ni)
      variable h : integer;
    begin
      if rst_ni = '0' then
        accum_results((f+1)*32 -1 downto 32*f) <= (others => '0');
        accum_partial_results_stg_1((f+1)*128 -1 downto f*128) <= (others => '0');
      elsif rising_edge(clk_i) then
        accum_results(((f+1)*(32))-1 downto 32*f) <= (others => '0');
        for g in 0 to (ACCL_NUM - FU_NUM) loop
          if multithreaded_accl_en = 1 then
            h := g;  -- set the spm rd/wr ports equal to the "for-loop"
          elsif multithreaded_accl_en = 0 then
            h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
          end if;
          if state_DSP(((h+1)*(2))-1 downto 2*h) = dsp_exec then
            if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)   = '1'  or -- acccumulate 32-bit types
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1'  or
                decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)   = '1') and
                MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "10" then
              if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                accum_partial_results_stg_1(31  + (f)*(128) downto  0 + (f)*(128))   <= std_logic_vector(unsigned(dsp_in_accum_operands(31  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width)))  + unsigned(dsp_in_accum_operands(63   + (f)*(SIMD_Width) downto  32 + (f)*(SIMD_Width))));
                accum_partial_results_stg_1(63  + (f)*(128) downto  32 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(95  + (f)*(SIMD_Width) downto  64 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(127  + (f)*(SIMD_Width) downto  96 + (f)*(SIMD_Width))));
                accum_partial_results_stg_1(95  + (f)*(128) downto  64 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(159  + (f)*(SIMD_Width) downto  128 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(191  + (f)*(SIMD_Width) downto  160 + (f)*(SIMD_Width))));
                accum_partial_results_stg_1(127  + (f)*(128) downto  96 + (f)*(128)) <= std_logic_vector(unsigned(dsp_in_accum_operands(223  + (f)*(SIMD_Width) downto  192 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(255  + (f)*(SIMD_Width) downto  224 + (f)*(SIMD_Width))));
              end if;
              if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(31   + (f)*(128) downto  0 + (f)*(128)))  + 
                                                          unsigned(accum_partial_results_stg_1(63   + (f)*(128) downto  32 + (f)*(128))) +
                                                          unsigned(accum_partial_results_stg_1(95   + (f)*(128) downto  64 + (f)*(128))) +
                                                          unsigned(accum_partial_results_stg_1(127  + (f)*(128) downto  96 + (f)*(128))) +
                                                          unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));
              end if;
              elsif (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTP_bit_position)    = '1'  or  -- acccumulate 8-bit and 16-bit types
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position)  = '1'  or
                     decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KVRED_bit_position)    = '1') and
                    (MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" or MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00") then
                if (accum_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_partial_results_stg_1(15  + (f)*(128) downto  0 + (f)*(128))    <= std_logic_vector(unsigned(dsp_in_accum_operands(15  + (f)*(SIMD_Width) downto  0 + (f)*(SIMD_Width)))    + unsigned(dsp_in_accum_operands(31   + (f)*(SIMD_Width) downto  16 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(31  + (f)*(128) downto  16 + (f)*(128))   <= std_logic_vector(unsigned(dsp_in_accum_operands(47  + (f)*(SIMD_Width) downto  32 + (f)*(SIMD_Width)))   + unsigned(dsp_in_accum_operands(63  + (f)*(SIMD_Width) downto  48 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(47  + (f)*(128) downto  32 + (f)*(128))   <= std_logic_vector(unsigned(dsp_in_accum_operands(79  + (f)*(SIMD_Width) downto  64 + (f)*(SIMD_Width)))   + unsigned(dsp_in_accum_operands(95  + (f)*(SIMD_Width) downto  80 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(63  + (f)*(128) downto  48 + (f)*(128))   <= std_logic_vector(unsigned(dsp_in_accum_operands(111  + (f)*(SIMD_Width) downto  96 + (f)*(SIMD_Width)))  + unsigned(dsp_in_accum_operands(127  + (f)*(SIMD_Width) downto  112 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(79  + (f)*(128) downto  64 + (f)*(128))   <= std_logic_vector(unsigned(dsp_in_accum_operands(143  + (f)*(SIMD_Width) downto  128 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(159  + (f)*(SIMD_Width) downto  144 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(95  + (f)*(128) downto  80 + (f)*(128))   <= std_logic_vector(unsigned(dsp_in_accum_operands(175  + (f)*(SIMD_Width) downto  160 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(191  + (f)*(SIMD_Width) downto  176 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(111  + (f)*(128) downto  96 + (f)*(128))  <= std_logic_vector(unsigned(dsp_in_accum_operands(207  + (f)*(SIMD_Width) downto  192 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(223  + (f)*(SIMD_Width) downto  208 + (f)*(SIMD_Width))));
                  accum_partial_results_stg_1(127  + (f)*(128) downto  112 + (f)*(128)) <= std_logic_vector(unsigned(dsp_in_accum_operands(239  + (f)*(SIMD_Width) downto  224 + (f)*(SIMD_Width))) + unsigned(dsp_in_accum_operands(255  + (f)*(SIMD_Width) downto  240 + (f)*(SIMD_Width))));
                end if;
                if (accum_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
                  accum_results(((f+1)*(32))-1 downto 32*f) <= std_logic_vector(unsigned(accum_partial_results_stg_1(15   + (f)*(128) downto  0 + (f)*(128)))  + 
                                                            unsigned(accum_partial_results_stg_1(31   + (f)*(128) downto  16 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(47   + (f)*(128) downto  32 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(63   + (f)*(128) downto  48 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(79   + (f)*(128) downto  64 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(95   + (f)*(128) downto  80 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(111  + (f)*(128) downto  96 + (f)*(128))) +
                                                            unsigned(accum_partial_results_stg_1(127  + (f)*(128) downto  112 + (f)*(128))) +
                                                            unsigned(accum_results(((f+1)*(32))-1 downto 32*f)));                
                end if;
              end if;
          end if;
        end loop;
      end if;
    end process;
  end generate ACCUM_SIMD_8;

  end generate ACCUM_replicated;

  out_sig: process(all) begin
    dsp_out_accum_results <= accum_results;
  end process out_sig;

------------------------------------------------------------------------ end of ACCUM Unit -------
--------------------------------------------------------------------------------------------------  

end ACCUM_STG;
--------------------------------------------------------------------------------------------------
-- END of ACCUM Unit architecture ----------------------------------------------------------------
--------------------------------------------------------------------------------------------------
