#include<stdlib.h> 
#include<float.h>  
#include<stdio.h>
#include<time.h>
#include<math.h>
#include "dataset.h"

#define SPM_MAX 64
#define SIZE_OF_INT 4

#define RISCY
int perf0 = 0;
int final_perf0 = 777;
int *ptr_perf0 = &perf0;

int perf1 = 0;
int final_perf1 = 777;
int *ptr_perf1 = &perf1;

int perf3 = 0;
int final_perf3 = 777;
int *ptr_perf3 = &perf3;

int perf4 = 0;
int final_perf4 = 777;
int *ptr_perf4 = &perf4;


void start_count_riscy(){
			int enable_perf_cnt = 0;
			final_perf0=0;
			final_perf1=0;
			final_perf3=0;
			final_perf4=0;
			__asm__("csrrw zero, 0x780, zero;"  // reset cycle count
					"csrrw zero, 0x781, zero;"  // reset instruction count
					"csrrw zero, 0x785, zero;"  // reset memory load count
					"csrrw zero, 0x786, zero;"  // reset memory store count
					"li %[enable], 0x000003F3;"  // 
					"csrrw zero, 0x7A0, %[enable]" // enable performance counters
					:
					:[enable] "r" (enable_perf_cnt)
			);
}
void finish_count_riscy(){
			__asm__("csrrw zero, 0x7A0, 0x00000000;" // disable performance counters
					"csrrw %[perf0], 0x780, zero;"
					"sw %[perf0], 0(%[ptr_perf0]);"
					"csrrw %[perf1], 0x781, zero;"
					"sw %[perf1], 0(%[ptr_perf1]);"
					"csrrw %[perf3], 0x785, zero;"
					"sw %[perf3], 0(%[ptr_perf3]);"
					"csrrw %[perf4], 0x786, zero;"
					"sw %[perf4], 0(%[ptr_perf4]);"
					:
					:[perf0] "r" (perf0), [ptr_perf0] "r" (ptr_perf0),
					 [perf1] "r" (perf1), [ptr_perf1] "r" (ptr_perf1),
					 [perf3] "r" (perf3), [ptr_perf3] "r" (ptr_perf3),
					 [perf4] "r" (perf4), [ptr_perf4] "r" (ptr_perf4)
			);

			final_perf0=*(ptr_perf0);
			final_perf1=*(ptr_perf1);
			final_perf3=*(ptr_perf3);
			final_perf4=*(ptr_perf4);
}


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
}
int finish_count(){

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

int zero=0;

int main(){
	int n=N_ROW_1;
	int m=N_COL_1;
	int u=N_COL_2;
	int vect[u];
	int k,p;
	int m_out[n][u];
	for(int i=0;i<n;i++){
		for(int j=0;j<u;j++){
			m_out[i][j]=0;
			vect[j]=0;
		}
	}
	//#ifdef RISCY
	//start_count_riscy();
	//#endif
	start_count();
	for(int i=0;i<n;i++){
		for(int j=0;j<m;j++){
			for(int k=0;k<u;k++){
				vect[k]+=m1[i][j]*m2[j][k];
			}
			
		}
		for(int j=0;j<u;j++){
			m_out[i][j]=vect[j];
			vect[j]=0;
		}
	}
	//#ifdef RISCY
	//finish_count_riscy();
	//printf(" Cycle Count = %d \n Instruction Count = %d \n Load Count = %d \n Store Count = %d \n \n", final_perf0, final_perf1, final_perf3, final_perf4);
	//#endif
    
    finish_count();
    if(Klessydra_get_coreID()==0){
		for (int i =0 ; i <4; i++){ 
			printf("{%d}=%d\t",i,(perf_results[0][i]+perf_results[1][i]+perf_results[2][i])/3);
			//perf_results[i]=0;
		}
	}
	else {
		__asm__("csrw 0x300, 0x8;" );// each thread enables it's own interrupt
		__asm__("wfi;");
	}

	return 0;
}