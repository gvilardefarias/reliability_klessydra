#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "dsp_functions.h"
#include "functions.h"
#include "klessydra_defs.h"
#include "data_def.h"
#include "pattern_def.h"

#define SIMD 8
#define PATTERN_TYPE gab50
#include "data.h"

#define MARKER 1
#define CHECK 0
#define PERF 0

#define DATA_TYPE 2 // 0:int8 1:int16 2:int32

#define SIZE_OF_INT 4
#define SPM_MAX 64

unsigned int out[V_SIZE];

int performance = 0;
int perf[3] = {0, 0, 0};
int *ptr_perf[3];
int perf_results[3][4] = {0};

void add_marker(){
	__asm__ volatile("addi x0, x0, 0x0FF"); // Instruction marker
}

void start_count()
{
	performance = 0;
	int cnt_en = 0;
	__asm__(
		// resetto registri
		"csrrw zero, 0xB00, 	zero;"
		"csrrw zero, 0xB02, 	zero;"
		"csrrw zero, 0xB06, 	zero;"
		"csrrw zero, 0xB07, 	zero;"
		// abilito tutto
		//  "li %[cnt_en], 0x00000FF3;"
		"li %[cnt_en], 0x00000063;"
		"csrrw zero, 0x7A0, %[cnt_en];"
		:
		: [cnt_en] "r"(cnt_en));

	add_marker();
}
int finish_count()
{
	add_marker();

	__asm__("csrrw zero, 0x7A0, 0x00000000");

	int i = Klessydra_get_coreID();

	__asm__("csrrw %[perf], 0xB00, zero;"
			"sw %[perf], 0(%[ptr_perf]);"
			:
			: [perf] "r"(perf[i]), [ptr_perf] "r"(ptr_perf[i]));
	perf_results[i][0] = perf[i]; // CICLI
	__asm__("csrrw %[perf], 0xB02, zero;"
			"sw %[perf], 0(%[ptr_perf]);"
			:
			: [perf] "r"(perf[i]), [ptr_perf] "r"(ptr_perf[i]));
	perf_results[i][1] = perf[i]; // ISTRUZIONI

	__asm__("csrrw %[perf], 0xB06, zero;"
			"sw %[perf], 0(%[ptr_perf]);"
			:
			: [perf] "r"(perf[i]), [ptr_perf] "r"(ptr_perf[i]));
	perf_results[i][2] = perf[i]; // Load

	__asm__("csrrw %[perf], 0xB07, zero;"
			"sw %[perf], 0(%[ptr_perf]);"
			:
			: [perf] "r"(perf[i]), [ptr_perf] "r"(ptr_perf[i]));
	perf_results[i][3] = perf[i]; // Store

	return perf_results;
}

int main(){
	__asm__("csrw 0x300, 0x8;" );// each thread enables it's own interrupt
  __asm__("csrrw zero, mcycle, zero");

		int *addrA = (int *)spmaddrA;
		int *addrB = (int *)spmaddrB;
		int *addrC = (int *)spmaddrC;
		int *addrD = (int *)spmaddrD;
		CSR_MVTYPE(DATA_TYPE);
		CSR_MVSIZE(V_SIZE*SIZE_OF_INT);

	sync_barrier_reset();
	sync_barrier_thread_registration();

	int th_id = Klessydra_get_coreID();
	if (th_id == 0) {
		kmemld((void *)((int *)addrA), &A[0], SIZE_OF_INT * V_SIZE);
		kmemld((void *)((int *)addrB), &B[0], SIZE_OF_INT * V_SIZE);
	}

#if PERF == 1
	start_count();
#endif
	sync_barrier_reset();
	sync_barrier_thread_registration();

	if (th_id == 0) {
		#if MARKER == 1
			add_marker();
		#endif

		for(int i = 0; i < SIMD * 2 + 1; i++){
			kvmul((void *)((int *)addrC), (void *)((int *)addrA), (void *)((int *)addrB));
		}

		#if MARKER == 1
			add_marker();
		#endif
	}

	sync_barrier();
	sync_barrier_thread_registration();
#if PERF == 1
		finish_count();
#endif

	if (th_id == 0) {
		#if CHECK == 1
			kmemstr((void *)((int *)out), (void *)((int *)addrC), SIZE_OF_INT * V_SIZE);

			for(int i = 0; i < V_SIZE; i++) {
				printf("%08X ", out[i]);
			}
		#endif
	}
#if PERF == 1
	if (th_id == 0){
		printf("\n");
		for (int i = 0; i < 1; i++){
			printf("Num_cycles (Mean):%d\n", (perf_results[0][i] + perf_results[1][i] + perf_results[2][i]) / 3);
			printf("Num_cycles 0:%d\n", perf_results[0][i]);
			printf("Num_cycles 1:%d\n", perf_results[1][i]);
			printf("Num_cycles 2:%d\n", perf_results[2][i]);
			// perf_results[i]=0;
		}
		printf("Num_instr 0:%d\n", perf_results[0][1]);
		printf("Num_instr 1:%d\n", perf_results[1][1]);
		printf("Num_instr 2:%d\n", perf_results[2][1]);
	}
#endif

	sync_barrier();
	sync_barrier_thread_registration();

    return 0;
}