-- Multiplier

-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

entity MULTIPLIER is
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
end entity;
architecture MULT_STG of MULTIPLIER is
  subtype accl_range is integer range ACCL_NUM - 1 downto 0;
  subtype fu_range   is integer range FU_NUM - 1 downto 0;

  signal dsp_mul_a                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers
  signal dsp_mul_b                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers
  signal dsp_mul_c                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers
  signal dsp_mul_d                       : array_2d(FU_NUM-1 downto 0)(SIMD_Width -1 downto 0); --  Contains the results of the 16-bit multipliers
  signal mul_tmp_a                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
  signal mul_tmp_b                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
  signal mul_tmp_c                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
  signal mul_tmp_d                       : array_3d(FU_NUM-1 downto 0)(SIMD-1 downto 0)(Data_Width-1 downto 0);
begin


  MULT_replicated : for f in fu_range generate
  --------------------------------------------------------------------------------------------------------------------------------
  --  ███╗   ███╗██╗   ██╗██╗  ████████╗██╗██████╗ ██╗     ██╗███████╗██████╗ ███████╗    ███████╗████████╗ ██████╗        ██╗  --
  --  ████╗ ████║██║   ██║██║  ╚══██╔══╝██║██╔══██╗██║     ██║██╔════╝██╔══██╗██╔════╝    ██╔════╝╚══██╔══╝██╔════╝       ███║  --
  --  ██╔████╔██║██║   ██║██║     ██║   ██║██████╔╝██║     ██║█████╗  ██████╔╝███████╗    ███████╗   ██║   ██║  ███╗█████╗╚██║  --
  --  ██║╚██╔╝██║██║   ██║██║     ██║   ██║██╔═══╝ ██║     ██║██╔══╝  ██╔══██╗╚════██║    ╚════██║   ██║   ██║   ██║╚════╝ ██║  --
  --  ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║██║     ███████╗██║███████╗██║  ██║███████║    ███████║   ██║   ╚██████╔╝       ██║  --
  --  ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝╚═╝     ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝╚══════╝    ╚══════╝   ╚═╝    ╚═════╝        ╚═╝  --
  --------------------------------------------------------------------------------------------------------------------------------
  -- STAGE 1 --
  fsm_MUL_STAGE_1 : process(clk_i,rst_ni)
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
        if halt_dsp_lat(h) = '0' then
          if mul_en(h) = '1' and (mul_stage_1_en(h) = '1' or recover_state_wires(h) = '1') then
          for i in 0 to SIMD-1 loop
              -- Unwinding the loop: 
              -- (1) The impelemtation in the loop does multiplication for KDOTP32, and KDOTP16 using only 16-bit multipliers. "A*B" = [Ahigh*(2^16) + Alow]*[Bhigh*(2^16) + Blow]
              -- (2) Expanding this equation "[Ahigh*(2^16) + Alow]*[Bhigh*(2^16) + Blow]"  gives: "Ahigh*Bhigh*(2^32) + Ahigh*Blow*(2^16) + Alow*Bhigh*(2^16) + Alow*Blow" which are the terms being stored in dsp_out_mul_results
              -- (3) Partial Multiplication 
                  -- (a) "dsp_mul_a" <= Ahigh*Bhigh 
                  -- (b) "dsp_mul_b" <= Ahigh*Blow
                  -- (c) "dsp_mul_c" <= Alow*Bhigh
                  -- (d) "dsp_mul_d" <= Alow*Blow
              -- (4) "dsp_mul_a" is shifted by 32 bits to the left, "dsp_mul_b" and "dsp_mul_c" are shifted by 16-bits to the left, "dsp_mul_d" is not shifted
              -- (5) For 16-bit and 8-bit muls, the FUNCT_SELECT_MASK is set to x"00000000" blocking the terms in "dsp_mul_b" and "dsp_mul_c". For executing 32-bit muls , we set the mask to x"FFFFFFFF"
              dsp_mul_a(f)(31+32*(i)  downto 32*(i)) <= std_logic_vector(unsigned(dsp_in_mul_operands(f)(0)(15+16*(2*i+1)    downto 16*(2*i+1))) * unsigned(dsp_in_mul_operands(f)(1)(15+16*(2*i+1)  downto 16*(2*i+1))));
              dsp_mul_b(f)(31+32*(i)  downto 32*(i)) <= std_logic_vector((unsigned(dsp_in_mul_operands(f)(0)(16*(2*i+1) - 1  downto 16*(2*i)))   * unsigned(dsp_in_mul_operands(f)(1)(15+16*(2*i+1)  downto 16*(2*i+1)))) and unsigned(FUNCT_SELECT_MASK(h)));
              dsp_mul_c(f)(31+32*(i)  downto 32*(i)) <= std_logic_vector((unsigned(dsp_in_mul_operands(f)(0)(15+16*(2*i+1)   downto 16*(2*i+1))) * unsigned(dsp_in_mul_operands(f)(1)(16*(2*i+1) - 1 downto 16*(2*i))))   and unsigned(FUNCT_SELECT_MASK(h)));
              dsp_mul_d(f)(31+32*(i)  downto 32*(i)) <= std_logic_vector(unsigned(dsp_in_mul_operands(f)(0)(16*(2*i+1)  - 1  downto 16*(2*i)))   * unsigned(dsp_in_mul_operands(f)(1)(16*(2*i+1) - 1 downto 16*(2*i))));
            end loop;
          end if;
        end if;
      end loop;
    end if;
  end process;

  fsm_MUL_STAGE_1_COMB : process(all)
  variable h : integer;
  begin
    mul_tmp_a(f) <= (others => (others => '0'));
    mul_tmp_b(f) <= (others => (others => '0'));
    mul_tmp_c(f) <= (others => (others => '0'));
    mul_tmp_d(f) <= (others => (others => '0'));
    for g in 0 to (ACCL_NUM - FU_NUM) loop
      if multithreaded_accl_en = 1 then
        h := g;  -- set the spm rd/wr ports equal to the "for-loop"
      elsif multithreaded_accl_en = 0 then
        h := f;  -- set the spm rd/wr ports equal to the "for-generate" 
      end if;
      -- KDOTP and KSVMUL instructions are handeled here
      -- this part right here shifts the intermidiate resutls appropriately, and then accumulates them in order to get the final mul result
      if mul_en(h) = '1' and (mul_stage_2_en(h) = '1' or recover_state_wires(h) = '1') then
        for i in 0 to SIMD-1 loop
          if MVTYPE_DSP(h) /= "10" then
            ------------------------------------------------------------------------------------
            mul_tmp_a(f)(i) <= (dsp_mul_a(f)(15+16*(2*i)  downto 16*(2*i)) & x"0000");
            mul_tmp_d(f)(i) <= (x"0000" & dsp_mul_d(f)(15+16*(2*i)  downto 16*(2*i)));
            ------------------------------------------------------------------------------------
          elsif MVTYPE_DSP(h) = "10" then
            -- mul_tmp_a(f)(i) <= (dsp_mul_a(f)(31+32*(2*i)  downto 31*(2*i)) & x"0000");     -- The upper 32-bit results of the multiplication are discarded   (Ah*Bh)
            mul_tmp_b(f)(i) <= (dsp_mul_b(f)(15+16*(2*i) downto 16*(2*i)) & x"0000");         -- Modified to only add the partial result to the lower 32-bits   (Ah*Bl)
            mul_tmp_c(f)(i) <= (dsp_mul_c(f)(15+16*(2*i) downto 16*(2*i)) & x"0000");         -- Modified to only add the partial result to the lower 32-bits   (Al*Bh)
            mul_tmp_d(f)(i) <= (dsp_mul_d(f)(31+32*(i)   downto 32*(i)));                     -- This is the lower 32-bit result of the partial mmultiplication (Al*Bl)
          end if;
        end loop;
      end if;
    end loop;
  end process;

  ------------------------------------------------------------------------------------------------------------------------------------
  --  ███╗   ███╗██╗   ██╗██╗  ████████╗██╗██████╗ ██╗     ██╗███████╗██████╗ ███████╗    ███████╗████████╗ ██████╗       ██████╗   --
  --  ████╗ ████║██║   ██║██║  ╚══██╔══╝██║██╔══██╗██║     ██║██╔════╝██╔══██╗██╔════╝    ██╔════╝╚══██╔══╝██╔════╝       ╚════██╗  --
  --  ██╔████╔██║██║   ██║██║     ██║   ██║██████╔╝██║     ██║█████╗  ██████╔╝███████╗    ███████╗   ██║   ██║  ███╗█████╗ █████╔╝  --
  --  ██║╚██╔╝██║██║   ██║██║     ██║   ██║██╔═══╝ ██║     ██║██╔══╝  ██╔══██╗╚════██║    ╚════██║   ██║   ██║   ██║╚════╝██╔═══╝   --
  --  ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║██║     ███████╗██║███████╗██║  ██║███████║    ███████║   ██║   ╚██████╔╝      ███████╗  --
  --  ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝╚═╝     ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝╚══════╝    ╚══════╝   ╚═╝    ╚═════╝       ╚══════╝  --
  ------------------------------------------------------------------------------------------------------------------------------------

  -- STAGE 2 --
  fsm_MUL_STAGE_2 : process(clk_i, rst_ni)
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
        -- Accumulate the partial multiplications to make up bigger multiplications
        if mul_en(h) = '1' and (mul_stage_2_en(h) = '1' or recover_state_wires(h) = '1') and halt_dsp_lat(h) = '0' then
          for i in 0 to SIMD-1 loop
            dsp_out_mul_results(f)((Data_Width-1)+Data_Width*(i) downto Data_Width*(i))  <= (std_logic_vector(unsigned(mul_tmp_a(f)(i)) + unsigned(mul_tmp_b(f)(i)) + unsigned(mul_tmp_c(f)(i)) + unsigned(mul_tmp_d(f)(i))));
          end loop;
        end if;
      end loop;
    end if;
  end process;

  end generate MULT_replicated;
end MULT_STG;