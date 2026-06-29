import numpy as np
import random
random.seed(2)

FU = 3 # Number of functional units

file_name = "dataset.h"

N_ROW_1 = 4*16
N_COL_1 = 4*16
N_COL_2 = 4*16
N_COL_3 = 4*16
N_COL_4 = 4*16

def gen_mat(rows, cols):
    mat = []
    for i in range(rows):
        row = []
        for j in range(cols):
            row.append(random.randint(0, 2**31 - 1))
            #row.append(0)
        mat.append(row)
    return mat

def mat2str(mat, mat_name):
    n_row = len(mat)
    n_col = len(mat[0])

    mat_str = f"unsigned int {mat_name}[{n_row}][{n_col}] = {{"
    for i in range(n_row):
        for j in range(n_col):
            mat_str += f"{mat[i][j]}"
            if j < n_col - 1:
                mat_str += ", "
        if i < n_row - 1:
            mat_str += ",\n"
    mat_str += "};\n"

    return mat_str


m1 = np.array(gen_mat(N_ROW_1, N_COL_1))
m2 = np.array(gen_mat(N_COL_1, N_COL_2))
m3 = np.array(gen_mat(N_COL_3, N_COL_3)) # Generating m3 transposed
m4 = np.array(gen_mat(N_COL_4, N_COL_4)) # Generating m3 transposed

# Force values on matrix
def standard1(m1, m2):
    m1[0,:] = 0x00000000

    m1[1,:] = 0x00000000
    m2[:,1] = 0x00000000
    m1[1,0] = 0x00000001
    m2[0,1] = 0xFFFFFFFF

    m1[2,:] = 0x11111111

    m2[:,3] = 0xFFFFFFFF

    #m1[2][:] = [0x00000000] * N_COL_1
    #m2[:][2] = [0x00000000] * N_COL_1
    #m1[2][0] = 0xFF000000
    #m2[0][2] = 0x00001100
    #m1[2][1] = 0x0F000000
    #m2[1][2] = 0x00000001
    #m1[2][2] = 0x000F0000
    #m2[2][2] = 0x00000100
    #m1[2][3] = 0x00FF0000
    #m2[3][2] = 0x00000011

    for i in range(FU):
        m1[6][i] = 0xFFFFFFFF
        m2[i][6] = 0x00000001

        m1[7][i] = 0xFFFFFFFF
        m2[i][7] = 0x11111111

        m1[8][i] = 0x11111111
        m2[i][8] = 0xFFFFFFFF

        m1[9][i] = 0x00000000
        m2[i][9] = 0x11111111

        m1[10][i] = 0x11111111
        m2[i][10] = 0x00000000

        m1[11][i] = 0x00000000
        m2[i][11] = 0x00000001

        m1[12][i] = 0xFFFFFFFF
        m2[i][12] = 0x00000000

        m1[13][i] = 0x00000000
        m2[i][13] = 0xFFFFFFFF

        m1[14][i] = 0xFFFFFFFF
        m2[i][14] = 0xFFFFFFFF

        m1[15][i] = 0xFFFFFFFF
        m2[i][15] = 0x01010101

def standard2(m1, m2):
    m1[0,:] = 0x00000000
    for i in range(FU):
        m1[i+FU-1,:] = 0x00000000
        m1[i+FU-1,i] = 0x00000001

        m1[i+2*FU-1,:] = 0x00000000
        m1[i+2*FU-1,i] = 0x00010000

        m1[i+3*FU-1,:] = 0x00000000
        m1[i+3*FU-1,i] = 0x0000FFFF

    m2[:,0] = [0x00000000]
    for i in range(FU):
        m2[i][1] = 0x0000FFFF
        m2[i][2] = 0xFFFF0000
        m2[i][3] = 0x00000001
        m2[i][4] = 0x00001000
        m2[i][5] = 0xFFFFFFFF
        m2[i][6] = 0x00010000
        m2[i][7] = 0x00010001

def standard3(m1, m2):
    m1[0,:] = 0x00000000
    m1[1,0:FU] = 0x0000FFFF
    
    for i in range(FU):
        m1[i+2,:] = 0x00000000
        m1[i+2,i] = 0x00000001

    m2[:,0] = 0x00000000
    for i in range(FU):
        m2[i,1] = 0xFFFFFFFF

        m2[i,2] = 0x00010001

def standard4(m1, m2):
    m1[0,:] = 0x00000000
    m1[1,0:FU] = 0xFFFFFFFF
    
    for i in range(FU):
        m1[i+2,:] = 0x00000000
        m1[i+2,i] = 0x00000001

    m2[:,0] = 0x00000000
    for i in range(FU):
        m2[i,1] = 0xFFFFFFFF
        m2[i,2] = 0x00010001
        m2[i,3] = 0x00001000


#standard2(m1, m2)

with open(file_name, "w") as f:
    f.write(f"#define N_ROW_1 {N_ROW_1}\n")
    f.write(f"#define N_COL_1 {N_COL_1}\n")
    f.write(f"#define N_COL_2 {N_COL_2}\n\n")
    f.write(f"#define N_COL_3 {N_COL_3}\n\n")
    f.write(f"#define N_COL_4 {N_COL_4}\n\n")

    f.write(mat2str(m1, "m1"))
    f.write(mat2str(m2, "m2"))
    f.write(mat2str(m3, "m3"))
    f.write(mat2str(m4, "m4"))

print("Dataset generated successfully.")