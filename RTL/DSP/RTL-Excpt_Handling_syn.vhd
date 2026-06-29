
-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;
use IEEE.math_real.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

entity EXCPT_HANDLING is
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

    state_DSP                   : in std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
    dsp_instr_req               : in  std_logic_vector(ACCL_NUM-1 downto 0);
    busy_DSP_internal_lat       : in std_logic_vector(ACCL_NUM-1 downto 0);

    dsp_except_data_wire            : out std_logic_vector(((ACCL_NUM)*(32))-1 downto 0);
    dsp_taken_branch           : out std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_except_condition       : out std_logic_vector(ACCL_NUM-1 downto 0);
    dsp_sci_req                : out std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
    dsp_to_sc                  : out std_logic_vector(((ACCL_NUM)*(SPM_NUM)*(2))-1 downto 0);
    dsp_sc_read_addr           : out std_logic_vector(((ACCL_NUM)*(2)*(Addr_Width))-1 downto 0);
    nextstate_DSP              : out std_logic_vector(((ACCL_NUM)*(2))-1 downto 0);
    busy_excp_hand             : out std_logic_vector(ACCL_NUM-1 downto 0)
  );
end entity EXCPT_HANDLING;

architecture EXCPT_STG of EXCPT_HANDLING is
  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;
  subtype accl_range is integer range ACCL_NUM-1 downto 0;
  signal overflow_rs1_sc                 : std_logic_vector(((ACCL_NUM)*(Addr_Width + 1))-1 downto 0);
  signal overflow_rs2_sc                 : std_logic_vector(((ACCL_NUM)*(Addr_Width + 1))-1 downto 0);
  signal overflow_rd_sc                  : std_logic_vector(((ACCL_NUM)*(Addr_Width + 1))-1 downto 0);
