include_directories(data)

#add_subdirectory(mul_1th_1accl)
#add_subdirectory(mul_3th_1accl)
#add_subdirectory(mul_3th_3accl)
#
#add_subdirectory(conv_1th_1accl)
#add_subdirectory(conv_3th_3accl)

add_subdirectory(matmul_1accl)
add_subdirectory(adhoc_1accl)
add_subdirectory(conv_1accl)

add_subdirectory(test_1accl)
add_subdirectory(test_fu_1accl)
add_subdirectory(test_maccl)

#add_subdirectory(conv_mul_2th_1accl)
#add_subdirectory(conv_mul_shf_2th_1accl)