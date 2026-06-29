#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "dsp_functions.h"
#include "functions.h"
#include "klessydra_defs.h"
#include "conv_dataset.h"
#include "dataset.h"
#include "ref.h"

#define CHECK 0
#define SIMD 4
#define RELU 1
#define PERF 1

#define TH_NUM 3
#define SIZE_OF_INT 4

#define SPM_MAX 64
#define SIZE_OF_INT 4

int matA0[A_ORDER*A_ORDER];
int matA1[A_ORDER*A_ORDER];
int matA2[A_ORDER*A_ORDER];
int dimension_A=A_ORDER*A_ORDER*sizeof(int);

//int matB[B_ORDER*B_ORDER] = {0};
//int dimension_B=B_ORDER*B_ORDER*sizeof(int);

unsigned int shf_data[SIMD*2] = {0x7FFFFFFF, 0x7FFFFFFF, 0x80000000, 0x80000000};
unsigned int relu_data[SIMD] = {0x7FFFFFFF, 0x7FFFFFFF};
unsigned int cmp_data0[SIMD*2] = {0x80808080, 0xFFFFFFFF, 0x7F7F7F7F, 0x00000000};
unsigned int cmp_data1[SIMD*2] = {0xFFFFFFFF, 0x80808080, 0x00000000, 0x7F7F7F7F};

int dimension_B = NUM_KERNELS*B_ORDER*B_ORDER*sizeof(int);

int output_compare0[NUM_KERNELS][A_ORDER*A_ORDER]={0};
int output_compare_s0[TH_NUM][NUM_KERNELS][A_ORDER*A_ORDER]={0};
int mat_second_A[3][A_ORDER][A_ORDER];

int azzero[SPM_MAX*SPM_MAX] = {0};
int sign;

int conv2D_out_scal=5;
int shift_pre=0;

unsigned int m_out32[TH_NUM][N_ROW_1][N_COL_2];

void convolution2D_Scaling(int size, int (*matrix)[size], int *kernel_tmp, int *out);
void convolution2D_SPM_off_NOB(void* spm_dest, void* spm_fm, void* spm_krn, void* spm_temp, int size);
void matrix_check( int* mat1, int* mat2, int size );
void relu_test(int size, int* mat);
  

