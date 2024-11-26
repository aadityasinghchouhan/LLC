#Makefile
PKG=../PKG/*
TB=../TB/cache.sv
TB_MODULE=cache

TRACE_FILE ?= rwims.din
DEBUG_MODE ?= 0
VERBOSITY ?= NONE

lib :
	vlib work
	@echo "---------------------------------------------"
	@echo "TRACE_FILE is $(TRACE_FILE)"
	@echo "---------------------------------------------"
	
cmp :
	vlog -coveropt 3 +acc +cover $(PKG) $(TB)

sim :
	vsim -coverage -novopt $(TB_MODULE) -sv_seed random -c -do "run -all; exit"

sim_arg:
	vsim -coverage -novopt $(TB_MODULE) -sv_seed random -c -do "run -all; exit" +TRACE_FILE=$(TRACE_FILE) +DEBUG_MODE=$(DEBUG_MODE) +VERBOSITY=$(VERBOSITY)

all : lib cmp sim
all_arg : lib cmp sim_arg
