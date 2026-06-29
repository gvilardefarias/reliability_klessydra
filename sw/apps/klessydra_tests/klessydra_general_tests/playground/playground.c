// NOTE: This test is like a sketchpad where we try to compile and run random pieces of code

#include <stdio.h>
#include <functions.h>

//Klessydra lib
#include"dsp_functions.h"
#include"klessydra_defs.h"

int shift = 2;
int a[516];
int b[516];
int max_v1[4096];
int max_v2[4096];
int max_v3[4096];
int max_v4[4096];

int out1[4];
int out2[4];

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

int main()
{
    Klessydra_En_Int(); // enable irqs
    sync_barrier_reset();
    sync_barrier_thread_registration();
    
    if(Klessydra_get_coreID() == 0) {
        start_count();
        int save_msize = 4;
        int save_config = 0;

        CSR_MVSIZE(4096); // reset SPM size
        CSR_MVTYPE(0x00000002); // set type to int

        kmemstr((void *)((int *)max_v3), (void *)((int *)spmaddrA), 1024 * sizeof(int));
        kmemstr((void *)((int *)max_v4), (void *)((int *)spmaddrB), 1024 * sizeof(int));

        kmemld((void *)((int *)spmaddrA), &max_v1[0], 1024 * sizeof(int));
        kmemld((void *)((int *)spmaddrB), &max_v2[0], 1024 * sizeof(int));


        kvmul((void *)((int *)spmaddrA), (void *)((int *)spmaddrA), (void *)((int *)spmaddrB));

        kmemstr((void *)((int *)max_v4), (void *)((int *)spmaddrA), 1024 * sizeof(int));

        kmemld((void *)((int *)spmaddrA), &max_v3[0], 1024 * sizeof(int));
        kmemld((void *)((int *)spmaddrB), &max_v2[0], 1024 * sizeof(int));

        CSR_MVSIZE(save_msize); // reset SPM size
        CSR_MVTYPE(save_config); // set type to int

        finish_count();

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
    sync_barrier();
    
    /*
    CSR_MVSIZE(4*4); // reset SPM size
    sync_barrier_reset();
    sync_barrier_thread_registration();
    if(Klessydra_get_coreID() == 0) {
        kmemld((void *)((int *)spmaddrA), &a[0], 4 * sizeof(int));
        kmemld((void *)((int *)spmaddrB), &b[0], 4 * sizeof(int));

//        krelu((void *)((int *)spmaddrA), (void *)((int *)spmaddrA));
//        krelu((void *)((int *)spmaddrB), (void *)((int *)spmaddrB));
        //kaddv((void *)((int *)spmaddrA), (void *)((int *)spmaddrA), (void *)((int *)spmaddrB));
        //krelu((void *)((int *)spmaddrA), (void *)((int *)spmaddrA));
        kvmul((void *)((int *)spmaddrA), (void *)((int *)spmaddrA), (void *)((int *)spmaddrB));

        kmemstr((void *)((int *)out1), (void *)((int *)spmaddrA), 4 * sizeof(int));

        //for(int i = 0; i < 4; i++) {
        //    printf("%d\n", out1[i]);
        //}
    }
    sync_barrier();

    //printf("test");



    //float x = 1.0;
    //float y = 2.0;
    //float z1, z2, z3, z4;
    //asm(
    // "flw  f1, 0(%[p_x]);"
    // "flw  f2, 0(%[p_y]);"
    // "fadd.s f3, f1, f2;"
    // "fsub.s f4, f1, f2;"
    // "fmul.s f5, f1, f2;"
    // "fdiv.s f6, f1, f2;"
    // "fsw  f3, 0(%[p_z1]);"
    // "fsw  f4, 0(%[p_z2]);"
    // "fsw  f5, 0(%[p_z3]);"
    // "fsw  f6, 0(%[p_z4]);"
    // :
    // : [p_x] "r" (&x), [p_y] "r" (&y),
    //   [p_z1] "r" (&z1), [p_z2] "r" (&z2),
    //   [p_z3] "r" (&z3), [p_z4] "r" (&z4)
    //);

    //sync_barrier_thread_registration();
    //if (Klessydra_get_coreID() == 0) {
    //  printf("%d+%d=%d\n", (int)x, (int)y, (int)z1);
    //}
    //sync_barrier();


    //float z;
    //z = x + y;
    //sync_barrier_thread_registration();
    //if (Klessydra_get_coreID() == 0) {
    //  printf("%f+%f=%f\n", x, y, z);
    //}
    //sync_barrier();

    //Klessydra_En_Int(); // enable irqs

    //sync_barrier_thread_registration();
    //if (Klessydra_get_coreID() == 0) {
    //  printf("Hello World!!!!!\n");
    //}
    //sync_barrier();
    */
    return 0;
}
