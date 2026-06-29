#include <stdio.h>
#include "dataset.h"

void mat_mul(unsigned int m1[N_ROW_1][N_COL_1], unsigned int m2[N_COL_1][N_COL_2], unsigned int m_out[N_ROW_1][N_COL_2]) {
    int n = N_ROW_1;
    int m = N_COL_1;
    int u = N_COL_2;

    for (int i = 0; i < n; i++){
        for (int j = 0; j < u; j++){
            m_out[i][j] = 0;
            for (int k = 0; k < m; k++) {
                m_out[i][j] += m1[i][k] * m2[k][j];
            }
        }
    }
}

void mat_trans(unsigned int m[][N_COL_2], int n_row, int n_col, unsigned int m_out[][N_COL_1]) {
    for (int i = 0; i < n_row; i++){
        for (int j = 0; j < n_col; j++){
            m_out[j][i] = m[i][j];
        }
    }
}

int main(){
    unsigned int m_ref[N_ROW_1][N_COL_2];
    unsigned int m_ref_trans[N_COL_2][N_ROW_1];
    unsigned int m_trans[N_COL_2][N_COL_1];

    mat_mul(m1, m2, m_ref);
    //mat_trans(m2, N_COL_1, N_COL_2, m_trans);

    FILE *ref_file = fopen("ref.h", "w");

    if (ref_file == NULL) {
        printf("Error opening file!\n");
        return 1;
    }

    fprintf(ref_file, "unsigned int ref_mat[%d][%d] = {", N_ROW_1, N_COL_2);
    for (int i = 0; i < N_ROW_1; i++) {
        for (int j = 0; j < N_COL_2; j++) {
            fprintf(ref_file, "%u", m_ref[i][j]);
            if (i != N_ROW_1 - 1 || j != N_COL_2 - 1) {
                fprintf(ref_file, ", ");
            }
        }
    }
    fprintf(ref_file, "};\n");

    fprintf(ref_file, "\nunsigned int m2_trans[%d][%d] = {", N_COL_2, N_COL_1);
    for(int i = 0; i < N_COL_2; i++) {
        for (int j = 0; j < N_COL_1; j++) {
            fprintf(ref_file, "%u", m2[j][i]);
            if (i != N_COL_2 - 1 || j != N_COL_1 - 1) {
                fprintf(ref_file, ", ");
            }
        }
    }
    fprintf(ref_file, "};\n");

    fclose(ref_file);

    return 0;
}