import os
import sys
import argparse
import warnings

#Local variables
PARSER_FILE = "parser.sv"
PARSER_MODULE = "parser"
run_commnads = 0

# Initialize the parser
parser = argparse.ArgumentParser()

# Define optional arguments with default values
parser.add_argument("-d", "--debug_mode", type=int, default=0, help="Enable/disable debug mode (default: 0)")
parser.add_argument("-f", "--file_name", type=str, default="rwims.din", help="Input File Name (default: rwims.din)")

# Parse the arguments
args = parser.parse_args()

# Check whether the input file is available or not
if not os.path.exists(args.file_name):
    file_name = "rwims.din"
    warnings.warn("[WARNING] Executing the default input file as the mentioned input file is NOT AVAILABLE in the directory!")
    run_commnads = 1
else:
    file_name = args.file_name
    run_commnads = 1
    
if run_commnads == 1:
	os.system("vlib work")
	os.system("vlog -coveropt 3 +acc +cover "+PARSER_FILE)
	os.system('vsim -coverage -novopt '+PARSER_MODULE+' -sv_seed random -c -do "run -all; exit" +TRACE_FILE='+file_name)
    