begin


  EXCPT_replicated : for h in accl_range generate
    EXCPT : process(all)
  variable dsp_except_condition_wires : std_logic_vector(harc_range);
  variable harc_EXEC_nat : integer;
  variable MVTYPE_exec : std_logic_vector(1 downto 0);
  variable dsp_taken_branch_wires : std_logic_vector(harc_range);  
  variable MVSIZE_exec: std_logic_vector(Addr_Width downto 0);

  variable rs1_to_sc_nat : integer;
  variable rs2_to_sc_nat : integer;
  variable dsp_sci_req_lat                : std_logic_vector(((ACCL_NUM)*(SPM_NUM))-1 downto 0);
  variable dsp_to_sc_lat              : std_logic_vector(((ACCL_NUM)*(SPM_NUM)*(2))-1 downto 0);
    begin
  harc_EXEC_nat := to_integer(unsigned(harc_EXEC));

  MVTYPE_exec := MVTYPE(3  + (harc_EXEC_nat)*(4) downto  2 + (harc_EXEC_nat)*(4));
  MVSIZE_exec := MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));

  MVSIZE_exec := MVSIZE(((harc_EXEC_nat+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(harc_EXEC_nat));

    rs1_to_sc_nat := to_integer(unsigned(rs1_to_sc));
    rs2_to_sc_nat := to_integer(unsigned(rs2_to_sc));

    dsp_except_condition_wires(h)  := '0';
    dsp_taken_branch_wires(h)      := '0';
    dsp_except_condition(h) <= '0';
    dsp_taken_branch(h)     <= '0';
    overflow_rs1_sc(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))             <= (others => '0');
    overflow_rs2_sc(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))             <= (others => '0');
    overflow_rd_sc(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))              <= (others => '0');
            busy_excp_hand(h) <= '0';
    dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h))        <= dsp_except_data_in(((h+1)*(32))-1 downto (32)*(h));

    dsp_to_sc_lat((h+1)*(SPM_NUM)*(2) -1 downto (h)*(SPM_NUM)*(2)) := (others => '0');
    dsp_sc_read_addr(((h+1)*(2)*(Addr_Width))-1 downto (h)*(2)*(Addr_Width)) <= (others => '0');
    nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= state_DSP(((h+1)*(2))-1 downto (2)*(h));

    dsp_sci_req_lat((h+1)*(SPM_NUM)-1 downto (SPM_NUM)*(h)) := (others => '0');

    if dsp_instr_req(h) = '1' or busy_DSP_internal_lat(h) = '1' then
        if state_DSP(((h+1)*(2))-1 downto (2)*(h)) = dsp_init then

          ---------------------------------------------------------------------------------------------------------------------
          --  ███████╗██╗  ██╗ ██████╗██████╗ ████████╗    ██╗  ██╗ █████╗ ███╗   ██╗██████╗ ██╗     ██╗███╗   ██╗ ██████╗   --
          --  ██╔════╝╚██╗██╔╝██╔════╝██╔══██╗╚══██╔══╝    ██║  ██║██╔══██╗████╗  ██║██╔══██╗██║     ██║████╗  ██║██╔════╝   --
          --  █████╗   ╚███╔╝ ██║     ██████╔╝   ██║       ███████║███████║██╔██╗ ██║██║  ██║██║     ██║██╔██╗ ██║██║  ███╗  --
          --  ██╔══╝   ██╔██╗ ██║     ██╔═══╝    ██║       ██╔══██║██╔══██║██║╚██╗██║██║  ██║██║     ██║██║╚██╗██║██║   ██║  -- 
          --  ███████╗██╔╝ ██╗╚██████╗██║        ██║       ██║  ██║██║  ██║██║ ╚████║██████╔╝███████╗██║██║ ╚████║╚██████╔╝  --
          --  ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝        ╚═╝       ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝   --
          ---------------------------------------------------------------------------------------------------------------------

          overflow_rs1_sc(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= std_logic_vector('0' & unsigned(RS1_Data_IE(Addr_Width -1 downto 0)) + unsigned(MVSIZE_exec) -1);
          overflow_rs2_sc(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h)) <= std_logic_vector('0' & unsigned(RS2_Data_IE(Addr_Width -1 downto 0)) + unsigned(MVSIZE_exec) -1);
          overflow_rd_sc(((h+1)*(Addr_Width + 1))-1 downto (Addr_Width + 1)*(h))  <= std_logic_vector('0' & unsigned(RD_Data_IE(Addr_Width  -1 downto 0)) + unsigned(MVSIZE_exec) -1);
          if MVSIZE_exec = (0 to Addr_Width => '0') then
            null;
          --elsif MVSIZE(1  + (harc_EXEC)*(Addr_Width + 1) downto  0 + (harc_EXEC)*(Addr_Width + 1)) /= "00" and MVTYPE_exec = "10" then  -- Set exception if the number of bytes are not divisible by four
          elsif MVSIZE_exec(1 downto  0) /= "00" and MVTYPE_exec = "10" then  -- Set exception if the number of bytes are not divisible by four
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h)) <= ILLEGAL_VECTOR_SIZE_EXCEPT_CODE;
          elsif MVSIZE((harc_EXEC_nat)*(Addr_Width + 1) + 0) /= '0' and MVTYPE_exec = "01" then            -- Set exception if the number of bytes are not divisible by two
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';
            dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h)) <= ILLEGAL_VECTOR_SIZE_EXCEPT_CODE;
          elsif (rs1_to_sc  = "100" and vec_read_rs1_ID = '1') or
            (rs2_to_sc  = "100" and vec_read_rs2_ID = '1') or
             rd_to_sc   = "100" then     -- Set exception for non scratchpad access
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h)) <= ILLEGAL_ADDRESS_EXCEPT_CODE;
          elsif rs1_to_sc = rs2_to_sc and vec_read_rs1_ID = '1' and vec_read_rs2_ID = '1' then               -- Set exception for same read access
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h)) <= READ_SAME_SCARTCHPAD_EXCEPT_CODE;    
          elsif (overflow_rs1_sc((h)*(Addr_Width + 1) + Addr_Width) = '1' and vec_read_rs1_ID = '1') or (overflow_rs2_sc((h)*(Addr_Width + 1) + Addr_Width) = '1' and  vec_read_rs2_ID = '1') then -- Set exception if reading overflows the scratchpad's address
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h)) <= SCRATCHPAD_OVERFLOW_EXCEPT_CODE;
          elsif overflow_rd_sc((h)*(Addr_Width + 1) + Addr_Width) = '1'  and vec_write_rd_ID = '1' then           -- Set exception if reading overflows the scratchpad's address, scalar writes are excluded
            dsp_except_condition_wires(h) := '1';
            dsp_taken_branch_wires(h)     := '1';    
            dsp_except_data_wire(((h+1)*(32))-1 downto (32)*(h)) <= SCRATCHPAD_OVERFLOW_EXCEPT_CODE;
          else
            if halt_hart(h) = '0' then
              nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_exec;
            else
              nextstate_DSP(((h+1)*(2))-1 downto (2)*(h)) <= dsp_halt_hart;
            end if;
            busy_excp_hand(h) <= '1';
          end if;

          if rs1_to_sc /= "100" and spm_rs1 = '1' and halt_hart(h) = '0' then
            if rs1_to_sc_nat < SPM_NUM and rs1_to_sc_nat >= 0 then
              dsp_sci_req_lat((h)*(SPM_NUM) + rs1_to_sc_nat) := '1';
              dsp_to_sc_lat((h)*(SPM_NUM)*(2) + (rs1_to_sc_nat)*(2) + 0) := '1';
            end if;
            dsp_sc_read_addr(((0+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(0) + (h)*(2)*(Addr_Width)) <= RS1_Data_IE(Addr_Width-1 downto 0);
          end if;
          if rs2_to_sc /= "100" and spm_rs2 = '1' and rs1_to_sc /= rs2_to_sc and halt_hart(h) = '0' then   -- Do not send a read request if the second operand accesses the same spm as the first,
            if rs2_to_sc_nat < SPM_NUM and rs2_to_sc_nat >= 0 then
              dsp_sci_req_lat((h)*(SPM_NUM) + rs2_to_sc_nat) := '1';
              dsp_to_sc_lat((h)*(SPM_NUM)*(2) + rs2_to_sc_nat*(2) + 1) := '1';
            end if;
            dsp_sc_read_addr(((1+1)*(Addr_Width))-1 + (h)*(2)*(Addr_Width) downto (Addr_Width)*(1) + (h)*(2)*(Addr_Width)) <= RS2_Data_IE(Addr_Width-1 downto 0);
          end if;
        end if;
      end if;

    dsp_except_condition(h) <= dsp_except_condition_wires(h);
    dsp_taken_branch(h)     <= dsp_taken_branch_wires(h);
    dsp_sci_req(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h)) <= dsp_sci_req_lat(((h+1)*(SPM_NUM))-1 downto (SPM_NUM)*(h));
    dsp_to_sc(((h+1)*(SPM_NUM)*(2))-1 downto (h)*(SPM_NUM)*(2)) <= dsp_to_sc_lat((h+1)*(SPM_NUM)*(2) -1 downto (h)*(SPM_NUM)*(2));

  end process EXCPT;
  end generate EXCPT_replicated;


end EXCPT_STG;
