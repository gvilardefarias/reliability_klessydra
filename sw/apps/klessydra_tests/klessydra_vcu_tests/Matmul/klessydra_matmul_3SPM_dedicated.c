#include<stdlib.h> 
#include<float.h>  
#include<stdio.h>
#include<time.h>
#include<math.h>

//Klessydra lib
#include"dsp_functions.h"
#include"functions.h"
#include"klessydra_defs.h"
//#include "mode.h"
#define SPM_MAX 64
#define SIZE_OF_INT 4
#define mode 0

#include "dataset.h"
#include "ref.h"

#if mode==1
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
    __asm__ volatile ("addi x0, x0, 0x0FF"); // Instruction marker
  }
  int finish_count(){
    __asm__ volatile ("addi x0, x0, 0x0FF"); // Instruction marker
  
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
  	/*printf("Fine_Conteggio:\t");
  	for (int i =0 ; i <4; i++){ 
  		printf("{%d}=%d\t",i,perf_results[i]);
  		perf_results[i]=0;
  	}
  	printf("\n");
  	perf=0;
  	performance=0;*/
   return perf_results;
  }
#else
  int 	performance=0;
  int 	perf[3]= {0,0,0};
  int* 	ptr_perf[3];
  int perf_results[3][4]={0};
  
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

    __asm__ volatile ("addi x0, x0, 0x0FF"); // Instruction marker
  }
  int finish_count(){
    __asm__ volatile ("addi x0, x0, 0x0FF"); // Instruction marker
  
  	__asm__("csrrw zero, 0x7A0, 0x00000000");
  	
  	int i = Klessydra_get_coreID();
  
  	__asm__("csrrw %[perf], 0xB00, zero;"
        "sw %[perf], 0(%[ptr_perf]);"
        :
        :[perf] "r" (perf[i]), 	[ptr_perf] "r" (ptr_perf[i])
        );
  	perf_results[i][0]=perf[i];//CICLI
  	__asm__("csrrw %[perf], 0xB02, zero;"
  		"sw %[perf], 0(%[ptr_perf]);"
  		:
  		:[perf] "r" (perf[i]), 	[ptr_perf] "r" (ptr_perf[i])
  		);
  	perf_results[i][1]=perf[i];//ISTRUZIONI
  
  	__asm__("csrrw %[perf], 0xB06, zero;"
  		"sw %[perf], 0(%[ptr_perf]);"
  		:
  		:[perf] "r" (perf[i]), 	[ptr_perf] "r" (ptr_perf[i])
  		);
  	perf_results[i][2]=perf[i];//Load
  	
  	__asm__("csrrw %[perf], 0xB07, zero;"
  		"sw %[perf], 0(%[ptr_perf]);"
  		:
  		:[perf] "r" (perf[i]), 	[ptr_perf] "r" (ptr_perf[i])
  		);
  	perf_results[i][3]=perf[i];//Store
  			
  	return perf_results;
  }
#endif

int zero=0;

