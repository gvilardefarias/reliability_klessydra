import numpy as np
import random

random.seed(21)

FU = 2
file_name = "data.h"
def_file = "data_def.h"

def sieve_primes(n):
    sieve = [True] * (n + 1)
    sieve[0] = sieve[1] = False
    for i in range(2, int(n**0.5) + 1):
        if sieve[i]:
            for j in range(i*i, n+1, i):
                sieve[j] = False
    return [i for i, prime in enumerate(sieve) if prime]

primes = sieve_primes(100000)

def gen_bin_with50_1s(bit_length):
    if bit_length % 2 != 0:
        raise ValueError("Bit length must be even for 50% 1s and 50% 0s.")
    
    num_ones = bit_length // 2
    num_zeros = bit_length // 2
    
    # Create a list with the required number of 1s and 0s
    bits = [1] * num_ones + [0] * num_zeros
    
    # Shuffle to randomize the order
    random.shuffle(bits)
    
    # Convert the bit list to an integer
    binary_string = ''.join(map(str, bits))
    return int(binary_string, 2)


def mat2str(mat, mat_name):
    n_row = len(mat)
    try:
        n_col = len(mat[0])
    except:
        n_col = 1

    if n_col > 1:
        mat_str = f"unsigned int {mat_name}[{n_row}][{n_col}] = {{"
    else:
        mat_str = f"unsigned int {mat_name}[{n_row}] = {{"

    for i in range(n_row):
        for j in range(n_col):
            if n_col > 1:
                mat_str += f"{mat[i][j]}"
            else:
                mat_str += f"{mat[i]}"
            if j < n_col - 1:
                mat_str += ", "
        if i < n_row - 1:
            mat_str += ", "
    mat_str += "};\n"

    return mat_str

def gen_patterns(vec_type, size, FU=FU):
    v_1 = []
    v_2 = []
    A = []
    B = []

    if vec_type == "chess":
        v_1 = [0xAAAAAAAA, 0xAAAAAAAA] * FU
        v_2 = [0x55555555, 0x55555555] * FU
    elif vec_type == "max_in":
        v_1 = [0xFFFFFFFF, 0xFFFFFFFF] * FU
        v_2 = [0x00000000, 0x00000000] * FU
    elif vec_type == "max_out":
        v_1 = [0xFFFFFFFF, 0x00000001] * FU
        v_2 = [0x00000000, 0xFFFFFFFE] * FU
    elif vec_type == "max_inter":
        v_1 = [0xFFFFFFFF, 0x00010001] * FU
        v_2 = [0x00000000, 0xFFFEFFFE] * FU
    elif vec_type == "nick1":
        # Format A * B & C * D
        v_1 = [0x3B317B33, 0xF93D5D1F, 0x9FFFE6BF, 0x6EFA8DAF]
        v_2 = [0xE5CF28F7, 0x37EF07EB, 0xFFFFAEAE, 0xB517D301]
    elif vec_type == "nick2":
                #2DEC1F76_20030006_6FFFB7F7_FD27AAA8
                #92132089_FFFFFFF9_7FFFB6BE_D7FFFFFF
        v_1 = [0xFD27AAA8, 0x20030006, 0x6FFFB7F7, 0x2DEC1F76]
        v_2 = [0xD7FFFFFF, 0xFFFFFFF9, 0x7FFFB6BE, 0x92132089]
    elif vec_type == "nick3":
                #A4030403_37FFFFFF_F553AAAA_5FFFFFFF
                #DBFFFBFF_C8030001_5FFFBFFF_73DFAAA9
        v_1 = [0x5FFFFFFF, 0x37FFFFFF, 0xF553AAAA, 0xA4030403]
        v_2 = [0x73DFAAA9, 0xC8030001, 0x5FFFBFFF, 0xDBFFFBFF]
    elif vec_type == "nick3_1":
        v_1 = [0x5FFFFFFF, 0x37FFFFFF] * FU
        v_2 = [0x73DFAAA9, 0xC8030001] * FU
    elif vec_type == "nick3_2":
        v_1 = [0xF553AAAA, 0xA4030403] * FU
        v_2 = [0x5FFFBFFF, 0xDBFFFBFF] * FU
    elif vec_type == "nick3_BE":
                #FFFFFFFA_5555CAAF_FFFFFFEC_C020C025
                #9555FBCE_FFFDFFFA_8000C013_FFDFFFDB
        v_1 = [0xC020C025, 0x5555CAAF, 0xFFFFFFEC, 0xFFFFFFFA]
        v_2 = [0xFFDFFFDB, 0xFFFDFFFA, 0x8000C013, 0x9555FBCE]
    elif vec_type == "nick4":
                #0B0279F6_BFFFD7FF
                #F4FF860B_7FFFFFFF
        v_1 = [0xBFFFD7FF, 0x0B0279F6] * FU
        v_2 = [0x7FFFFFFF, 0xF4FF860B] * FU
    elif vec_type == "prim":
        random.seed(21)
        for i in range(size):
            A.append(random.choice(primes))
            B.append(random.choice(primes))
        return (A, B)
    elif vec_type == "gab50":
        random.seed(21)
        for i in range(size):
            A.append(gen_bin_with50_1s(32))
            B.append(gen_bin_with50_1s(32))
        return (A, B)
    else:
        print("Invalid vector type.")

    for i in range(size//FU):
        if i % 2 == 0:
            for j in range(FU):
                A.append(v_1[0 + 2*j])
                B.append(v_1[1 + 2*j])
                #print(j)
        else:
            for j in range(FU):
                A.append(v_2[0 + 2*j])
                B.append(v_2[1 + 2*j])
    return (A, B)


with open(file_name, "w") as f:
    with open(def_file, "w") as f_def:
        counter = 0 
        for vec_type in ["chess", "max_in", "max_out", "max_inter", "nick3_1", "nick3_2", "prim", "gab50"]:
            f_def.write(f"#define {vec_type} {counter}\n")
            counter += 1
            for fu in [2,8]:
                if fu == 2:
                    size = 4096
                else:
                    size = 4096
                A, B = gen_patterns(vec_type, size, fu)
                f.write(f"#if PATTERN_TYPE == {vec_type} && SIMD == {fu}\n")
                f.write(f"#define V_SIZE {size}\n\n")
                f.write(mat2str(A, "A"))
                f.write(mat2str(B, "B"))
                f.write(f"#endif\n\n")

print("Dataset generated successfully.")