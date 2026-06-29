from ctypes import c_int32
import numpy as np
import argparse
import random

file_name = "conv_dataset.h"

seed = 0

A_ORDER = 4*16 
NUM_KERNELS = 5

parser = argparse.ArgumentParser(description="Generate convolution dataset")
parser.add_argument('--a_order', type=int, default=A_ORDER, help='Order of the square matrix A')
parser.add_argument('--seed', type=int, default=seed, help='Random seed for reproducibility')
args = parser.parse_args()
A_ORDER = args.a_order
seed = args.seed     # Seed -1 for random values in a range

random.seed(seed)

def gen_mat(rows, cols):
    mat = []
    for i in range(rows):
        row = []
        for j in range(cols):
            if seed >= 0:
                row.append(c_int32(random.getrandbits(32)).value)
            else:
                row.append(random.randint(-2**10, 2**10))
        mat.append(row)
    return mat


def mat2str(mat, mat_name, array = False):
    n_row = len(mat)
    n_col = len(mat[0])

    if array:
        mat_str = f"int {mat_name}[{n_row*n_col}] = {{\n"
    else:
        mat_str = f"int {mat_name}[{n_row}][{n_col}] = {{"
    for i in range(n_row):
        for j in range(n_col):
            mat_str += f"{mat[i][j]}"
            if j < n_col - 1:
                mat_str += ", "
        if i < n_row - 1:
            mat_str += ",\n"
    mat_str += "};\n"

    return mat_str

def def2str(def_name, def_value):
    return f"#define {def_name} {def_value}\n"

image = gen_mat(A_ORDER, A_ORDER)

kernels = """int kernels[NUM_KERNELS*3*3] = {
    0, 0, 0,
    0, 1, 0,
    0, 0, 0,\n
    -1, -1, -1,
    0, 0, 0,
    1, 1, 1,\n
    -1, 0, 1,
    -1, 0, 1,
    -1, 0, 1,\n
    4, 4, 4,
    4, 4, 4,
    4, 4, 4,\n
    0, -1, 0,
    -1, 5, -1,
    0, -1, 0
};\n"""


with open(file_name, "w") as f:
    f.write(def2str("A_ORDER", A_ORDER))
    f.write(def2str("NUM_KERNELS", NUM_KERNELS))

    f.write(kernels)

    f.write(mat2str(image, "image", True))

print(f"Dataset generated successfully with A_ORDER={A_ORDER} and seed={seed}.")