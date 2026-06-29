#include<stdlib.h> 
#include<float.h>  
#include<stdio.h>
#include<time.h>
#include<math.h>

//Klessydra lib
#include"dsp_functions.h"
#include"functions.h"
#include"klessydra_defs.h"

#include "dataset.h"
#include "ref.h"

#define SPM_MAX 64*32
#define SIZE_OF_INT 4

int 	performance=0;
int 	perf=0;
int* 	ptr_perf = &perf;
int perf_results[4]={0};

void start_count(){
	performance=0;
	int cnt_en=0;
  __asm__(	
						// resetto registri
						"csrrw zero, 0xB00, 	zero;"
						"csrrw zero, 0xB02, 	zero;"
						"csrrw zero, 0xB06, 	zero;"
						"csrrw zero, 0xB07, 	zero;"
						//abilito tutto
						// "li %[cnt_en], 0x00000FF3;"
						"li %[cnt_en], 0x00000063;"
						"csrrw zero, 0x7A0, %[cnt_en];"
						:
						:[cnt_en] "r" (cnt_en)	);

	__asm__ volatile("addi x0, x0, 0x0FF"); // Instruction marker
}
void finish_count(){
	__asm__ volatile("addi x0, x0, 0x0FF"); // Instruction marker

	__asm__("csrrw zero, 0x7A0, 0x00000000");
	
	__asm__("csrrw %[perf], 0xB00, zero;"
      "sw %[perf], 0(%[ptr_perf]);"
      :
      :[perf] "r" (perf), 	[ptr_perf] "r" (ptr_perf)
      );
	perf_results[0]=perf;//CICLI
	__asm__("csrrw %[perf], 0xB02, zero;"
		"sw %[perf], 0(%[ptr_perf]);"
		:
		:[perf] "r" (perf), 	[ptr_perf] "r" (ptr_perf)
		);
	perf_results[1]=perf;//ISTRUZIONI

	__asm__("csrrw %[perf], 0xB06, zero;"
		"sw %[perf], 0(%[ptr_perf]);"
		:
		:[perf] "r" (perf), 	[ptr_perf] "r" (ptr_perf)
		);
	perf_results[2]=perf;//Load
	
	__asm__("csrrw %[perf], 0xB07, zero;"
		"sw %[perf], 0(%[ptr_perf]);"
		:
		:[perf] "r" (perf), 	[ptr_perf] "r" (ptr_perf)
		);
	perf_results[3]=perf;//Store
			
			
	performance=perf;
	printf("Fine_Conteggio:\t");
	for (int i =0 ; i <4; i++){ 
		printf("{%d}=%d\t",i,perf_results[i]);
		perf_results[i]=0;
	}
	printf("\n");
	perf=0;
	performance=0;
}

int m_out[N_ROW_1][N_COL_2];
int zero=0;

