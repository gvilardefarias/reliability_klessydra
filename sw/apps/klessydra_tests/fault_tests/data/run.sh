python3 gen_conv_dataset.py
python3 gen_dataset.py && gcc calc_ref.c -o calc_ref && ./calc_ref
