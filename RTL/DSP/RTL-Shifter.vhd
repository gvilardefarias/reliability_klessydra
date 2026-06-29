
-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

entity SHIFTER is
  generic(
    multithreaded_accl_en : natural;
    SIMD                  : natural;
    --------------------------------
    ACCL_NUM              : natural;
    FU_NUM                : natural;
    Data_Width            : natural;
    SIMD_Width            : natural
  );
  port(
    -- Core Signals
    clk_i, rst_ni                   : in std_logic;
    -- inputs from DSP_pipeline_controller
    shifter_stage_1_en              : in std_logic_vector(ACCL_NUM - 1 downto 0);
    shifter_stage_2_en              : in std_logic_vector(ACCL_NUM - 1 downto 0);
    halt_dsp_lat                    : in std_logic_vector(ACCL_NUM - 1 downto 0);
    -- inputs from DSP_Exec_Unit
    MVTYPE_DSP                      : in array_2d(ACCL_NUM - 1 downto 0)(1 downto 0);
    decoded_instruction_DSP_lat     : in array_2d(ACCL_NUM - 1 downto 0)(DSP_UNIT_INSTR_SET_SIZE -1 downto 0);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(ACCL_NUM - 1 downto 0);
    -- inputs from DSP_FU_Handler
    shift_en                        : in std_logic_vector(ACCL_NUM - 1 downto 0);  -- enables the use of the shifters
    -- inputs from DSP_Mapping
    dsp_in_shifter_operand          : in array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
    dsp_in_shift_amount             : in array_2d(ACCL_NUM - 1 downto 0)(4 downto 0);

    --outputs for DSP_Mapping
    dsp_out_shifter_results         : out array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0)
  );
end entity SHIFTER;

architecture SHIF_STG of SHIFTER is

  subtype accl_range is integer range ACCL_NUM - 1 downto 0;
  subtype fu_range   is integer range FU_NUM - 1 downto 0;

  signal dsp_int_shifter_operand         : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_in_shifter_operand_lat      : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);  -- 15 bits because i only want to latch the signed bits
  signal dsp_in_shifter_operand_lat_wire : array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
  signal dsp_shift_enabler               : array_2d(ACCL_NUM-1 downto 0)(15 downto 0);