int main(){

	#if mode==1
		//printf("Shared mode selected:"\n);

			int n=N_ROW_1;
			int m=N_COL_1;
			int u=N_COL_2;
			int k,p;
			int scl=SPM_MAX*SPM_MAX/(3*u);
			int offset[3]={0,0,0};
			//Matrix initialization
			int m_out[n][u];
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
			if(Klessydra_get_coreID()==0){
				start_count();
				CSR_MVSIZE(u*SIZE_OF_INT);
				for(int i=0;i<n;i++){
					k=0;
					p=0;
					kmemld((void *)((int *)spmaddrA), &m2[0][0],  SIZE_OF_INT*(u*scl));
					for(int j=0;j<m;j++){
						if(j%scl==0 & j!=0){
							p++;
							k=0;
							if(m-(p*scl)>scl){
								kmemld((void *)((int *)spmaddrA), &m2[j][0],  SIZE_OF_INT*(u*scl));
							}
							else{
								kmemld((void *)((int *)spmaddrA), &m2[j][0],  SIZE_OF_INT*((m-scl*p)*u));
							}
						}
						offset[1]=k*u;
						ksvmulrf((void *)((int *)spmaddrC),(void *)((int *)spmaddrA+offset[1]),m1[i][j]);
						kaddv((void *)((int *)spmaddrB),(void *)((int *)spmaddrB),(void *)((int *)spmaddrC));
						k++;
					}
					kmemstr(&m_out[i][0],  (void *)((int *)spmaddrB),  u*SIZE_OF_INT);
					kbcast((void *)((int *)spmaddrB),(void *)zero);
				}
			}
			if(Klessydra_get_coreID()==1){
				CSR_MVSIZE(u*SIZE_OF_INT);
				for(int i=0;i<n;i++){
					k=0;
					p=0;
					kmemld((void *)((int *)spmaddrA+u*scl), &m2[0][0],  SIZE_OF_INT*(u*scl));
					for(int j=0;j<m;j++){
						if(j%scl==0 & j!=0){
							p++;
							k=0;
							if(m-(p*scl)>scl){
								kmemld((void *)((int *)spmaddrA+u*scl), &m2[j][0],  SIZE_OF_INT*(u*scl));
							}
							else{
								kmemld((void *)((int *)spmaddrA+u*scl), &m2[j][0],  SIZE_OF_INT*((m-scl*p)*u));
							}
						}
						offset[1]=u*scl+k*u;
						ksvmulrf((void *)((int *)spmaddrC+u),(void *)((int *)spmaddrA+offset[1]),m1[i][j]);
						kaddv((void *)((int *)spmaddrB+u),(void *)((int *)spmaddrB+u),(void *)((int *)spmaddrC+u));
						k++;
					}
					kmemstr(&m_out[i][0],  (void *)((int *)spmaddrB+u),  u*SIZE_OF_INT);
					kbcast((void *)((int *)spmaddrB+u),(void *)zero);
				}
			}
			if(Klessydra_get_coreID()==2){
				CSR_MVSIZE(u*SIZE_OF_INT);
				for(int i=0;i<n;i++){
					k=0;
					p=0;
					kmemld((void *)((int *)spmaddrA+u*scl+u*scl), &m2[0][0],  SIZE_OF_INT*(u*scl));
					for(int j=0;j<m;j++){
						if(j%scl==0 & j!=0){
							p++;
							k=0;
							if(m-(p*scl)>scl){
								kmemld((void *)((int *)spmaddrA+u*scl+u*scl), &m2[j][0],  SIZE_OF_INT*(u*scl));
							}
							else{
								kmemld((void *)((int *)spmaddrA+u*scl+u*scl), &m2[j][0],  SIZE_OF_INT*((m-scl*p)*u));
							}
						}
						offset[1]=k*u+u*scl+u*scl;
						ksvmulrf((void *)((int *)spmaddrC+u+u),(void *)((int *)spmaddrA+offset[1]),m1[i][j]);
						kaddv((void *)((int *)spmaddrB+u+u),(void *)((int *)spmaddrB+u+u),(void *)((int *)spmaddrC+u+u));
						k++;
					}
					kmemstr(&m_out[i][0],  (void *)((int *)spmaddrB+u+u),  u*SIZE_OF_INT);
					kbcast((void *)((int *)spmaddrB+u+u),(void *)zero);
				}
			}
      
      	if(Klessydra_get_coreID()==0){
        finish_count();
        }
			sync_barrier_reset();		
			sync_barrier_thread_registration();
      sync_barrier();
   

 		if(Klessydra_get_coreID()==0){
			//performance=perf;
			printf("\n");
			printf("Num_cycles:%d\n",perf_results[0]);
			printf("\n");
			//perf=0;
			//performance=0;
	     //printf("Num_cycles:%d\n",n_cycle);

			int pass=1;
			for(int i=0;i<n;i++){
				for(int j=0;j<u;j++){
					if(m_out[i][j]!=ref_mat[i][j]){
						pass=0;
						printf("Error in [%d][%d] %d != %d\n",i,j,m_out[i][j],ref_mat[i][j]);
						break;
					}
					printf("%d ",m_out[i][j]);
				}
			}
			if(pass==1){
				printf("Test passed\n");
			} else{
				printf("Test failed\n");
			}
			return 0;
		}
		else {
			__asm__("wfi;");
		}
	
#else
		//printf("Dedicated mode selected:\n");
		ptr_perf[0] = &perf[0];
		ptr_perf[1] = &perf[1];
		ptr_perf[2] = &perf[2];


		int n=N_ROW_1;
		int m=N_COL_1;
		int u=N_COL_2;
		int k,p;
		int scl=SPM_MAX*SPM_MAX/u;
		int offset[3]={0,0,0};
		//Matrix initialization
		int m_out[n][u];
		for(int i=0;i<n;i++){
			for(int j=0;j<u;j++){
				m_out[i][j]=0;
			}
		}
		__asm__("csrw 0x300, 0x8;" );//Enable interrupts for all threads
		__asm__("csrrw zero, mcycle, zero");
		CSR_MVSIZE(SPM_MAX*SPM_MAX*SIZE_OF_INT);
		kbcast((void *)spmaddrA, (void *)zero);
		kbcast((void *)spmaddrB, (void *)zero);
		kbcast((void *)spmaddrC, (void *)zero);
		CSR_MVSIZE(u*SIZE_OF_INT);
		start_count();
		for(int i=0;i<n;i++){
			k=0;
			p=0;
			kmemld((void *)((int *)spmaddrA), &m2[0][0],  SIZE_OF_INT*(u*scl));
			for(int j=0;j<m;j++){
				if(j%scl==0 & j!=0){
					p++;
					k=0;
					if(m-(p*scl)>scl){
						kmemld((void *)((int *)spmaddrA), &m2[j][0],  SIZE_OF_INT*(u*scl));
					}
					else{
						kmemld((void *)((int *)spmaddrA), &m2[j][0],  SIZE_OF_INT*((m-scl*p)*u));
					}
				}
				offset[1]=k*u;
				ksvmulrf((void *)((int *)spmaddrC),(void *)((int *)spmaddrA+offset[1]),m1[i][j]);
				kaddv((void *)((int *)spmaddrB),(void *)((int *)spmaddrB),(void *)((int *)spmaddrC));
				k++;
			}
			kmemstr(&m_out[i][0],  (void *)((int *)spmaddrB),  u*SIZE_OF_INT);
			kbcast((void *)((int *)spmaddrB),(void *)zero);
		}
		finish_count();
		sync_barrier_reset();		
		sync_barrier_thread_registration();
		sync_barrier();
		
		if(Klessydra_get_coreID()==0){
			//performance=perf;
			printf("\n");
			for (int i =0 ; i <1; i++){ 
				printf("Num_cycles (Mean):%d\n",(perf_results[0][i]+perf_results[1][i]+perf_results[2][i])/3);
				printf("Num_cycles 0:%d\n",perf_results[0][i]);
				printf("Num_cycles 1:%d\n",perf_results[1][i]);
				printf("Num_cycles 2:%d\n",perf_results[2][i]);
				//perf_results[i]=0;
			}
			//perf=0;
			//performance=0;
	     //printf("Num_cycles:%d\n",n_cycle);
			
			int pass=1;
			for(int i=0;i<n;i++){
				for(int j=0;j<u;j++){
					if(m_out[i][j]!=ref_mat[i][j]){
						pass=0;
						break;
					}
				}
			}
			if(pass==1){
				printf("Test passed\n");
			} else{
				printf("Test failed\n");
			}

			return 0;
		}
		else {
			__asm__("wfi;");
		}
#endif	
}

