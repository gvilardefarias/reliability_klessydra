
-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

entity COMPARATOR is
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
    MVTYPE_DSP                      : in array_2d(ACCL_NUM-1 downto 0)(1 downto 0);
    relu_instr                      : in std_logic_vector(ACCL_NUM-1 downto 0);
    -- inputs from DSP_pipeline_controller
    halt_dsp_lat                    : in std_logic_vector(ACCL_NUM-1 downto 0);
    cmp_stage_1_en                  : in std_logic_vector(ACCL_NUM-1 downto 0);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(ACCL_NUM-1 downto 0);
    -- inputs from DSP_FU_Handler
    cmp_en                          : in std_logic_vector(ACCL_NUM-1 downto 0);  -- enables the use of the shifters
    -- inputs from DSP_Mapping
    dsp_in_cmp_operands             : in array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0);
    -- inputs from adders
    MSB_stage_2                     : in array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(4*SIMD-1 downto 0);
  
    -- outputs for DSP_Mapping
    dsp_out_cmp_results             : out array_2d(FU_NUM-1 downto 0)(SIMD_Width-1 downto 0)
  );
end entity COMPARATOR;

architecture COMP_STG of COMPARATOR is
  subtype accl_range is integer range ACCL_NUM-1 downto 0;
  subtype fu_range   is integer range FU_NUM-1 downto 0;

  signal MSB_stage_3                     : array_3d(ACCL_NUM-1 downto 0)(1 downto 0)(4*SIMD-1 downto 0);
begin


  COMP_replicated : for f in fu_range generate
  ----------------------------------------------------------------------------------------------------
  -- ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ██████╗  █████╗ ████████╗ ██████╗ ██████╗ ███████╗  --
  --██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝  --
  --██║     ██║   ██║██╔████╔██║██████╔╝███████║██████╔╝███████║   ██║   ██║   ██║██████╔╝███████╗  --
  --██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██╔══██╗██╔══██║   ██║   ██║   ██║██╔══██╗╚════██║  --
  --╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║██║  ██║██║  ██║   ██║   ╚██████╔╝██║  ██║███████║  --
  -- ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝  --
  ----------------------------------------------------------------------------------------------------

  fsm_RELU : process(clk_i, rst_ni)
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
        if cmp_en(h) = '1' and halt_dsp_lat(h) = '0' then
          MSB_stage_3(f)  <= MSB_stage_2(f);
          if cmp_stage_1_en(h) = '1' or recover_state_wires(h) = '1' then
            if MVTYPE_DSP(h) = "10" then
              for i in 0 to SIMD-1 loop
                if relu_instr(h) = '1' then
                  if dsp_in_cmp_operands(f)(31+32*(i)) = '1' then
                    -- TODO do the same for the other sizes
                    --dsp_out_cmp_results(f)(31+32*(i) downto 32*(i)) <= (others => '0');
                    dsp_out_cmp_results(f)(31+32*(i) downto 32*(i)) <= std_logic_vector(to_unsigned(0, 32));
                  else
                    dsp_out_cmp_results(f)(31+32*(i) downto 32*(i)) <= dsp_in_cmp_operands(f)(31+32*(i) downto 32*(i));
                  end if;
                else
                  if MSB_stage_3(f)(1)(4*(i)+3) = MSB_stage_3(f)(0)(4*(i)+3) then -- if both signs are equal, than read the MSB from the subtractor
                    if dsp_in_cmp_operands(f)(31+32*(i)) = '1' then
                      dsp_out_cmp_results(f)(31+32*(i) downto 32*(i)) <= (31+32*(i) downto 32*(i)+1 => '0') & '1';
                    else
                      dsp_out_cmp_results(f)(31+32*(i) downto 32*(i)) <= (others => '0');
                    end if;
                  elsif MSB_stage_3(f)(1)(4*(i)+3) /= MSB_stage_3(f)(0)(4*(i)+3) and MSB_stage_3(f)(0)(4*(i)+3) = '1' then
                    dsp_out_cmp_results(f)(31+32*(i) downto 32*(i)) <= (31+32*(i) downto 32*(i)+1 => '0') & '1';
                  else
                    dsp_out_cmp_results(f)(31+32*(i) downto 32*(i)) <= (others => '0');
                  end if;
                end if;
              end loop;
            elsif MVTYPE_DSP(h) = "01" then
              for i in 0 to 2*SIMD-1 loop
                if relu_instr(h) = '1' then
                  if dsp_in_cmp_operands(f)(15+16*(i)) = '1' then
                      dsp_out_cmp_results(f)(15+16*(i) downto 16*(i)) <= (others => '0');
                  else
                      dsp_out_cmp_results(f)(15+16*(i) downto 16*(i)) <= dsp_in_cmp_operands(f)(15+16*(i) downto 16*(i));
                  end if;
                else
                  if MSB_stage_3(f)(1)(2*(i)+1) = MSB_stage_3(f)(0)(2*(i)+1) then -- if both signs are equal, than read the MSB from the subtractor
                    if dsp_in_cmp_operands(f)(15+16*(i)) = '1' then
                      dsp_out_cmp_results(f)(15+16*(i) downto 16*(i)) <= (15+16*(i) downto 16*(i)+1 => '0') & '1';
                    else
                      dsp_out_cmp_results(f)(15+16*(i) downto 16*(i)) <= (others => '0');
                    end if;
                  elsif MSB_stage_3(f)(1)(2*(i)+1) /= MSB_stage_3(f)(0)(2*(i)+1) and MSB_stage_3(f)(0)(2*(i)+1) = '1' then
                    dsp_out_cmp_results(f)(15+16*(i) downto 16*(i)) <= (15+16*(i) downto 16*(i)+1 => '0') & '1';
                  else
                    dsp_out_cmp_results(f)(15+16*(i) downto 16*(i)) <= (others => '0');
                  end if;
                end if;
              end loop;
            elsif MVTYPE_DSP(h) = "00" then
              for i in 0 to 4*SIMD-1 loop
                if relu_instr(h) = '1' then
                  if dsp_in_cmp_operands(f)(7+8*(i)) = '1' then
                      dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= (others => '0');
                  else
                    dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= dsp_in_cmp_operands(f)(7+8*(i) downto 8*(i));
                  end if;
                else
                  if MSB_stage_3(f)(1)(i) = MSB_stage_3(f)(0)(i) then -- if both signs are equal, than read the MSB from the subtractor
                    if dsp_in_cmp_operands(f)(7+8*(i)) = '1' then
                      dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= (std_logic_vector(to_unsigned(0, 7))) & '1';
--                      dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= (7+8*(i) downto 8*(i)+1 => '0') & '1';
                    else
                      dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= std_logic_vector(to_unsigned(0, 8));
--                      dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= (others => '0');
                    end if;
                  elsif MSB_stage_3(f)(1)(i) /= MSB_stage_3(f)(0)(i) and MSB_stage_3(f)(0)(i) = '1' then
                    dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= (std_logic_vector(to_unsigned(0, 7))) & '1';
--                    dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= (7+8*(i) downto 8*(i)+1 => '0') & '1';
                  else
                    dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= std_logic_vector(to_unsigned(0, 8));
--                    dsp_out_cmp_results(f)(7+8*(i) downto 8*(i)) <= (others => '0');
                  end if;
                end if;
              end loop;  -- SIMD LOOP
            end if;
          end if;
        end if;
      end loop; -- ACCL NUM LOOP
    end if;
  end process;

  end generate COMP_replicated;
end COMP_STG;