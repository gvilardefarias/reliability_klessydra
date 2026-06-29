
-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

entity ADDER is
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
      clk_i                             : in  std_logic;
      rst_ni                            : in  std_logic;
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
end entity;
architecture ADD_STG of ADDER is
  
  subtype accl_range is integer range ACCL_NUM-1 downto 0;
  subtype fu_range   is integer range FU_NUM-1 downto 0;

  signal dsp_add_8_0                    : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits, contains the results of 8-bit adders
  signal dsp_add_16_8                   : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits  contains the results of 8-bit adders
  signal dsp_add_8_0_wire               : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits, contains the results of 8-bit adders
  signal dsp_add_16_8_wire              : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits  contains the results of 8-bit adders
  signal carry_8_wire                   : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_8_0" signal
  signal carry_16_wire                  : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_16_8" signal
  signal carry_24_wire                  : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_24_16" signal
  signal dsp_in_adder_operands_lat      : array_3d(FU_NUM-1 downto 0)(1 downto 0)(SIMD_Width/2 -1 downto 0); -- data_Width devided by the number of pipeline stages
  signal carry_16                       : array_2d(FU_NUM-1 downto 0)(SIMD-1 downto 0);  -- carry-out bit of the "dsp_add_16_8" signal
  signal dsp_add_24_16_wire             : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits  contains the results of 8-bit adders
  signal dsp_add_32_24_wire             : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(8 downto 0); -- 9-bits, this should be 8 if we choose to discard the overflow of the addition of the upper byte