int performance = 0;
int perf[3] = {0, 0, 0};
int *ptr_perf[3];
int perf_results[3][4] = {0};

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

	__asm__ volatile("addi x0, x0, 0x0FF"); // Instruction marker
}
int finish_count()
{
	__asm__ volatile("addi x0, x0, 0x0FF"); // Instruction marker

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
	int v_max = SPM_MAX*SPM_MAX*SIZE_OF_INT;

int main(){
	__asm__("csrw 0x300, 0x8;" );// each thread enables it's own interrupt
  __asm__("csrrw zero, mcycle, zero");

int n;
int m;
int u;
int dt_sz = SIMD*2;
unsigned int sub_out[N_ROW_1][N_COL_2];
unsigned int shft_out0[SIMD*6];
unsigned int shft_out1[SIMD*6];
unsigned int relu_out[SIMD];
unsigned int cmp_out0[SIMD*2];
unsigned int cmp_out1[SIMD*2];
unsigned int shf_out32[2][N_ROW_1][N_COL_2];
unsigned int shf_out16[2][N_ROW_1][N_COL_2];
unsigned int shf_out8 [2][N_ROW_1][N_COL_2];
unsigned int m_out8[N_ROW_1][N_COL_2];
int d_size;
int idx_i, idx_j;
int v_size;
unsigned int ops_out32[15][N_ROW_1][N_COL_2];
unsigned int ops_out16[15][N_ROW_1][N_COL_2];
unsigned int ops_out8 [15][N_ROW_1][N_COL_2];
unsigned int ops_mem[5][SPM_MAX][SPM_MAX];

	sync_barrier_reset();
	sync_barrier_thread_registration();

	int th_id = Klessydra_get_coreID();
		CSR_MVTYPE(0x00000002);

#if PERF == 1
	sync_barrier();
	sync_barrier_thread_registration();
	start_count();
#endif


	if(th_id==0){
		for(int i=0;i<SIMD;i++){
			shf_data[i]      = 0x7FFFFFFF;
			shf_data[i+SIMD] = 0x80000000;
			relu_data[i]     = 0x7FFFFFFF;
		}
		for(int i=0;i<SIMD/2;i++){
			cmp_data0[i*4]   = 0x80808080;
			cmp_data0[i*4+1] = 0xFFFFFFFF;
			cmp_data0[i*4+2] = 0x7F7F7F7F;
			cmp_data0[i*4+3] = 0x00000000;
			cmp_data1[i*4]   = 0xFFFFFFFF;
			cmp_data1[i*4+1] = 0x80808080;
			cmp_data1[i*4+2] = 0x00000000;
			cmp_data1[i*4+3] = 0x7F7F7F7F;
		}
	}

	//sync_barrier();
	//sync_barrier_thread_registration();


#if CHECK == 1
		for (int i = 0; i < A_ORDER; i++)
		{
			for (int j = 0; j < A_ORDER; j++)
			{
				mat_second_A[0][i][j] = image[i * A_ORDER + j];
			}
		}
#endif

		CSR_MVSIZE(v_max);
		kmemld((void*)spmaddrA,(void*)azzero, SPM_MAX*SPM_MAX*SIZE_OF_INT);
		kmemld((void*)spmaddrB,(void*)azzero, SPM_MAX*SPM_MAX*SIZE_OF_INT);
		kmemld((void*)spmaddrC,(void*)azzero, SPM_MAX*SPM_MAX*SIZE_OF_INT);
		kmemld((void*)spmaddrD,(void*)azzero, SPM_MAX*SPM_MAX*SIZE_OF_INT);

		//so i just use a quick function that do the trick
		CSR_MVSIZE(2*SIZE_OF_INT);
		kdotpps_v3((void*)spmaddrA,	(void*)spmaddrA,	(void*)spmaddrB, (void*) conv2D_out_scal);
		CSR_MVSIZE(dimension_A);
	
	    //--------------------------------------LOADING & PRESCALING--------------------------------------------------
		kmemld((void*)((int*)spmaddrB), (void*)kernels, dimension_B);
		kmemld((void*)((int*)spmaddrA), (void*)image, dimension_A);

 		n=N_ROW_1;
 		m=N_COL_1;
 		u=N_COL_2;

		//CSR_MVSIZE(v_max);
		//kbcast((void *)spmaddrA, (void *)azzero);

		d_size = u*m/4;

		//------------------------------------------CONVOLUTION-------------------------------------------------------
	for(int i=0; i<NUM_KERNELS; i++){
		convolution2D_SPM_off_NOB((void*)(	(int*)spmaddrC), (void*)(	(int*)spmaddrA), (void*)(	(int*)spmaddrB + i*B_ORDER*B_ORDER), (void*)(	(int*)spmaddrD ), A_ORDER);

		#if RELU == 1
			CSR_MVSIZE(dimension_A);
			krelu((void*)((int*)spmaddrC), (void*)((int*)spmaddrC));
		#endif

		kmemstr((void*)((int*)output_compare_s0 + i*A_ORDER*A_ORDER + th_id*A_ORDER*A_ORDER*NUM_KERNELS ),		
		 				(void*)((int*)spmaddrC ),
						SIZE_OF_INT*(	A_ORDER*A_ORDER));
	}

#if CHECK == 1
		CSR_MVTYPE(0x00000002);
#else
		CSR_MVTYPE(0x00000001);
#endif

	//kmemld((void *)spmaddrB, (void *)azzero, SPM_MAX*SPM_MAX*SIZE_OF_INT);
	kmemld((void *)spmaddrB, (void *)azzero, SPM_MAX*SPM_MAX*SIZE_OF_INT);
	//kmemld((void *)spmaddrD, (void *)azzero, SPM_MAX*SPM_MAX*SIZE_OF_INT);

	CSR_MVSIZE(m*SIZE_OF_INT);
	int *addrA = (int *)spmaddrA;
	int *addrB = (int *)spmaddrB;
	int *addrC = (int *)spmaddrC;

	kmemld((void *)((int *)addrA), &m2[0][0], SIZE_OF_INT * u * m);

	for (int i = 0; i < n; i++){
		for (int j = 0; j < m; j++){
			ksvmulrf((void *)((int *)addrC), (void *)((int *)addrA + j*u), m1[i][j]);
			kaddv((void *)((int *)addrB), (void *)((int *)addrB), (void *)((int *)addrC));
		}
		kmemstr(&m_out32[th_id][i][0], (void *)((int *)addrB), u * SIZE_OF_INT);
		kmemld((void *)((int *)addrB), (void *)azzero, m * SIZE_OF_INT);
	}

	kmemld((void *)((int *)addrB), &m1[0][0], SIZE_OF_INT * u * m);

		CSR_MVTYPE(0x00000001);
		CSR_MVSIZE(u*SIZE_OF_INT);
		CSR_MPSCLFAC(0x00000005);

		for(int i = 0;i < u;i++){
			ksubv((void *)((int *)addrC), (void *)((int *)addrA + (u-i-1)*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out16[0][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kaddv((void *)((int *)addrC), (void *)((int *)addrA + (u-i-1)*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out16[1][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kvred((void *)((int *)addrC), (void *)((int *)addrA + i*m));
			kmemstr((void *)((int *) &ops_out16[2][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			krelu((void *)((int *)addrC), (void *)((int *)addrA + i*m));
			kmemstr((void *)((int *) &ops_out16[3][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kvslt((void *)((int *)addrC), (void *)((int *)addrA + (u-i-1)*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out16[4][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			ksvslt((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out16[5][i]), (void *)((int *)addrC), SIZE_OF_INT * m);

			ksvaddrf((void *)((int *)addrC), (void *)((int *)addrA + i*m), m2[0][i]);
			kmemstr((void *)((int *) &ops_out16[8][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			ksvaddsc((void *)((int *)addrC), (void *)((int *)addrB + i*m), (void *) addrA + i);
			kmemstr((void *)((int *) &ops_out16[10][i]), (void *)((int *)addrC), SIZE_OF_INT * m);

			kdotp((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out16[13][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kdotpps((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out16[14][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
		}
		kbcast((void *)((int *)addrC), (void *)m2[0][3]);
		kmemstr((void *)((int *) &ops_out16[6][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		kvcp((void *)((int *)addrC), (void *)((int *)addrB + 2*m));
		kmemstr((void *)((int *) &ops_out16[7][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		kdotp((void *)((int *)addrC), (void *)((int *)addrA + 3*u), (void *)((int *)addrB + 2*u));
		kmemstr((void *)((int *) &ops_out16[12][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		kvmul((void *)((int *)addrC), (void *)((int *)addrA + 1*u), (void *)((int *)addrB + (u-2)*u));
		kmemstr((void *)((int *) &ops_out16[9][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		ksvmulsc((void *)((int *)addrC), (void *)((int *)addrA + (u-3)*m), m2[3][2]);
		kmemstr((void *)((int *) &ops_out16[11][0]), (void *)((int *)addrC), SIZE_OF_INT * m);

		CSR_MVTYPE(0x00000002);
		CSR_MPSCLFAC(0x00000000);
		m = m/2;
		u = u/2;
		CSR_MVSIZE(u*SIZE_OF_INT);
		for(int i = 0;i < u;i++){
			ksubv((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out32[0][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kaddv((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out32[1][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kvred((void *)((int *)addrC), (void *)((int *)addrA + i*m));
			kmemstr((void *)((int *) &ops_out32[2][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kvslt((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out32[4][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			ksvslt((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out32[5][i]), (void *)((int *)addrC), SIZE_OF_INT * m);

			ksvaddrf((void *)((int *)addrC), (void *)((int *)addrA + i*m), m1[i][1]);
			kmemstr((void *)((int *) &ops_out32[8][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			ksvaddsc((void *)((int *)addrC), (void *)((int *)addrB + i*m), (void *) addrA + i);
			kmemstr((void *)((int *) &ops_out32[10][i]), (void *)((int *)addrC), SIZE_OF_INT * m);

			kdotp((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out32[11][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kdotpps((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out32[12][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
		}
		CSR_MPSCLFAC(0x0000000F);
		for(int i = 0;i < u;i++){
			kdotpps((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + m*(u-1) - i*m));
			kmemstr((void *)((int *) &ops_out32[13][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
		}
		kbcast((void *)((int *)addrC), (void *)m1[3][0]);
		kmemstr((void *)((int *) &ops_out32[6][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		kvcp((void *)((int *)addrC), (void *)((int *)addrA + 2*m));
		kmemstr((void *)((int *) &ops_out32[7][0]), (void *)((int *)addrC), SIZE_OF_INT * m);

		kvmul((void *)((int *)addrC), (void *)((int *)addrA + 3*u), (void *)((int *)addrB + (u-1)*u));
		kmemstr((void *)((int *) &ops_out32[9][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		ksvmulrf((void *)((int *)addrC), (void *)((int *)addrA + 0*u), m1[1][u-3]);
		kmemstr((void *)((int *) &ops_out32[1][0]), (void *)((int *)addrC), SIZE_OF_INT * m);

		CSR_MVTYPE(0x00000000);
		CSR_MPSCLFAC(0x00000002);
		CSR_MVSIZE(u*SIZE_OF_INT);
		for(int i = 0;i < u;i++){
			kaddv((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out8[1][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kvred((void *)((int *)addrC), (void *)((int *)addrA + i*m));
			kmemstr((void *)((int *) &ops_out8[2][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			krelu((void *)((int *)addrC), (void *)((int *)addrA + i*m));
			kmemstr((void *)((int *) &ops_out8[3][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kvslt((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out8[4][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			ksvslt((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out8[5][i]), (void *)((int *)addrC), SIZE_OF_INT * m);

			ksvaddrf((void *)((int *)addrC), (void *)((int *)addrA + (u-1-i)*m), m1[i][i]);
			kmemstr((void *)((int *) &ops_out8[8][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			ksvaddsc((void *)((int *)addrC), (void *)((int *)addrB + i*m), (void *) addrA + i);
			kmemstr((void *)((int *) &ops_out8[10][i]), (void *)((int *)addrC), SIZE_OF_INT * m);

			kdotp((void *)((int *)addrC), (void *)((int *)addrA + (u-1)*m - i*m), (void *)((int *)addrB + i*m));
			kmemstr((void *)((int *) &ops_out8[13][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
			kdotpps((void *)((int *)addrC), (void *)((int *)addrA + i*m), (void *)((int *)addrB + 1 + i*m));
			kmemstr((void *)((int *) &ops_out8[14][i]), (void *)((int *)addrC), SIZE_OF_INT * m);
		}
		kbcast((void *)((int *)addrC), (void *)m2[1][2]);
		kmemstr((void *)((int *) &ops_out8[6][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		kvcp((void *)((int *)addrC), (void *)((int *)addrA + 2*m));
		kmemstr((void *)((int *) &ops_out8[7][0]), (void *)((int *)addrC), SIZE_OF_INT * m);

		ksvmulsc((void *)((int *)addrC), (void *)((int *)addrA + (u-3)*m), m2[1][2]);
		kmemstr((void *)((int *) &ops_out8[12][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		ksvmulrf((void *)((int *)addrC), (void *)((int *)addrA + 4*u), m1[u-2][0]);
		kmemstr((void *)((int *) &ops_out8[1][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		kvmul((void *)((int *)addrC), (void *)((int *)addrA + 0*u), (void *)((int *)addrB + (u-3)*u));
		kmemstr((void *)((int *) &ops_out8[9][0]), (void *)((int *)addrC), SIZE_OF_INT * m);
		ksvmulsc((void *)((int *)addrC), (void *)((int *)addrA + (u-4)*m), m2[2][1]);
		kmemstr((void *)((int *) &ops_out8[11][0]), (void *)((int *)addrC), SIZE_OF_INT * m);

		u = N_COL_1;
		m = N_COL_1;
		
		int *spmD_max = (int *)spmaddrD + SPM_MAX*SPM_MAX;
		CSR_MVSIZE(0);
		ksubv((void *)((int *) spmD_max - 1), (void *)((int *)spmD_max-2), (void *)((int *)spmaddrA + SPM_MAX*SPM_MAX -1));
		CSR_MVSIZE(1);
		kaddv((void *)((int *) spmD_max - 1), (void *)((int *)spmD_max-2), (void *)((int *)spmaddrA));
		kmemstr((void *)((int *) &ops_mem[0][0]), (void *)((int *)spmD_max - 1), SIZE_OF_INT * 1);
		CSR_MVSIZE(v_max);
		ksubv((void *)((int *)spmaddrD), (void *)((int *)spmaddrA), (void *)((int *)spmaddrB));
		kmemstr((void *)((int *) &ops_mem[1][0]), (void *)((int *)spmaddrD), v_max);


		CSR_MVSIZE(u/2*SIZE_OF_INT);

		for(int i = 0;i < u/2;i++){
			ksrav((void *)((int *)addrC + i*m), (void *)((int *)addrA + i*m), m1[0][i]);
		}
		kmemstr((void *)((int *)shf_out8[0]), (void *)((int *)addrC), SIZE_OF_INT * u/2 * m);
		for(int i = 0;i < u/2;i++){
			ksrlv((void *)((int *)addrC + i*m), (void *)((int *)addrA + i*m), m2[0][i]);
		}
		kmemstr((void *)((int *)shf_out8[1]), (void *)((int *)addrC), SIZE_OF_INT * u/2 * m);
		CSR_MVTYPE(0x00000001);
		for(int i = 0;i < u/2;i++){
			ksrav((void *)((int *)addrC + i*m), (void *)((int *)addrA + i*m), m1[1][i]);
		}
		kmemstr((void *)((int *)shf_out16[0]), (void *)((int *)addrC), SIZE_OF_INT * u/2 * m);
		for(int i = 0;i < u/2;i++){
			ksrlv((void *)((int *)addrC + i*m), (void *)((int *)addrA + i*m), m2[1][i]);
		}
		kmemstr((void *)((int *)shf_out16[1]), (void *)((int *)addrC), SIZE_OF_INT * u/2 * m);
		CSR_MVTYPE(0x00000002);
		for(int i = 0;i < u/2;i++){
			ksrav((void *)((int *)addrC + i*m), (void *)((int *)addrA + i*m), m1[2][i]);
		}
		kmemstr((void *)((int *)shf_out32[0]), (void *)((int *)addrC), SIZE_OF_INT * u/2 * m);
		for(int i = 0;i < u/2;i++){
			ksrlv((void *)((int *)addrC + i*m), (void *)((int *)addrA + i*m), m2[2][i]);
		}
		kmemstr((void *)((int *)shf_out32[1]), (void *)((int *)addrC), SIZE_OF_INT * u/2 * m);


		CSR_MVTYPE(0x00000000);
		CSR_MVSIZE(m*u/4*SIZE_OF_INT);

		kdotp((void *)((int *)addrC ),(void *)((int *)addrB),(void *)((int *)addrA));
		kmemstr(&m_out8[0][0],  (void *)((int *)addrC),  d_size);
		// ----------- Shifter ------------
		CSR_MVTYPE(0x00000002);
		CSR_MVSIZE(dt_sz * SIZE_OF_INT);

		kmemld((void *)((int *)addrA), &shf_data[0], SIZE_OF_INT * dt_sz);

		ksrav((void *)((int *)addrB), (void *)((int *)addrA), (int *)shift_pre);
		ksrlv((void *)((int *)addrC), (void *)((int *)addrA), (int *)shift_pre);

		kmemstr((void *)((int *)shft_out0), (void *)((int *)addrB), SIZE_OF_INT * dt_sz);
		kmemstr((void *)((int *)shft_out1), (void *)((int *)addrC), SIZE_OF_INT * dt_sz);

		CSR_MVTYPE(0x00000001);

		shift_pre = 0;

		ksrav((void *)((int *)addrB), (void *)((int *)addrA), (int *)shift_pre);
		ksrlv((void *)((int *)addrC), (void *)((int *)addrA), (int *)shift_pre);

		kmemstr((void *)((int *)shft_out0 + dt_sz), (void *)((int *)addrB), SIZE_OF_INT * dt_sz);
		kmemstr((void *)((int *)shft_out1 + dt_sz), (void *)((int *)addrC), SIZE_OF_INT * dt_sz);

		shift_pre = 15;

		ksrav((void *)((int *)addrB), (void *)((int *)addrA), (int *)shift_pre);
		ksrlv((void *)((int *)addrC), (void *)((int *)addrA), (int *)shift_pre);

		kmemstr((void *)((int *)shft_out0 + 2*dt_sz), (void *)((int *)addrB), SIZE_OF_INT * dt_sz);
		kmemstr((void *)((int *)shft_out1 + 2*dt_sz), (void *)((int *)addrC), SIZE_OF_INT * dt_sz);


		// --------- Comparator ---------
		CSR_MVTYPE(0x00000002);
		CSR_MVSIZE(SIZE_OF_INT * SIMD);

		kmemld((void *)((int *)addrC), (void *)(&relu_data[0]), SIZE_OF_INT * SIMD);
		krelu((void *)((int *)addrC), (void *)((int *)addrC));
		kmemstr((void *)((int *)relu_out), (void *)((int *)addrC), SIZE_OF_INT * SIMD);


		CSR_MVTYPE(0x00000000);
		CSR_MVSIZE(SIZE_OF_INT * SIMD * 2);

		kmemld((void *)((int *)addrA), (void *)(&cmp_data0[0]), SIZE_OF_INT * SIMD * 2);
		kmemld((void *)((int *)addrB), (void *)(&cmp_data1[0]), SIZE_OF_INT * SIMD * 2);

		kvslt((void *)((int *)addrC), (void *)((int *)addrA), (void *)((int *)addrB));
		kmemstr((void *)((int *)cmp_out0), (void *)((int *)addrC), SIZE_OF_INT * SIMD * 2);

		kvslt((void *)((int *)addrC), (void *)((int *)addrB), (void *)((int *)addrA));
		kmemstr((void *)((int *)cmp_out1), (void *)((int *)addrC), SIZE_OF_INT * SIMD * 2);

	
#if PERF == 1
	sync_barrier();
		finish_count();
	sync_barrier_thread_registration();
#endif


#if CHECK == 1
shift_pre = 0;
    if(th_id == 2) {
		for(int i=0; i<NUM_KERNELS; i++){
			convolution2D_Scaling(A_ORDER, mat_second_A[0],(int*)kernels + i*B_ORDER*B_ORDER, (int*)output_compare0 + i*A_ORDER*A_ORDER);
			//convolution2D_Scaling(A_ORDER, mat_second_A[0],(int*)matB + i*B_ORDER*B_ORDER, (int*)output_compare0 + i*A_ORDER*A_ORDER);

			#if RELU == 1
				relu_test(A_ORDER, output_compare0[i]);
			#endif
		}
    }
#endif

	sync_barrier();


#if CHECK == 1
	sync_barrier_thread_registration();
   if(th_id == 0) {
	 	for(int k=0;k<TH_NUM; k++){
			for(int i=0; i<NUM_KERNELS; i++){
				matrix_check(output_compare_s0[k][i],output_compare0[i], A_ORDER);
			}
		}
	} else if(th_id == 1) {
		int pass = 1;
	 	for(int k=0;k<TH_NUM; k++){
			for (int i = 0; i < n; i++){
				for (int j = 0; j < u; j++){
					if (m_out32[k][i][j] != ref_mat[i][j]){
						pass = 0;
						printf("Error in [%d][%d][%d]: %d != %d\n", k, i, j, m_out32[k][i][j], ref_mat[i][j]);
						break;
					}
				}
			}
		}
		if(pass == 1){
			printf("Mult test passed\n");
		}
		else{
			printf("Mult test failed\n");
		}
	}

	sync_barrier();
#endif

#if PERF == 1
	sync_barrier_thread_registration();
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
	sync_barrier();
#endif

    return 0;
}

//------------------------------------------------------------------------------------------------------------
// Functions
//------------------------------------------------------------------------------------------------------------

void relu_test(int size, int* mat1) {
	for(int i=0; i<size; i++) {
		for(int j=0; j<size; j++) {
			if(mat1[i*size+j] < 0) {
				mat1[i*size+j] = 0;
			}
		}
	}
}

void convolution2D_Scaling(int size, int (*matrix)[size], int *kernel_tmp, int *out)
{
	int print=0;
	int kernel[9];
	int conv2D_scaling_factor=shift_pre;
//	int conv2D_out_scal=conv2D_out_scal;
	for(int i=0;i<9;i++) {
    	kernel[i]=(kernel_tmp[i]>>conv2D_scaling_factor);
  }
	int i, j;
	int pt=0;
	///////////////////////////////////
	//scandisci tutta l'ultima						colonna	F
	j=(size-1);
	for(i = 1; i < size-1 ; i++)
	{
		pt=i*size+j;
		out[pt] +=	(((matrix[i-1][j-1]>>conv2D_scaling_factor) * kernel[0]) >> conv2D_out_scal) +
								(((matrix[i-1][j]	>>conv2D_scaling_factor)	* kernel[1]) >> conv2D_out_scal) +
								(((matrix[i][j-1]	>>conv2D_scaling_factor)	* kernel[3]) >> conv2D_out_scal) +
								(((matrix[i][j]	>>conv2D_scaling_factor)		* kernel[4]) >> conv2D_out_scal) +
								(((matrix[i+1][j-1]>>conv2D_scaling_factor) * kernel[6]) >> conv2D_out_scal) +
								(((matrix[i+1][j] >>conv2D_scaling_factor)	* kernel[7]) >> conv2D_out_scal);
	}
	if(print){
		printf("dopo kernel F\n");
		for (int rig=0;rig<size;rig++){
			for (int col=0;col<size;col++){
				printf("%d\t",out[rig*size+col]);
			}printf("\n");
		}
	}
		//printf("out[%d]=%d\n",pt,(int)out[pt]);
	///////////////////////////////////
													//alto sinistra A
	i=0;
	j=0;
	pt=i*size+j;
		out[pt] +=	(((matrix[i][j]	>>conv2D_scaling_factor)		* kernel[4])>>			conv2D_out_scal) 	 +
					(((matrix[i][j+1]>>conv2D_scaling_factor)		* kernel[5])>>			conv2D_out_scal)	 +
					(((matrix[i+1][j] >>conv2D_scaling_factor)		* kernel[7])>>			conv2D_out_scal)	 +
					(((matrix[i+1][j+1]>>conv2D_scaling_factor) 	* kernel[8])>>			conv2D_out_scal)	;
		//printf("out[%d]=%d\n",pt,(int)out[pt]);

	///////////////////////////////////
	//vertice alto a destra 						C
	i=0;
	j=(size-1);
	pt=i*size+j;
		out[pt] +=	(((matrix[i][j-1]>>conv2D_scaling_factor)		* kernel[3])>>			conv2D_out_scal) 	  +
					(((matrix[i][j]	>>conv2D_scaling_factor)		* kernel[4])>>			conv2D_out_scal) 	  +
					(((matrix[i+1][j-1]>>conv2D_scaling_factor) 	* kernel[6])>>			conv2D_out_scal) 	  +
					(((matrix[i+1][j] >>conv2D_scaling_factor)		* kernel[7])>>			conv2D_out_scal) 	 ;
		//printf("out[%d]=%d\n",pt,(int)out[pt]);

	///////////////////////////////////
	//in basso a 									sinistra G
	j=0;
	i=size-1;
	pt=i*size+j;
		out[pt] +=	(((matrix[i-1][j]	>>conv2D_scaling_factor)	* kernel[1])>>		conv2D_out_scal)     +
					(((matrix[i-1][j+1]>>conv2D_scaling_factor)		* kernel[2])>>		conv2D_out_scal)     +
					(((matrix[i][j]	>>conv2D_scaling_factor)		* kernel[4])>>		conv2D_out_scal)     +
					(((matrix[i][j+1]	>>conv2D_scaling_factor)	* kernel[5])>>		conv2D_out_scal)    ;
		//printf("out[%d]=%d\n",pt,(int)out[pt]);

	///////////////////////////////////
	//in basso a 									destra	I
	i=(size-1);
	j=size-1;
	pt=i*size+j;
		out[pt] +=	(((matrix[i-1][j-1]>>conv2D_scaling_factor) 	* kernel[0])>>		conv2D_out_scal)     +
					(((matrix[i-1][j]	>>conv2D_scaling_factor)	* kernel[1])>>		conv2D_out_scal)     +
					(((matrix[i][j-1]	>>conv2D_scaling_factor)	* kernel[3])>>		conv2D_out_scal)     +
					(((matrix[i][j]	>>conv2D_scaling_factor)		* kernel[4])>>		conv2D_out_scal)    ;
		//printf("out[%d]=%d\n",pt,(int)out[pt]);
	if(print){
		printf("dopo kernel F-ACGI\n");
		for (int rig=0;rig<size;rig++){
			for (int col=0;col<size;col++){
				printf("%d\t",out[rig*size+col]);
			}printf("\n");
		}
	}
	///////////////////////////////////
	//scandisci tutta la prima colonna 				D
	j=0;
	for(i = 1; i < size-1 ; i++)
	{
		pt=i*size+j;
		out[pt] +=	(((matrix[i-1][j]>>conv2D_scaling_factor)	* kernel[1])>>			conv2D_out_scal) 	   +
					(((matrix[i-1][j+1]>>conv2D_scaling_factor)	* kernel[2])>>			conv2D_out_scal) 	   +
					(((matrix[i][j]	>>conv2D_scaling_factor)	* kernel[4])>>			conv2D_out_scal) 	   +
					(((matrix[i][j+1]>>conv2D_scaling_factor)	* kernel[5])>>			conv2D_out_scal) 	   +
					(((matrix[i+1][j] >>conv2D_scaling_factor)	* kernel[7])>>			conv2D_out_scal) 	   +
					(((matrix[i+1][j+1]>>conv2D_scaling_factor) * kernel[8])>>			conv2D_out_scal) 	  ;
	}
		//printf("out[%d]=%d\n",pt,(int)out[pt]);
	if(print){
		printf("dopo kernel F-ACGI-D\n");
	for (int rig=0;rig<size;rig++){
		for (int col=0;col<size;col++){
			printf("%d\t",out[rig*size+col]);
			}printf("\n");
		}
	}
	///////////////////////////////////
	// kernel 										E centrale
	for (i = 1; i < size-1; i++)
	{
		for (j = 1; j < size-1; j++)
		{
			pt=i*size+j;
			out[pt] +=	(	(	(matrix[i-1][j-1]>>conv2D_scaling_factor) 	* kernel[0])>>		conv2D_out_scal)    +
						(	(	(matrix[i-1][j]	>>conv2D_scaling_factor)	* kernel[1])>>		conv2D_out_scal)    +
						(	(	(matrix[i-1][j+1]>>conv2D_scaling_factor)		* kernel[2])>>		conv2D_out_scal)    +
						(	(	(matrix[i][j-1]	>>conv2D_scaling_factor)	* kernel[3])>>		conv2D_out_scal)    +
						(	(	(matrix[i][j]	>>conv2D_scaling_factor)		* kernel[4])>>		conv2D_out_scal)    +
						(	(	(matrix[i][j+1]	>>conv2D_scaling_factor)	* kernel[5])>>		conv2D_out_scal)    +
						(	(	(matrix[i+1][j-1]>>conv2D_scaling_factor) 	* kernel[6])>>		conv2D_out_scal)    +
						(	(	(matrix[i+1][j] >>conv2D_scaling_factor)		* kernel[7])>>		conv2D_out_scal)    +
						(	(	(matrix[i+1][j+1]>>conv2D_scaling_factor) 	* kernel[8])>>		conv2D_out_scal)   ;
		}
	}
	if(print){
		printf("dopo kernel F-ACGI-D-E\n");
		for (int rig=0;rig<size;rig++){
			for (int col=0;col<size;col++){
				printf("%d\t",out[rig*size+col]);
			}printf("\n");
		}
	}
	///////////////////////////////////
	//scandisci tutta la prima riga tra i due		 vertici alti 	B
	i=0;
	for (j = 1; j < size-1; j++)
	{
		pt=i*size+j;
		out[pt] +=	(((matrix[i][j-1]>>conv2D_scaling_factor)	* kernel[3])>>			conv2D_out_scal) 	  +
					(((matrix[i][j]	>>conv2D_scaling_factor)	* kernel[4])>>			conv2D_out_scal) 	  +
					(((matrix[i][j+1]>>conv2D_scaling_factor)	* kernel[5])>>			conv2D_out_scal) 	  +
					(((matrix[i+1][j-1]>>conv2D_scaling_factor) * kernel[6])>>			conv2D_out_scal) 	  +
					(((matrix[i+1][j] >>conv2D_scaling_factor)	* kernel[7])>>			conv2D_out_scal) 	  +
					(((matrix[i+1][j+1]>>conv2D_scaling_factor) * kernel[8])>>			conv2D_out_scal) 	 ;
	}
		//printf("out[%d]=%d\n",pt,(int)out[pt]);
	if(print){
		printf("dopo kernel F-ACGI-D-E-B\n");
		for (int rig=0;rig<size;rig++){
			for (int col=0;col<size;col++){
				printf("%d\t",out[rig*size+col]);
			}printf("\n");
		}
	}
	///////////////////////////////////
	//scandisci tutta l'ultima riga tra i due vertici bassi	 H
	i=size-1;
	for (j = 1; j < size-1; j++)
	{
		pt=i*size+j;
		out[pt] +=	(((matrix[i-1][j-1]>>conv2D_scaling_factor) 	* kernel[0])>>		conv2D_out_scal)  +
					(((matrix[i-1][j]	>>conv2D_scaling_factor)	* kernel[1])>>		conv2D_out_scal)  +
					(((matrix[i-1][j+1]>>conv2D_scaling_factor)		* kernel[2])>>		conv2D_out_scal)  +
					(((matrix[i][j-1]	>>conv2D_scaling_factor)	* kernel[3])>>		conv2D_out_scal)  +
					(((matrix[i][j]	>>conv2D_scaling_factor)		* kernel[4])>>		conv2D_out_scal)  +
					(((matrix[i][j+1]	>>conv2D_scaling_factor)	* kernel[5])>>		conv2D_out_scal) ;
	}
		//printf("out[%d]=%d\n",pt,(int)out[pt]);
	if(print){
		printf("dopo kernel F-ACGI-D-E-B-H\n");
		for (int rig=0;rig<size;rig++){
			for (int col=0;col<size;col++){
				printf("%d\t",out[rig*size+col]);
			}printf("\n");
		}
	}
}

//base algorithm for check pourposes
void matrix_check( int* mat1, int* mat2, int size )
{
  int err=0;
	for(int i=0; i<size; i++)
	{
		for(int j=0; j<size; j++)
		{
			if ( *((int*)mat1+i*size+j) != *((int*)mat2+i*size+j) ) {
				//printf("\nERROR at elements [%d][%d]: %d != %d\n",i,j, *((int*)mat1+i*size+j), *((int*)mat2+i*size+j));
        err++;

			}
		}
	}
  if (err==0){
    printf("Conv Test passed\n");
  }
  else{
	printf("Conv Test error\n");
  }
}

void convolution2D_SPM_off_NOB(void* spm_dest, 	 void* spm_fm,	 void* spm_krn,	 void* spm_temp,  int size){
	int print=0;
  //Pointers to Spms and other index that i'll need for the convolution

	// void* spmaddrAoff= (void*)((int*)spm_fm + mem_off );
	void* spmaddrAoff= (void*)(spm_fm);
	void* spmaddrBoff= (void*)(spm_krn );
	void* spmaddrCoff= (void*)(spm_dest);
	void* spmaddrDoff= (void*)(spm_temp);

	void* dest_in_C;
  void* dest_in_B;
  void* dest_in_D;

  int k_element=0;
  int mat_int_shift=0; //internal shifting for properly pointing insied the spms while making kaddv

	int jump_kr_row=3; // determina il salto della riga per la matrice kernel zeropadded
	int kern_offset=0;
	int fm_offset=0;
  int zero=0;

	CSR_MVSIZE(size*size*SIZE_OF_INT);
	ksvmulrf((void*)spmaddrCoff,(void*)spmaddrCoff,(void*)zero);

	//______________________________sub_kernel F
  CSR_MVSIZE(2*SIZE_OF_INT);
	kern_offset	=	0;
	fm_offset= (size-1-1);
	for(int i=1; i< size-1;i++){
		dest_in_C	= (void*)spmaddrCoff + SIZE_OF_INT*(size*i)+ SIZE_OF_INT*(1)*(size-1);
		dest_in_D	= (void*)spmaddrDoff + SIZE_OF_INT*(size*i)+ SIZE_OF_INT*(1)*(size-1);
		kdotpps		(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(i-1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(0)*jump_kr_row+	kern_offset ) );
    kaddv(dest_in_C, dest_in_C, dest_in_D);
		kdotpps		(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(i)*size				+fm_offset	),	(void*) ( (int*)spmaddrBoff+(1)*jump_kr_row+	kern_offset )	);
    kaddv(dest_in_C, dest_in_C, dest_in_D);
		kdotpps		(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(i+1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(2)*jump_kr_row+	kern_offset )	);
		kaddv(dest_in_C, dest_in_C, dest_in_D);
	}


	// kern_offset	=	0;
	// fm_offset= (size-1-1);
	// for(int i=1; i< size-1;i++){
		// CSR_MVSIZE(2*SIZE_OF_INT);
		// dest_in_C	= (void*)spmaddrCoff + SIZE_OF_INT*(size*i)+ SIZE_OF_INT*(1)*(size-1);
		// dest_in_D	= (void*)spmaddrDoff + SIZE_OF_INT*(size*i)+ SIZE_OF_INT*(1)*(size-1);
		// kdotpps		(dest_in_D+4,			(void*)(	(int*)spmaddrAoff+	(i-1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(0)*jump_kr_row+	kern_offset ) );
		// kdotpps		(dest_in_D+8,			(void*)(	(int*)spmaddrAoff+	(i)*size				+fm_offset	),	(void*) ( (int*)spmaddrBoff+(1)*jump_kr_row+	kern_offset )	);
		// kdotpps		(dest_in_D+12,		(void*)(	(int*)spmaddrAoff+	(i+1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(2)*jump_kr_row+	kern_offset )	);
    // // kaddv(dest_in_C, dest_in_C, dest_in_D);
    // // kaddv(dest_in_C, dest_in_C, dest_in_D);
		// // kaddv(dest_in_C, dest_in_C, dest_in_D);
		// CSR_MVSIZE(3*SIZE_OF_INT);
		// kvred32(dest_in_C,dest_in_D);
	// }
// // int kbacst16_v2(void* rd, void* rs1, int size)
// // {
	// // __asm__(
		// // "csrw 0xBF0, %[size];"
		// // "kvred16 %[rd], %[rs1];"
		// // ://no output register
		// // :[size] "r" (size), [rd] "r" (rd), [rs1] "r" (rs1)
		// // :/*no clobbered registers*/
	// // );

	// // return 1;
// // }


  //______________________________sub_kernel___________A-C-G-I
	CSR_MVSIZE(2*SIZE_OF_INT);
  //______________________________sub_kernel A
	dest_in_C	=		(void*)spmaddrCoff + SIZE_OF_INT*(0)*(size-1); //[0]
	dest_in_D	=		(void*)spmaddrDoff + SIZE_OF_INT*(0)*(size-1);
	kern_offset	=	1;
	fm_offset		=	0;
	kdotpps(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(0)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(1)*jump_kr_row+	kern_offset ));
	kdotpps(dest_in_D+4,		(void*)(	(int*)spmaddrAoff+	(1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(2)*jump_kr_row+	kern_offset ));
	//______________________________sub_kernel C
	dest_in_C	=		(void*)spmaddrCoff + SIZE_OF_INT*(1)*(size-1); //[4]
	dest_in_D	=		(void*)spmaddrDoff + SIZE_OF_INT*(1)*(size-1);
	kern_offset	=	0;
	fm_offset		=	(size-1-1);
	kdotpps(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(0)*size			+ fm_offset	),	(void*) ( (int*)spmaddrBoff+(1)*jump_kr_row+	kern_offset ));
	kdotpps(dest_in_D-4,		(void*)(	(int*)spmaddrAoff+	(1)*size			+ fm_offset	),	(void*) ( (int*)spmaddrBoff+(2)*jump_kr_row+	kern_offset ));
	//______________________________sub_kernel G
	dest_in_C	=		(void*)spmaddrCoff + SIZE_OF_INT*(size)*(size-1); //[20]
	dest_in_D	=		(void*)spmaddrDoff + SIZE_OF_INT*(size)*(size-1);
	kern_offset	=	1;
	fm_offset		=	0;
	kdotpps(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(size-1-1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(0)*jump_kr_row+	kern_offset ));
	kdotpps(dest_in_D+4,		(void*)(	(int*)spmaddrAoff+	(size-1)	*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(1)*jump_kr_row+	kern_offset ));
	//______________________________sub_kernel I
	dest_in_C	=		(void*)spmaddrCoff + SIZE_OF_INT*(size+1)*(size-1); //[24]
	dest_in_D	=		(void*)spmaddrDoff + SIZE_OF_INT*(size+1)*(size-1);
	kern_offset	=	0;
	fm_offset		=	(size-1-1);
	kdotpps(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(size-1-1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(0)*jump_kr_row+	kern_offset ));
	kdotpps(dest_in_D-4,		(void*)(	(int*)spmaddrAoff+	(size-1)	*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(1)*jump_kr_row+	kern_offset ));

	// //______________________________sommo i parziali prodotti dei sub_kernels A-C-G-I
  	CSR_MVSIZE(1*SIZE_OF_INT);

	kaddv((void*)spmaddrCoff + SIZE_OF_INT*(0)*(size-1),	    	(void*)spmaddrCoff + SIZE_OF_INT*(0)*(size-1),	       	(void*)spmaddrDoff + SIZE_OF_INT*(0)*(size-1));
  kaddv((void*)spmaddrCoff + SIZE_OF_INT*(1)*(size-1),	    	(void*)spmaddrCoff + SIZE_OF_INT*(1)*(size-1),        	(void*)spmaddrDoff + SIZE_OF_INT*(1)*(size-1));
  kaddv((void*)spmaddrCoff + SIZE_OF_INT*(size)*(size-1),			(void*)spmaddrCoff + SIZE_OF_INT*(size)*(size-1),  			(void*)spmaddrDoff + SIZE_OF_INT*(size)*(size-1));
  kaddv((void*)spmaddrCoff + SIZE_OF_INT*(size+1)*(size-1),		(void*)spmaddrCoff + SIZE_OF_INT*(size+1)*(size-1),			(void*)spmaddrDoff + SIZE_OF_INT*(size+1)*(size-1));

  kaddv((void*)spmaddrCoff + SIZE_OF_INT*(0)*(size-1),	    	(void*)spmaddrCoff + SIZE_OF_INT*(0)*(size-1),	    	  	(void*)spmaddrDoff + SIZE_OF_INT*(0)*(size-1) + 4	);
  kaddv((void*)spmaddrCoff + SIZE_OF_INT*(1)*(size-1),	    	(void*)spmaddrCoff + SIZE_OF_INT*(1)*(size-1),      		 	(void*)spmaddrDoff + SIZE_OF_INT*(1)*(size-1) - 4	);
  kaddv((void*)spmaddrCoff + SIZE_OF_INT*(size)*(size-1),			(void*)spmaddrCoff + SIZE_OF_INT*(size)*(size-1),  				(void*)spmaddrDoff + SIZE_OF_INT*(size)*(size-1) +4	);
  kaddv((void*)spmaddrCoff + SIZE_OF_INT*(size+1)*(size-1),		(void*)spmaddrCoff + SIZE_OF_INT*(size+1)*(size-1),				(void*)spmaddrDoff + SIZE_OF_INT*(size+1)*(size-1) -4	);



	//______________________________sub_kernel D
  CSR_MVSIZE(2*SIZE_OF_INT);
	kern_offset	=	1;
	fm_offset		=	0;
	for(int i=1; i< size-1;i++){
		dest_in_C	= (void*)spmaddrCoff + SIZE_OF_INT*(size*i);
		dest_in_D	= (void*)spmaddrDoff + SIZE_OF_INT*(size*i);
		kdotpps(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(i-1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(0)*jump_kr_row+	kern_offset ));
		kaddv(dest_in_C, dest_in_C, dest_in_D);
		kdotpps(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(i)*size				+fm_offset	),	(void*) ( (int*)spmaddrBoff+(1)*jump_kr_row+	kern_offset ));
    kaddv(dest_in_C, dest_in_C, dest_in_D);
		kdotpps(dest_in_D,		(void*)(	(int*)spmaddrAoff+	(i+1)*size			+fm_offset	),	(void*) ( (int*)spmaddrBoff+(2)*jump_kr_row+	kern_offset ));
    kaddv(dest_in_C, dest_in_C, dest_in_D);
	}



  //______________________________sub_kernel E
  CSR_MVSIZE((size-2)*SIZE_OF_INT);
	for(int i=1; i< size-1;i++)
	{
		// dest_in_C	= (void*)(	(int*)	(spmaddrCoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT;
		// dest_in_D	= (void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT;
		k_element=0;
		for (int rw_pt=-1; rw_pt<2; rw_pt++) //rw_pt is an index i use to point to the correct row, regarding this loop that is executed three times
		//instead of making 9 different ksvmulrf
		{
			ksvmulsc((void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
        			  (void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+0 ),
                (void*)	( (int*)spmaddrBoff+k_element++) );

				ksrav((void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
								(void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
								(int*)conv2D_out_scal);

  		kaddv ((void*)(	(int*)	(spmaddrCoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
              (void*)(	(int*)	(spmaddrCoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
              (void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT);

			ksvmulsc((void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
        			  (void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+1 ),
                (void*)	( (int*)spmaddrBoff+k_element++) );

				ksrav((void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
								(void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
								(int*)conv2D_out_scal);

  		kaddv ((void*)(	(int*)	(spmaddrCoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
              (void*)(	(int*)	(spmaddrCoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
              (void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT);

			ksvmulsc((void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
        			  (void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+2 ),
                (void*)	( (int*)spmaddrBoff+k_element++) );

				ksrav((void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
								(void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
								(int*)conv2D_out_scal);

  		kaddv ((void*)(	(int*)	(spmaddrCoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
              (void*)(	(int*)	(spmaddrCoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT,
              (void*)(	(int*)	(spmaddrDoff)	) + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT);
		}
	}



  // //______________________________sub_kernel B
  // CSR_MVSIZE((size-2)*SIZE_OF_INT);
  for(int i=0; i< 1;i++)
  {
    dest_in_C	= (void*)spmaddrCoff  + 1*SIZE_OF_INT;
    dest_in_D	= (void*)spmaddrDoff  + 1*SIZE_OF_INT;
    k_element=3;
    for (int rw_pt=0; rw_pt<2; rw_pt++) //rw_pt is an index i use to point to the correct row, regarding this loop that is executed three times
    //instead of making 9 different ksvmulrf
    {
      ksvmulsc(dest_in_D,			(void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+0 ),	(void*)	( (int*)spmaddrBoff+k_element++) );
					ksrav(dest_in_D,	dest_in_D,	(int*)conv2D_out_scal);
      kaddv (dest_in_C, dest_in_C,  dest_in_D);
      ksvmulsc(dest_in_D,			(void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+1 ),	(void*)	( (int*)spmaddrBoff+k_element++) );
					ksrav(dest_in_D,	dest_in_D,	(int*)conv2D_out_scal);
      kaddv	(dest_in_C, dest_in_C,  dest_in_D);
      ksvmulsc(dest_in_D,			(void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+2 ),	(void*)	( (int*)spmaddrBoff+k_element++) );
					ksrav(dest_in_D,	dest_in_D,	(int*)conv2D_out_scal);
      kaddv (dest_in_C, dest_in_C,  dest_in_D);
    }
  }



	//______________________________sub_kernel H
  // CSR_MVSIZE((size-2)*SIZE_OF_INT);
	for(int i=size-1; i< size;i++)
	{
		dest_in_C	= (void*)spmaddrCoff + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT;
    dest_in_D	= (void*)spmaddrDoff + SIZE_OF_INT*(size*i)+1*SIZE_OF_INT;
		k_element=0;
		for (int rw_pt=-1; rw_pt<1; rw_pt++) //rw_pt is an index i use to point to the correct row, regarding this loop that is executed three times
		//instead of making 9 different ksvmulrf
		{
			ksvmulsc(dest_in_D,			(void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+0 ),	(void*)	( (int*)spmaddrBoff+k_element++) );
				ksrav(dest_in_D,	dest_in_D,	(int*)conv2D_out_scal);
      kaddv	(dest_in_C, dest_in_C, dest_in_D);
			ksvmulsc(dest_in_D,			(void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+1 ),	(void*)	( (int*)spmaddrBoff+k_element++) );
				ksrav(dest_in_D,	dest_in_D,	(int*)conv2D_out_scal);
      kaddv	(dest_in_C, dest_in_C, dest_in_D);
			ksvmulsc(dest_in_D,			(void*)	( (int*)spmaddrAoff + (i+rw_pt)*size	+2 ),	(void*)	( (int*)spmaddrBoff+k_element++) );
				ksrav(dest_in_D,	dest_in_D,	(int*)conv2D_out_scal);
      kaddv	(dest_in_C, dest_in_C, dest_in_D);
		}
	}

	CSR_MVSIZE(size*size*SIZE_OF_INT);
	ksvmulrf((void*)spmaddrDoff,(void*)spmaddrDoff,(void*)zero);
	// CSR_MVSIZE(3*3*SIZE_OF_INT);
	// ksvmulrf((void*)spmaddrBoff,(void*)spmaddrBoff,(void*)zero);
	// // kbcast((void*)spmaddrBoff,(void*)shift_spmB);
}