begin


  SHIF_replicated : for f in fu_range generate
  ------------------------------------------------------------------------------------------------------------
  --  ███████╗██╗  ██╗██╗███████╗████████╗███████╗██████╗ ███████╗    ███████╗████████╗ ██████╗        ██╗  --
  --  ██╔════╝██║  ██║██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝    ██╔════╝╚══██╔══╝██╔════╝       ███║  --
  --  ███████╗███████║██║█████╗     ██║   █████╗  ██████╔╝███████╗    ███████╗   ██║   ██║  ███╗█████╗╚██║  --
  --  ╚════██║██╔══██║██║██╔══╝     ██║   ██╔══╝  ██╔══██╗╚════██║    ╚════██║   ██║   ██║   ██║╚════╝ ██║  --
  --  ███████║██║  ██║██║██║        ██║   ███████╗██║  ██║███████║    ███████║   ██║   ╚██████╔╝       ██║  --
  --  ╚══════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝    ╚══════╝   ╚═╝    ╚═════╝        ╚═╝  --
  ------------------------------------------------------------------------------------------------------------

  fsm_DSP_shifter_stg_1 : process(clk_i, rst_ni)
  variable h : integer;
  begin
    if rst_ni = '0' then
    elsif rising_edge(clk_i) then
      for g in 0 to (ACCL_NUM - FU_NUM) loop
        if multithreaded_accl_en = 1 then
          h := g;  -- set the spm rd/wr ports equal to the "for-loop"
        elsif multithreaded_accl_en = 0 then
          h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
        end if;
        if shift_en(h) = '1' and (shifter_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
          for i in 0 to SIMD-1 loop
            dsp_int_shifter_operand(f)(31+32*(i) downto 32*(i)) <= to_stdlogicvector(to_bitvector(dsp_in_shifter_operand(f)(31+32*(i) downto 32*(i))) srl to_integer(unsigned(dsp_in_shift_amount(f))));
          end loop;
          --for i in 0 to 4*SIMD-1 loop -- latch the sign bits
            --dsp_in_sign_bits(f)(i) <= dsp_in_shifter_operand(f)(7+8*(i));
          --end loop;
          if MVTYPE_DSP(h) = "00" then
            for i in 0 to 4*SIMD-1 loop -- latch the sign bits
              dsp_in_shifter_operand_lat(f)(7+8*i downto 8*i) <= (others => dsp_in_shifter_operand(f)(7+8*i));
            end loop;
          elsif MVTYPE_DSP(h) = "01" then
            for i in 0 to 2*SIMD-1 loop -- latch the sign bits
              for bit_idx in 0 to 15 loop
                dsp_in_shifter_operand_lat(f)(16*i + bit_idx) <= dsp_in_shifter_operand(f)(15+16*i);
              end loop;
              --dsp_in_shifter_operand_lat(f)(15+16*i downto 16*i) <= (others => dsp_in_shifter_operand(f)(15+16*i));
            end loop;
          elsif MVTYPE_DSP(h) = "10" then
            for i in 0 to SIMD-1 loop -- latch the sign bits
              for bit_idx in 0 to 31 loop
                dsp_in_shifter_operand_lat(f)(32*i + bit_idx) <= dsp_in_shifter_operand(f)(31+32*i);
              end loop;
--              dsp_in_shifter_operand_lat(f)(31+32*i downto 32*i) <= (others => dsp_in_shifter_operand(f)(31+32*i));
            end loop;
          end if;
        end if;
      end loop;
    end if;
  end process;

  ----------------------------------------------------------------------------------------------------------------
  --  ███████╗██╗  ██╗██╗███████╗████████╗███████╗██████╗ ███████╗    ███████╗████████╗ ██████╗       ██████╗   --
  --  ██╔════╝██║  ██║██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝    ██╔════╝╚══██╔══╝██╔════╝       ╚════██╗  --
  --  ███████╗███████║██║█████╗     ██║   █████╗  ██████╔╝███████╗    ███████╗   ██║   ██║  ███╗█████╗ █████╔╝  --
  --  ╚════██║██╔══██║██║██╔══╝     ██║   ██╔══╝  ██╔══██╗╚════██║    ╚════██║   ██║   ██║   ██║╚════╝██╔═══╝   --
  --  ███████║██║  ██║██║██║        ██║   ███████╗██║  ██║███████║    ███████║   ██║   ╚██████╔╝      ███████╗  --
  --  ╚══════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝    ╚══════╝   ╚═╝    ╚═════╝       ╚══════╝  --
  ----------------------------------------------------------------------------------------------------------------

  fsm_DSP_shifter_stg_2 : process(clk_i, rst_ni)
  variable h : integer;
  begin
    if rst_ni = '0' then
    elsif rising_edge(clk_i) then
      for g in 0 to (ACCL_NUM - FU_NUM) loop
        if multithreaded_accl_en = 1 then
          h := g;  -- set the spm rd/wr ports equal to the "for-loop"
        elsif multithreaded_accl_en = 0 then
          h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
        end if;
        if shift_en(h) = '1' and (shifter_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
          if    MVTYPE_DSP(h) = "10" then
            for i in 0 to SIMD-1 loop
              dsp_out_shifter_results(f)(31+32*(i) downto 32*(i)) <= dsp_in_shifter_operand_lat_wire(f)(31 +32*(i) downto 32*(i)) or dsp_int_shifter_operand(f)(31+32*(i) downto 32*(i));
            end loop;
          elsif MVTYPE_DSP(h) = "01" or (decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1' and MVTYPE_DSP(h) = "00") then -- KDOTPPS8 has been added here because the number of elements loaded for mul operations is equal for 8-bit and 16-bits instr
            for i in 0 to 2*SIMD-1 loop
              dsp_out_shifter_results(f)(15+16*(i) downto 16*(i)) <=  dsp_in_shifter_operand_lat_wire(f)(15 +16*(i) downto 16*(i)) or (dsp_int_shifter_operand(f)(15+16*(i) downto 16*(i)) and dsp_shift_enabler(h)(15 downto 0));
            end loop;
          elsif MVTYPE_DSP(h) = "00" then
            for i in 0 to 4*SIMD-1 loop
              dsp_out_shifter_results(f)(7+8*(i) downto 8*(i)) <=  dsp_in_shifter_operand_lat_wire(f)(7 +8*(i) downto 8*(i)) or  (dsp_int_shifter_operand(f)(7+8*(i) downto 8*(i)) and dsp_shift_enabler(h)(7 downto 0));
            end loop;
          end if;
        end if;
      end loop;
    end if;
  end process;

  fsm_DSP_shifter_comb : process(all)
  variable h : integer;
  begin
    dsp_in_shifter_operand_lat_wire(f) <= (others => '0');
    for g in 0 to (ACCL_NUM - FU_NUM) loop
      if multithreaded_accl_en = 1 then
        h := g;  -- set the spm rd/wr ports equal to the "for-loop"
      elsif multithreaded_accl_en = 0 then
        h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
      end if;
      dsp_shift_enabler(h) <= (others => '0');
      if shift_en(h) = '1' and halt_dsp_lat(h) = '0' then
        if MVTYPE_DSP(h) = "01" then
          for idx in 0 to (15 - to_integer(unsigned(dsp_in_shift_amount(h)(3 downto 0)))) loop
            dsp_shift_enabler(h)(idx) <= '1';
          end loop;
          --dsp_shift_enabler(h)(15 - to_integer(unsigned(dsp_in_shift_amount(h)(3 downto 0))) downto 0) <= (others => '1');
        elsif MVTYPE_DSP(h) = "00" then
          -- TODO do the same thing as for 16b
          dsp_shift_enabler(h)(7 -  to_integer(unsigned(dsp_in_shift_amount(h)(2 downto 0))) downto 0) <= (others => '1');
        end if;
        if (decoded_instruction_DSP_lat(h)(KSRAV_bit_position) = '1' or decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1') and
            MVTYPE_DSP(h) = "10" then    -- 32-bit sign extension for for srl in stage 1
          for i in 0 to SIMD-1 loop
            --dsp_in_shifter_operand_lat(f)(31+32*(i) downto 31 - to_integer(unsigned(dsp_in_shift_amount(h)(4 downto 0)))+32*(i))   <= (others => dsp_in_sign_bits(h)(3+4*(i)));
            dsp_in_shifter_operand_lat_wire(f)(31+32*(i) downto 31 - to_integer(unsigned(dsp_in_shift_amount(f)(4 downto 0)))+32*(i)) <= 
            dsp_in_shifter_operand_lat(f)(     31+32*(i) downto 31 - to_integer(unsigned(dsp_in_shift_amount(f)(4 downto 0)))+32*(i));
          end loop;
        elsif (decoded_instruction_DSP_lat(h)(KSRAV_bit_position) = '1' or decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1') and
               MVTYPE_DSP(h) = "01" then -- 16-bit sign extension for for srl in stage 1
          for i in 0 to 2*SIMD-1 loop
            --dsp_in_shifter_operand_lat(f)(15+16*(i) downto 15 - to_integer(unsigned(dsp_in_shift_amount(h)(3 downto 0)))+16*(i))   <= (others => dsp_in_sign_bits(h)(1+2*(i)));
            dsp_in_shifter_operand_lat_wire(f)(15+16*(i) downto 15 - to_integer(unsigned(dsp_in_shift_amount(f)(3 downto 0)))+16*(i)) <= 
            dsp_in_shifter_operand_lat(f)(     15+16*(i) downto 15 - to_integer(unsigned(dsp_in_shift_amount(f)(3 downto 0)))+16*(i));
          end loop;
        elsif (decoded_instruction_DSP_lat(h)(KSRAV_bit_position) = '1'  or decoded_instruction_DSP_lat(h)(KDOTPPS_bit_position) = '1') and
               MVTYPE_DSP(h) = "00" then  -- 8-bit  sign extension for for srl in stage 1
          for i in 0 to 4*SIMD-1 loop
            --dsp_in_shifter_operand_lat(f)(7+8*(i) downto 7 - to_integer(unsigned(dsp_in_shift_amount(h)(2 downto 0)))+8*(i))    <= (others => dsp_in_sign_bits(h)(i));
            dsp_in_shifter_operand_lat_wire(f)(7+8*(i) downto 7 - to_integer(unsigned(dsp_in_shift_amount(f)(2 downto 0)))+8*(i)) <= 
            dsp_in_shifter_operand_lat(f)(     7+8*(i) downto 7 - to_integer(unsigned(dsp_in_shift_amount(f)(2 downto 0)))+8*(i));
          end loop;
        end if;
      end if;
    end loop;
  end process; 

  end generate SHIF_replicated;

------------------------------------------------------------------------ end of ACCUM Unit -------
--------------------------------------------------------------------------------------------------  

end SHIF_STG;