begin

  ADD_replicated : for f in fu_range generate
  ------------------------------------------------------------------------------------------------
  --   █████╗ ██████╗ ██████╗ ███████╗██████╗ ███████╗    ███████╗████████╗ ██████╗        ██╗  --
  --  ██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔════╝    ██╔════╝╚══██╔══╝██╔════╝       ███║  --
  --  ███████║██║  ██║██║  ██║█████╗  ██████╔╝███████╗    ███████╗   ██║   ██║  ███╗█████╗╚██║  --
  --  ██╔══██║██║  ██║██║  ██║██╔══╝  ██╔══██╗╚════██║    ╚════██║   ██║   ██║   ██║╚════╝ ██║  --
  --  ██║  ██║██████╔╝██████╔╝███████╗██║  ██║███████║    ███████║   ██║   ╚██████╔╝       ██║  --
  -- -╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝    ╚══════╝   ╚═╝    ╚═════╝        ╚═╝  --
  ------------------------------------------------------------------------------------------------
    
  fsm_DSP_adder_stage_1 : process(all)
  variable h : integer;
  begin
    dsp_add_8_0_wire(f)  <= dsp_add_8_0(f);
    dsp_add_16_8_wire(f) <= dsp_add_16_8(f);
    for g in 0 to (ACCL_NUM - FU_NUM) loop
      if multithreaded_accl_en = 1 then
        h := g;  -- set the spm rd/wr ports equal to the "for-loop"
      elsif multithreaded_accl_en = 0 then
        h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
      end if;
      --  Addition in SIMD Virtual Parallelism is executed here, if the carries are blocked, we will have a chain of 8-bit or 16-bit adders, else we have 32-bit adders
      for i in 0 to SIMD-1 loop
        if (adder_stage_1_en(h) = '1' or recover_state_wires(h) = '1') then
          -- Unwinding the loop: 
          -- (1) the term "8*(4*i)" is used to jump between the 32-bit words, inside the 128-bit values read by the DSP
          -- (2) Each addition results in an 8-bit value, and the 9th bit being the carry, depending on the instruction (KADDV32, KADDV16, KADDV8) we either pass the or block the carries.
          -- (3) CARRIES:
           -- (a) If we pass all the carries in the 32-bit word, we will have executed KADDV32 (4*32-bit parallel additions)
           -- (b) If we pass the 9th and 25th carries we would have executed KADDV16 (8*16-bit parallel additions)
           -- (c) If we pass none of the carries then we would have executed KADDV8 (16*8-bit parallel additions)
          dsp_add_8_0_wire(f)(i)   <= std_logic_vector('0' & unsigned(dsp_in_adder_operands(f)(0)(7+8*(4*i)  downto 8*(4*i)))   + unsigned(dsp_in_adder_operands(f)(1)(7+8*(4*i)  downto 8*(4*i))) + twos_complement(h)(0+(4*i)));
          dsp_add_16_8_wire(f)(i)  <= std_logic_vector('0' & unsigned(dsp_in_adder_operands(f)(0)(15+8*(4*i) downto 8+8*(4*i))) + unsigned(dsp_in_adder_operands(f)(1)(15+8*(4*i) downto 8+8*(4*i))) + carry_8_wire(f)(i) + twos_complement(h)(1+(4*i)));
          -- All the 8-bit adders are lumped into one output write signal that will write to the scratchpads
          -- Carries are either passed or blocked for the 9-th, 17-th, and 25-th bits
          carry_8_wire(f)(i)  <= dsp_add_8_0_wire(f)(i)(8)   and carry_pass(h)(0);
          carry_16_wire(f)(i) <= dsp_add_16_8_wire(f)(i)(8)  and carry_pass(h)(1);
        end if;
      end loop;
    end loop;
  end process;

  ---------------------------------------------------------------------------------------------------
  --   █████╗ ██████╗ ██████╗ ███████╗██████╗ ███████╗    ███████╗████████╗ ██████╗       ██████╗  --
  --  ██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔════╝    ██╔════╝╚══██╔══╝██╔════╝       ╚════██╗ --
  --  ███████║██║  ██║██║  ██║█████╗  ██████╔╝███████╗    ███████╗   ██║   ██║  ███╗█████╗ █████╔╝ --
  --  ██╔══██║██║  ██║██║  ██║██╔══╝  ██╔══██╗╚════██║    ╚════██║   ██║   ██║   ██║╚════╝██╔═══╝  --
  --  ██║  ██║██████╔╝██████╔╝███████╗██║  ██║███████║    ███████║   ██║   ╚██████╔╝      ███████╗ --
  -- -╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝    ╚══════╝   ╚═╝    ╚═════╝       ╚══════╝ --
  ---------------------------------------------------------------------------------------------------

  fsm_DSP_adder_stage_2 : process(all)
  variable h : integer;
  begin
    carry_24_wire(f)               <= (others => '0');
    dsp_add_24_16_wire(f)          <= (others => (others => '0'));
    dsp_add_32_24_wire(f)          <= (others => (others => '0'));
    for g in 0 to (ACCL_NUM - FU_NUM) loop
      if multithreaded_accl_en = 1 then
        h := g;  -- set the spm rd/wr ports equal to the "for-loop"
      elsif multithreaded_accl_en = 0 then
        h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
      end if;
      -- Addition is here
      if halt_dsp_lat(h) = '0' then
      --  Addition in SIMD Virtual Parallelism is executed here, if the carries are blocked, we will have a chain of 8-bit or 16-bit adders, else we have 32-bit adders
        for i in 0 to SIMD-1 loop
          if (adder_stage_2_en(h) = '1' or recover_state_wires(h) = '1') then
            dsp_add_24_16_wire(f)(i) <= std_logic_vector('0' & unsigned(dsp_in_adder_operands_lat(f)(0)(7+8*(2*i) downto 8*(2*i))) + 
                                                               unsigned(dsp_in_adder_operands_lat(f)(1)(7+8*(2*i) downto 8*(2*i))) + 
                                                                        carry_16(f)(i) + twos_complement(h)(2+(4*i)));
            dsp_add_32_24_wire(f)(i) <= std_logic_vector('0' & unsigned(dsp_in_adder_operands_lat(f)(0)(15+8*(2*i) downto 8+8*(2*i))) + 
                                                               unsigned(dsp_in_adder_operands_lat(f)(1)(15+8*(2*i) downto 8+8*(2*i))) + 
                                                                        carry_24_wire(f)(i) + twos_complement(h)(3+(4*i)));
            -- All the 8-bit adders are lumped into one output write signal that will write to the scratchpads
            -- Carries are either passed or blocked for the 9-th, 17-th, and 25-th bits
            carry_24_wire(f)(i) <= dsp_add_24_16_wire(f)(i)(8) and carry_pass(h)(2);
          end if;
        end loop;
      end if;
    end loop;
  end process;

  fsm_DSP_adder : process(clk_i, rst_ni)
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
        -- Addition is here
        if add_en(h) = '1' and halt_dsp_lat(h) = '0' then
          carry_16(f)     <= carry_16_wire(f);
          dsp_add_8_0(f)  <= dsp_add_8_0_wire(f);
          dsp_add_16_8(f) <= dsp_add_16_8_wire(f);
          MSB_stage_2(f)  <= MSB_stage_1(f);
          --  Addition in SIMD Virtual Parallelism is executed here, if the carries are blocked, we will have a chain of 8-bit or 16-bit adders, else we have normal 32-bit adders
          for i in 0 to SIMD-1 loop
            if (adder_stage_2_en(h) = '1' or recover_state_wires(h) = '1') then
                -- All the 8-bit adders are lumped into one output signal
              dsp_out_adder_results(f)(31+32*(i) downto 32*(i)) <= dsp_add_32_24_wire(f)(i)(7 downto 0) & dsp_add_24_16_wire(f)(i)(7 downto 0) & dsp_add_16_8(f)(i)(7 downto 0) & dsp_add_8_0(f)(i)(7 downto 0);
            end if;
          end loop;
          for i in 0 to SIMD-1 loop
            for j in 0 to 1 loop
              dsp_in_adder_operands_lat(f)(j)(15 +16*(i) downto 16*(i)) <= dsp_in_adder_operands(f)(j)(31+32*(i) downto 16+32*(i));
            end loop;
          end loop;
        end if;
      end loop;
    end if;
  end process;

  end generate ADD_replicated;

------------------------------------------------------------------------ end of ACCUM Unit -------
--------------------------------------------------------------------------------------------------  

end ADD_STG;