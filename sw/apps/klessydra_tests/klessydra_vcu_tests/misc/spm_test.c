#include <stdio.h>
#include "dsp_functions.h"

#define SPM_ADDR 0x10000000
int test_val_ld;
int dummy;
int test_val_sw;

int main() {
	test_val_ld = 0xDEADBEEF;
	dummy = 0x12345678;
	/*
	if (Klessydra_get_coreID()==0) {
		int spm_addr = SPM_ADDR;
		int test_val_ld = 0xDEADBEEF;
		int test_val_sw;

		kmemld(SPM_ADDR, &test_val_ld, 4);
		kmemstr(&test_val_sw, SPM_ADDR, 4);

		if (test_val_ld == test_val_sw) {
			printf("\nTEST PASSED\n");
		}
		else {
			printf("MISMATCH: kmemld_word = %x, kmemstr_word = %x", test_val_ld, test_val_sw);
			printf("\nTEST FAILED\n");
		}
	}
	else {
		__asm__("csrrw zero, mstatus, 8;" "wfi;");
	}
	*/
	sync_barrier();
	sync_barrier_reset();		
	sync_barrier_thread_registration();
	if (Klessydra_get_coreID()==0) {
		kmemld(SPM_ADDR, &test_val_ld, 4);
	}
	sync_barrier();
	sync_barrier_reset();		
	sync_barrier_thread_registration();
	if (Klessydra_get_coreID()==1) {
		//kmemld(SPM_ADDR+32, &dummy, 4);

		kmemstr(&test_val_sw, SPM_ADDR, 4);

		if (test_val_ld == test_val_sw) {
			printf("\nTEST PASSED\n");
		}
		else {
			printf("MISMATCH: kmemld_word = %x, kmemstr_word = %x", test_val_ld, test_val_sw);
			printf("\nTEST FAILED\n");
		}
	}
	sync_barrier();
	sync_barrier_reset();		
	sync_barrier_thread_registration();

	return 0;
}