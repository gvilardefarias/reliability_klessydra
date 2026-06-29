
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
      SIMD_Width            : natural
    );
	port(
      clk_i                             : in  std_logic;
      rst_ni                            : in  std_logic;
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
end entity;
architecture ADD_STG of ADDER is
  
  subtype accl_range is integer range ACCL_NUM-1 downto 0;
  subtype fu_range   is integer range FU_NUM-1 downto 0;

  signal dsp_add_8_0                    : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_16_8                   : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_8_0_wire               : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_16_8_wire              : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal carry_8_wire                   : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal carry_16_wire                  : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal carry_24_wire                  : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal dsp_in_adder_operands_lat      : std_logic_vector(((FU_NUM)*(2)*(SIMD_Width/2))-1 downto 0);
  signal carry_16                       : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  signal dsp_add_24_16_wire             : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  signal dsp_add_32_24_wire             : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
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
  variable dsp_add_8_0_wire_var  : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  variable dsp_add_16_8_wire_var : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  variable carry_8_wire_var    : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  variable carry_16_wire_var   : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  begin
    dsp_add_8_0_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f))  := dsp_add_8_0((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));
    dsp_add_16_8_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f)) := dsp_add_16_8((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));

    carry_8_wire_var(((f+1)*(SIMD))-1 downto SIMD*f)    := (others => '0');
    carry_16_wire_var(((f+1)*(SIMD))-1 downto SIMD*f)   := (others => '0');
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
          dsp_add_8_0_wire_var(((i+1)*(9))-1 + (f)*(SIMD)*(9) downto 9*i + (f)*(SIMD)*(9))   := std_logic_vector('0' & unsigned(dsp_in_adder_operands(7+8*(4*i)   + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width) downto  8*(4*i) + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width)))   + unsigned(dsp_in_adder_operands(7+8*(4*i)   + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  8*(4*i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))) + unsigned'('0'&twos_complement((h)*(64) + 0+(4*i))));
          dsp_add_16_8_wire_var(((i+1)*(9))-1 + (f)*(SIMD)*(9) downto 9*i + (f)*(SIMD)*(9))  := std_logic_vector('0' & unsigned(dsp_in_adder_operands(15+8*(4*i)  + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width) downto  8+8*(4*i) + (f)*(2)*(SIMD_Width) + (0)*(SIMD_Width))) + unsigned(dsp_in_adder_operands(15+8*(4*i)  + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width) downto  8+8*(4*i) + (f)*(2)*(SIMD_Width) + (1)*(SIMD_Width))) + unsigned'('0'&carry_8_wire((f)*(SIMD) + i)) + unsigned'('0'&twos_complement((h)*(64) + 1+(4*i))));
          -- All the 8-bit adders are lumped into one output write signal that will write to the scratchpads
          -- Carries are either passed or blocked for the 9-th, 17-th, and 25-th bits
          carry_8_wire_var((f)*(SIMD) + i)  := dsp_add_8_0_wire((f)*(SIMD)*(9) + (i)*(9) + 8)   and carry_pass((h)*(3) + 0);
          carry_16_wire_var((f)*(SIMD) + i) := dsp_add_16_8_wire((f)*(SIMD)*(9) + (i)*(9) + 8)  and carry_pass((h)*(3) + 1);
        end if;
      end loop;
    end loop;

    dsp_add_8_0_wire((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f))  <= dsp_add_8_0_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));
    dsp_add_16_8_wire((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f)) <= dsp_add_16_8_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));
    carry_8_wire(((f+1)*(SIMD))-1 downto SIMD*f)    <= carry_8_wire_var(((f+1)*(SIMD))-1 downto SIMD*f);
    carry_16_wire(((f+1)*(SIMD))-1 downto SIMD*f)   <= carry_16_wire_var(((f+1)*(SIMD))-1 downto SIMD*f);
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
  variable carry_24_wire_var   : std_logic_vector(((FU_NUM)*(SIMD))-1 downto 0);
  variable dsp_add_24_16_wire_var : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  variable dsp_add_32_24_wire_var : std_logic_vector(((FU_NUM)*(SIMD)*(9))-1 downto 0);
  begin
    carry_24_wire_var(((f+1)*(SIMD))-1 downto SIMD*f)               := (others => '0');
    dsp_add_24_16_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f))          := (others => '0');
    dsp_add_32_24_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f))          := (others => '0');
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
            dsp_add_24_16_wire_var(((i+1)*(9))-1 + (f)*(SIMD)*(9) downto 9*i + (f)*(SIMD)*(9)) := std_logic_vector('0' & unsigned(dsp_in_adder_operands_lat(7+8*(2*i)  + (f)*(2)*(SIMD_Width/2) + (0)*(SIMD_Width/2) downto  8*(2*i) + (f)*(2)*(SIMD_Width/2) + (0)*(SIMD_Width/2))) + 
                                                               unsigned(dsp_in_adder_operands_lat(7+8*(2*i)  + (f)*(2)*(SIMD_Width/2) + (1)*(SIMD_Width/2) downto  8*(2*i) + (f)*(2)*(SIMD_Width/2) + (1)*(SIMD_Width/2))) + 
                                                                        unsigned'('0'&carry_16((f)*(SIMD) + i)) + unsigned'('0'&twos_complement((h)*(64) + 2+(4*i))));
            dsp_add_32_24_wire_var(((i+1)*(9))-1 + (f)*(SIMD)*(9) downto 9*i + (f)*(SIMD)*(9)) := std_logic_vector('0' & unsigned(dsp_in_adder_operands_lat(15+8*(2*i)  + (f)*(2)*(SIMD_Width/2) + (0)*(SIMD_Width/2) downto  8+8*(2*i) + (f)*(2)*(SIMD_Width/2) + (0)*(SIMD_Width/2))) + 
                                                               unsigned(dsp_in_adder_operands_lat(15+8*(2*i)  + (f)*(2)*(SIMD_Width/2) + (1)*(SIMD_Width/2) downto  8+8*(2*i) + (f)*(2)*(SIMD_Width/2) + (1)*(SIMD_Width/2))) + 
                                                                        unsigned'('0'&carry_24_wire((f)*(SIMD) + i)) + unsigned'('0'&twos_complement((h)*(64) + 3+(4*i))));
            -- All the 8-bit adders are lumped into one output write signal that will write to the scratchpads
            -- Carries are either passed or blocked for the 9-th, 17-th, and 25-th bits
            carry_24_wire_var((f)*(SIMD) + i) := dsp_add_24_16_wire((f)*(SIMD)*(9) + (i)*(9) + 8) and carry_pass((h)*(3) + 2);
          end if;
        end loop;
      end if;
    end loop;

    carry_24_wire(((f+1)*(SIMD))-1 downto SIMD*f)               <= carry_24_wire_var(((f+1)*(SIMD))-1 downto SIMD*f);
    dsp_add_24_16_wire((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f))          <= dsp_add_24_16_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));
    dsp_add_32_24_wire((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f))          <= dsp_add_32_24_wire_var((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));
  end process;

  fsm_DSP_adder : process(clk_i, rst_ni)
  variable h : integer;
  variable dsp_out_adder_results_lat : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  variable dsp_in_adder_operands_lat_var : std_logic_vector(((FU_NUM)*(2)*(SIMD_Width/2))-1 downto 0);
  begin
    if rst_ni = '0' then
    dsp_out_adder_results_lat((f+1)*SIMD_Width -1 downto f*SIMD_Width) := (others => '0');
    dsp_in_adder_operands_lat_var((f+1)*2*(SIMD_Width/2) -1 downto f*2*(SIMD_Width/2)) := (others => '0');
    MSB_stage_2((f+1)*2*4*SIMD -1 downto f*2*4*SIMD) <= (others => '0');
    dsp_add_8_0((f+1)*SIMD*9 -1 downto f*SIMD*9) <= (others => '0');
    dsp_add_16_8((f+1)*SIMD*9 -1 downto f*SIMD*9) <= (others => '0');
    carry_16((f+1)*SIMD -1 downto f*SIMD) <= (others => '0');
    elsif rising_edge(clk_i) then
      for g in 0 to (ACCL_NUM - FU_NUM) loop
        if multithreaded_accl_en = 1 then
          h := g;  -- set the spm rd/wr ports equal to the "for-loop"
        elsif multithreaded_accl_en = 0 then
          h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
        end if;
        -- Addition is here
        if add_en(h) = '1' and halt_dsp_lat(h) = '0' then
          carry_16(((f+1)*(SIMD))-1 downto SIMD*f)     <= carry_16_wire(((f+1)*(SIMD))-1 downto SIMD*f);
          dsp_add_8_0((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f))  <= dsp_add_8_0_wire((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));
          dsp_add_16_8((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f)) <= dsp_add_16_8_wire((((f)+1)*(SIMD)*(9))-1 downto (SIMD)*(9)*(f));
          MSB_stage_2((((f)+1)*(2)*(4*SIMD))-1 downto (2)*(4*SIMD)*(f))  <= MSB_stage_1((((f)+1)*(2)*(4*SIMD))-1 downto (2)*(4*SIMD)*(f));
          --  Addition in SIMD Virtual Parallelism is executed here, if the carries are blocked, we will have a chain of 8-bit or 16-bit adders, else we have normal 32-bit adders
          for i in 0 to SIMD-1 loop
            if (adder_stage_2_en(h) = '1' or recover_state_wires(h) = '1') then
                -- All the 8-bit adders are lumped into one output signal
              dsp_out_adder_results_lat(31+32*(i)  + (f)*(SIMD_Width) downto  32*(i) + (f)*(SIMD_Width)) := dsp_add_32_24_wire(7  + (f)*(SIMD)*(9) + (i)*(9) downto  0 + (f)*(SIMD)*(9) + (i)*(9)) & dsp_add_24_16_wire(7  + (f)*(SIMD)*(9) + (i)*(9) downto  0 + (f)*(SIMD)*(9) + (i)*(9)) & dsp_add_16_8(7  + (f)*(SIMD)*(9) + (i)*(9) downto  0 + (f)*(SIMD)*(9) + (i)*(9)) & dsp_add_8_0(7  + (f)*(SIMD)*(9) + (i)*(9) downto  0 + (f)*(SIMD)*(9) + (i)*(9));
            end if;
          end loop;
          for i in 0 to SIMD-1 loop
            for j in 0 to 1 loop
              dsp_in_adder_operands_lat_var(15 +16*(i)  + (f)*(2)*(SIMD_Width/2) + (j)*(SIMD_Width/2) downto  16*(i) + (f)*(2)*(SIMD_Width/2) + (j)*(SIMD_Width/2)) := dsp_in_adder_operands(31+32*(i)  + (f)*(2)*(SIMD_Width) + (j)*(SIMD_Width) downto  16+32*(i) + (f)*(2)*(SIMD_Width) + (j)*(SIMD_Width));
            end loop;
          end loop;
        end if;
      end loop;
    end if;

    dsp_in_adder_operands_lat((f+1)*2*(SIMD_Width/2) -1 downto f*2*(SIMD_Width/2)) <= dsp_in_adder_operands_lat_var((f+1)*2*(SIMD_Width/2) -1 downto f*2*(SIMD_Width/2));
    dsp_out_adder_results((f+1)*SIMD_Width -1 downto f*SIMD_Width) <= dsp_out_adder_results_lat((f+1)*SIMD_Width -1 downto f*SIMD_Width);
  end process;

  end generate ADD_replicated;

------------------------------------------------------------------------ end of ACCUM Unit -------
--------------------------------------------------------------------------------------------------  

end ADD_STG;