int main(){
	int n=N_ROW_1;
	int m=N_COL_1;
	int u=N_COL_2;
	int m2_div = m*u/SPM_MAX;
	int scl=n/(3);
	int offset[3]={0,0,0};
	//Matrix initialization
	for(int i=0;i<n;i++){
		for(int j=0;j<u;j++){
			m_out[i][j]=0;
		}
	}
	__asm__("csrw 0x300, 0x8;" );//Enable interrupts for all threads
	__asm__("csrrw zero, mcycle, zero");
	CSR_MVSIZE(SPM_MAX*SPM_MAX*SIZE_OF_INT);
	if(Klessydra_get_coreID()==0){
		kbcast((void *)spmaddrA, (void *)zero);
	}
	else if(Klessydra_get_coreID()==1){
		kbcast((void *)spmaddrB, (void *)zero);
	}
	else if(Klessydra_get_coreID()==2){
		kbcast((void *)spmaddrC, (void *)zero);
	}
	sync_barrier();
	sync_barrier_reset();		
	sync_barrier_thread_registration();

	CSR_MVSIZE(m*SIZE_OF_INT);
	if(Klessydra_get_coreID()==0){
		start_count();
		kmemld((void *)((int *)spmaddrA), &m1[0][0],  SIZE_OF_INT*(m*scl));

		for(int i=0;i<scl;i++){
			kmemld((void *)((int *)spmaddrB), &m2_trans[0][0],  SIZE_OF_INT*(u*m/2));
			for(int j=0;j<u/2;j++){
				kdotp((void *)((int *)spmaddrC + j),(void *)((int *)spmaddrB + j*m),(void *)((int *)spmaddrA + i*m));
			}

			kmemld((void *)((int *)spmaddrB), &m2_trans[N_COL_2/2][0],  SIZE_OF_INT*(u*m/2));
			for(int j=u/2;j<u;j++){
				kdotp((void *)((int *)spmaddrC + j),(void *)((int *)spmaddrB + (j - u/2)*m),(void *)((int *)spmaddrA + i*m));
			}

			kmemstr(&m_out[i][0],  (void *)((int *)spmaddrC),  u*SIZE_OF_INT);
		}
	}
	if(Klessydra_get_coreID()==1){
		kmemld((void *)((int *)spmaddrA), &m1[scl][0],  SIZE_OF_INT*(m*scl));

		for(int i=0;i<scl;i++){
			kmemld((void *)((int *)spmaddrB), &m2_trans[0][0],  SIZE_OF_INT*(u*m/2));
			for(int j=0;j<u/2;j++){
				kdotp((void *)((int *)spmaddrC + j),(void *)((int *)spmaddrB + j*m),(void *)((int *)spmaddrA + i*m));
			}

			kmemld((void *)((int *)spmaddrB), &m2_trans[N_COL_2/2][0],  SIZE_OF_INT*(u*m/2));
			for(int j=u/2;j<u;j++){
				kdotp((void *)((int *)spmaddrC + j),(void *)((int *)spmaddrB + (j - u/2)*m),(void *)((int *)spmaddrA + i*m));
			}

			kmemstr(&m_out[i + scl][0],  (void *)((int *)spmaddrC),  u*SIZE_OF_INT);
		}
	}
	if(Klessydra_get_coreID()==2){
		kmemld((void *)((int *)spmaddrA), &m1[2*scl][0],  SIZE_OF_INT*(n*m - 2*m*scl));
		
		for(int i=0;i<n - 2*scl;i++){
			kmemld((void *)((int *)spmaddrB), &m2_trans[0][0],  SIZE_OF_INT*(u*m/2));
			for(int j=0;j<u/2;j++){
				kdotp((void *)((int *)spmaddrC + j),(void *)((int *)spmaddrB + j*m),(void *)((int *)spmaddrA + i*m));
			}

			kmemld((void *)((int *)spmaddrB), &m2_trans[N_COL_2/2][0],  SIZE_OF_INT*(u*m/2));
			for(int j=u/2;j<u;j++){
				kdotp((void *)((int *)spmaddrC + j),(void *)((int *)spmaddrB + (j - u/2)*m),(void *)((int *)spmaddrA + i*m));
			}

			kmemstr(&m_out[i + 2*scl][0],  (void *)((int *)spmaddrC),  u*SIZE_OF_INT);
		}
	}
	sync_barrier_reset();		
	sync_barrier_thread_registration();
	sync_barrier();

	if (Klessydra_get_coreID() == 0){
		finish_count();

		int pass = 1;
		for (int i = 0; i < n; i++){
			for (int j = 0; j < u; j++){
				if (m_out[i][j] != ref_mat[i][j]){
					pass = 0;
					printf("Error in [%d][%d]: %d != %d\n", i, j, m_out[i][j], ref_mat[i][j]);
					break;
				}
			}
		}
		if(pass == 1){
			printf("Test passed\n");
		}
		else{
			printf("Test failed\n");
		}

		return 0;
	}
	else
	{
		__asm__("wfi;");
	}

	
	return 0;
}