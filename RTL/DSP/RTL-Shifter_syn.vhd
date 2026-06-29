
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
    MVTYPE_DSP                      : in std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
    decoded_instruction_DSP_lat     : in std_logic_vector(((ACCL_NUM)*(DSP_UNIT_INSTR_SET_SIZE))-1 downto 0);
    -- inputs from DSP_Excpt_Unit
    recover_state_wires             : in std_logic_vector(ACCL_NUM - 1 downto 0);
    -- inputs from DSP_FU_Handler
    shift_en                        : in std_logic_vector(ACCL_NUM - 1 downto 0);  -- enables the use of the shifters
    -- inputs from DSP_Mapping
    dsp_in_shifter_operand          : in std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
    dsp_in_shift_amount             : in std_logic_vector(((ACCL_NUM)*(5))-1 downto 0);

    --outputs for DSP_Mapping
    dsp_out_shifter_results         : out std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0)
  );
end entity SHIFTER;

architecture SHIF_STG of SHIFTER is

  subtype accl_range is integer range ACCL_NUM - 1 downto 0;
  subtype fu_range   is integer range FU_NUM - 1 downto 0;

  signal dsp_int_shifter_operand         : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_in_shifter_operand_lat      : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_in_shifter_operand_lat_wire : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  signal dsp_shift_enabler               : std_logic_vector(((ACCL_NUM)*(16))-1 downto 0);
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
  variable dsp_in_shifter_operand_lat_var : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  variable dsp_int_shifter_operand_var : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  begin
    if rst_ni = '0' then
      dsp_in_shifter_operand_lat_var((f+1)*SIMD_Width -1 downto f*SIMD_Width) := (others => '0');
      dsp_int_shifter_operand_var((f+1)*SIMD_Width -1 downto f*SIMD_Width) := (others => '0');
    elsif rising_edge(clk_i) then
      for g in 0 to (ACCL_NUM - FU_NUM) loop
        if multithreaded_accl_en = 1 then
          h := g;  -- set the spm rd/wr ports equal to the "for-loop"
        elsif multithreaded_accl_en = 0 then
          h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
        end if;
        if shift_en(h) = '1' and (shifter_stage_1_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
          for i in 0 to SIMD-1 loop
            dsp_int_shifter_operand_var(31+32*(i)  + (f)*(SIMD_Width) downto  32*(i) + (f)*(SIMD_Width)) := to_stdlogicvector(to_bitvector(dsp_in_shifter_operand(31+32*(i)  + (f)*(SIMD_Width) downto  32*(i) + (f)*(SIMD_Width))) srl to_integer(unsigned(dsp_in_shift_amount(((f+1)*(5))-1 downto 5*f))));
          end loop;
          --for i in 0 to 4*SIMD-1 loop -- latch the sign bits
            --dsp_in_sign_bits(f)(i) <= dsp_in_shifter_operand(f)(7+8*(i));
          --end loop;
          if MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00" then
            for i in 0 to 4*SIMD-1 loop -- latch the sign bits
              dsp_in_shifter_operand_lat_var(7+8*i  + (f)*(SIMD_Width) downto  8*i + (f)*(SIMD_Width)) := (others => dsp_in_shifter_operand((f)*(SIMD_Width) + 7+8*i));
            end loop;
          elsif MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" then
            for i in 0 to 2*SIMD-1 loop -- latch the sign bits
              for bit_idx in 0 to 15 loop
                dsp_in_shifter_operand_lat_var((f)*(SIMD_Width) + 16*i + bit_idx) := dsp_in_shifter_operand((f)*(SIMD_Width) + 15+16*i);
              end loop;
              --dsp_in_shifter_operand_lat(f)(15+16*i downto 16*i) <= (others => dsp_in_shifter_operand(f)(15+16*i));
            end loop;
          elsif MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "10" then
            for i in 0 to SIMD-1 loop -- latch the sign bits
              for bit_idx in 0 to 31 loop
                dsp_in_shifter_operand_lat_var((f)*(SIMD_Width) + 32*i + bit_idx) := dsp_in_shifter_operand((f)*(SIMD_Width) + 31+32*i);
              end loop;
--              dsp_in_shifter_operand_lat(f)(31+32*i downto 32*i) <= (others => dsp_in_shifter_operand(f)(31+32*i));
            end loop;
          end if;
        end if;
      end loop;
    end if;
    dsp_in_shifter_operand_lat((f+1)*SIMD_Width -1 downto f*SIMD_Width) <= dsp_in_shifter_operand_lat_var((f+1)*SIMD_Width -1 downto f*SIMD_Width);
    dsp_int_shifter_operand((f+1)*SIMD_Width -1 downto f*SIMD_Width) <= dsp_int_shifter_operand_var((f+1)*SIMD_Width -1 downto f*SIMD_Width);
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
  variable dsp_out_shifter_results_var : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  begin
    if rst_ni = '0' then
      dsp_out_shifter_results_var((f+1)*SIMD_Width -1 downto f*SIMD_Width) := (others => '0');
    elsif rising_edge(clk_i) then
      for g in 0 to (ACCL_NUM - FU_NUM) loop
        if multithreaded_accl_en = 1 then
          h := g;  -- set the spm rd/wr ports equal to the "for-loop"
        elsif multithreaded_accl_en = 0 then
          h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
        end if;
        if shift_en(h) = '1' and (shifter_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
          if    MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "10" then
            for i in 0 to SIMD-1 loop
              dsp_out_shifter_results_var(31+32*(i)  + (f)*(SIMD_Width) downto  32*(i) + (f)*(SIMD_Width)) := dsp_in_shifter_operand_lat_wire(31 +32*(i)  + (f)*(SIMD_Width) downto  32*(i) + (f)*(SIMD_Width)) or dsp_int_shifter_operand(31+32*(i)  + (f)*(SIMD_Width) downto  32*(i) + (f)*(SIMD_Width));
            end loop;
          elsif MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" or (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1' and MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00") then -- KDOTPPS8 has been added here because the number of elements loaded for mul operations is equal for 8-bit and 16-bits instr
            for i in 0 to 2*SIMD-1 loop
              dsp_out_shifter_results_var(15+16*(i)  + (f)*(SIMD_Width) downto  16*(i) + (f)*(SIMD_Width)) := dsp_in_shifter_operand_lat_wire(15 +16*(i)  + (f)*(SIMD_Width) downto  16*(i) + (f)*(SIMD_Width)) or (dsp_int_shifter_operand(15+16*(i)  + (f)*(SIMD_Width) downto  16*(i) + (f)*(SIMD_Width)) and dsp_shift_enabler(15  + (h)*(16) downto  0 + (h)*(16)));
            end loop;
          elsif MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00" then
            for i in 0 to 4*SIMD-1 loop
              dsp_out_shifter_results_var(7+8*(i)  + (f)*(SIMD_Width) downto  8*(i) + (f)*(SIMD_Width)) := dsp_in_shifter_operand_lat_wire(7 +8*(i)  + (f)*(SIMD_Width) downto  8*(i) + (f)*(SIMD_Width)) or  (dsp_int_shifter_operand(7+8*(i)  + (f)*(SIMD_Width) downto  8*(i) + (f)*(SIMD_Width)) and dsp_shift_enabler(7  + (h)*(16) downto  0 + (h)*(16)));
            end loop;
          end if;
        end if;
      end loop;
    end if;
    dsp_out_shifter_results((f+1)*SIMD_Width -1 downto f*SIMD_Width) <= dsp_out_shifter_results_var((f+1)*SIMD_Width -1 downto f*SIMD_Width);
  end process;

  fsm_DSP_shifter_comb : process(all)
  variable dsp_in_shifter_operand_lat_wire_var : std_logic_vector(((FU_NUM)*(SIMD_Width))-1 downto 0);
  variable dsp_shift_enabler_var               : std_logic_vector(((ACCL_NUM)*(16))-1 downto 0);
  variable h : integer;
  begin
    dsp_in_shifter_operand_lat_wire_var(((f+1)*(SIMD_Width))-1 downto SIMD_Width*f) := (others => '0');
    for g in 0 to (ACCL_NUM - FU_NUM) loop
      if multithreaded_accl_en = 1 then
        h := g;  -- set the spm rd/wr ports equal to the "for-loop"
      elsif multithreaded_accl_en = 0 then
        h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
      end if;
      dsp_shift_enabler_var(((h+1)*(16))-1 downto 16*h) := (others => '0');
      if shift_en(h) = '1' and halt_dsp_lat(h) = '0' then
        if MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" then
          for idx in 0 to 15 loop
            if idx <= (15 - to_integer(unsigned(dsp_in_shift_amount(3  + (h)*(5) downto  0 + (h)*(5))))) then
              dsp_shift_enabler_var((h)*(16) + idx) := '1';
            else
              dsp_shift_enabler_var((h)*(16) + idx) := '0';
            end if;
          end loop;
          --dsp_shift_enabler(h)(15 - to_integer(unsigned(dsp_in_shift_amount(h)(3 downto 0))) downto 0) <= (others => '1');
        elsif MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00" then
          -- TODO do the same thing as for 16b
          for idx in 0 to 7 loop
            if idx <= (7 - to_integer(unsigned(dsp_in_shift_amount(2  + (h)*(5) downto  0 + (h)*(5))))) then
              dsp_shift_enabler_var((h)*(16) + idx) := '1';
            else
              dsp_shift_enabler_var((h)*(16) + idx) := '0';
            end if;
          end loop;
          --dsp_shift_enabler(7 -  to_integer(unsigned(dsp_in_shift_amount(2  + (h)*(5)  + (h)*(16) downto   0 + (h)*(5)))) downto 0 + (h)*(16)) <= (others => '1');
        end if;
        if (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRAV_bit_position) = '1' or decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1') and
            MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "10" then    -- 32-bit sign extension for for srl in stage 1
          for i in 0 to SIMD-1 loop
            --dsp_in_shifter_operand_lat(f)(31+32*(i) downto 31 - to_integer(unsigned(dsp_in_shift_amount(h)(4 downto 0)))+32*(i))   <= (others => dsp_in_sign_bits(h)(3+4*(i)));
            for idx in 0 to 31 loop
              if idx = (31 - to_integer(unsigned(dsp_in_shift_amount(4  + (f)*(5) downto  0 + (f)*(5))))) then
                dsp_in_shifter_operand_lat_wire_var(31+32*(i)  + (f)*(SIMD_Width) downto idx +32*(i) + (f)*(SIMD_Width)) := 
                dsp_in_shifter_operand_lat(     31+32*(i)  + (f)*(SIMD_Width) downto idx +32*(i) + (f)*(SIMD_Width));
              end if;
            end loop;

           -- dsp_in_shifter_operand_lat_wire(31+32*(i)  + (f)*(SIMD_Width) downto  31 - to_integer(unsigned(dsp_in_shift_amount(4  + (f)*(5) downto  0 + (f)*(5))))+32*(i) + (f)*(SIMD_Width)) <= 
           -- dsp_in_shifter_operand_lat(     31+32*(i)  + (f)*(SIMD_Width) downto  31 - to_integer(unsigned(dsp_in_shift_amount(4  + (f)*(5) downto  0 + (f)*(5))))+32*(i) + (f)*(SIMD_Width));
          end loop;
        elsif (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRAV_bit_position) = '1' or decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1') and
               MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "01" then -- 16-bit sign extension for for srl in stage 1
          for i in 0 to 2*SIMD-1 loop
            --dsp_in_shifter_operand_lat(f)(15+16*(i) downto 15 - to_integer(unsigned(dsp_in_shift_amount(h)(3 downto 0)))+16*(i))   <= (others => dsp_in_sign_bits(h)(1+2*(i)));
            for idx in 0 to 15 loop
              if idx = (15 - to_integer(unsigned(dsp_in_shift_amount(3  + (f)*(5) downto  0 + (f)*(5))))) then
                dsp_in_shifter_operand_lat_wire_var(15+16*(i)  + (f)*(SIMD_Width) downto idx +16*(i) + (f)*(SIMD_Width)) := 
                dsp_in_shifter_operand_lat(     15+16*(i)  + (f)*(SIMD_Width) downto idx +16*(i) + (f)*(SIMD_Width));
              end if;
            end loop;

            --dsp_in_shifter_operand_lat_wire(15+16*(i)  + (f)*(SIMD_Width) downto  15 - to_integer(unsigned(dsp_in_shift_amount(3  + (f)*(5) downto  0 + (f)*(5))))+16*(i) + (f)*(SIMD_Width)) <= 
            --dsp_in_shifter_operand_lat(     15+16*(i)  + (f)*(SIMD_Width) downto  15 - to_integer(unsigned(dsp_in_shift_amount(3  + (f)*(5) downto  0 + (f)*(5))))+16*(i) + (f)*(SIMD_Width));
          end loop;
        elsif (decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KSRAV_bit_position) = '1'  or decoded_instruction_DSP_lat((h)*(DSP_UNIT_INSTR_SET_SIZE) + KDOTPPS_bit_position) = '1') and
               MVTYPE_DSP(((h+1)*(2))-1 downto 2*h) = "00" then  -- 8-bit  sign extension for for srl in stage 1
          for i in 0 to 4*SIMD-1 loop
            --dsp_in_shifter_operand_lat(f)(7+8*(i) downto 7 - to_integer(unsigned(dsp_in_shift_amount(h)(2 downto 0)))+8*(i))    <= (others => dsp_in_sign_bits(h)(i));
            for idx in 0 to 7 loop
              if idx = (7 - to_integer(unsigned(dsp_in_shift_amount(2  + (f)*(5) downto  0 + (f)*(5))))) then
                dsp_in_shifter_operand_lat_wire_var(7+8*(i)  + (f)*(SIMD_Width) downto idx +8*(i) + (f)*(SIMD_Width)) := 
                dsp_in_shifter_operand_lat(     7+8*(i)  + (f)*(SIMD_Width) downto idx +8*(i) + (f)*(SIMD_Width));
              end if;
            end loop;

            --dsp_in_shifter_operand_lat_wire(7+8*(i)  + (f)*(SIMD_Width) downto  7 - to_integer(unsigned(dsp_in_shift_amount(2  + (f)*(5) downto  0 + (f)*(5))))+8*(i) + (f)*(SIMD_Width)) <= 
            --dsp_in_shifter_operand_lat(     7+8*(i)  + (f)*(SIMD_Width) downto  7 - to_integer(unsigned(dsp_in_shift_amount(2  + (f)*(5) downto  0 + (f)*(5))))+8*(i) + (f)*(SIMD_Width));
          end loop;
        end if;
      end if;
    end loop;
    dsp_in_shifter_operand_lat_wire((f+1)*SIMD_Width -1 downto f*SIMD_Width) <= dsp_in_shifter_operand_lat_wire_var((f+1)*SIMD_Width -1 downto f*SIMD_Width);
    dsp_shift_enabler(((f+1)*(16))-1 downto 16*f) <= dsp_shift_enabler_var(((f+1)*(16))-1 downto 16*f);
  end process; 

  end generate SHIF_replicated;

------------------------------------------------------------------------ end of ACCUM Unit -------
--------------------------------------------------------------------------------------------------  

end SHIF_STG;
