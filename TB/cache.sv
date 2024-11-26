`timescale 1ns/1ps

`include "../PKG/defines.sv"

import trace_pkg::*;
import cache_struct_pkg::*;

module cache;

    //Declare physical address
    string file_name;                           //Variable to store filename input
    int input_file_open;                        //Variable to store open file content
    int output_file_open;                       //Variable to store open file content
    int line_count;
    int verbosity_in;
    string line;

    //Local variables
    int valid_cnt;
    int invalid_cnt;
    bit set_empty;
    bit set_full;
    bit tag_matched;


    //Declare cache memory
    cache_set_st cache_mem;

    //Function: Read command line arguments
    function void read_cmd_line_args();
        if($value$plusargs("DEBUG_MODE=%d", debug_mode_pkg))
        begin
            if(debug_mode_pkg == 1)
                display_val(DEBUG, "DEBUG_MODE is Enabled");
            else if(debug_mode_pkg == 0)
                display_val(DEBUG, "DEBUG_MODE is Disabled");
        end

        if($value$plusargs("TRACE_FILE=%0s", file_name))
            display_val(DEBUG, $sformatf("Input TRACE_FILE name is: %0s", file_name));
        else begin
            file_name = "rwims.din";
            display_val(DEBUG, $sformatf("Input TRACE_FILE name is: %0s",file_name));
        end

        if($value$plusargs("VERBOSITY=%0d", verbosity_in))
        begin
            $cast(verbosity_level, verbosity_in);
            $display("Verbosity is set to: %0d", verbosity_level);
        end
        else begin
            verbosity_level = NONE;
            $display("Verbosity is set to: %0s", verbosity_level);
        end
    endfunction: read_cmd_line_args

    //Function: Check whether the cache set is full or empty
    function void check_for_set_empty_full();
        set_full = 0;
        set_empty = 0;
        valid_cnt = 0;
        invalid_cnt = 0;

        for(int i=0; i<`NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
        begin
            if(cache_mem[set_val].cache_line[i].valid == 1)
            begin
                valid_cnt++;
            end
            if(cache_mem[set_val].cache_line[i].valid !== 1)
            begin
                invalid_cnt++;
            end
        end

        if(valid_cnt == `NUM_OF_WAYS_OF_ASSOCIATIVITY)
            set_full = 1;
        if(invalid_cnt == `NUM_OF_WAYS_OF_ASSOCIATIVITY)
            set_empty = 1;

        display_val(DEBUG, $sformatf("Valid Counts = %0d", valid_cnt));
        display_val(DEBUG, $sformatf("Invalid Counts = %0d", invalid_cnt));
    endfunction: check_for_set_empty_full


    //Procedural block to perform operation
    initial begin

        //Displaying the given data of cache memory
        display_given_data();

        //Function call to read command line arguments
        read_cmd_line_args();

        //Open input and output files
        input_file_open = $fopen($sformatf("../%s",file_name), "r");
        output_file_open = $fopen("../output.txt", "w");

        $fdisplay(output_file_open, "--------------------- PROJECT #9 ---------------------");
        $fdisplay(output_file_open, "-------------------- Parsed Data  --------------------");
        $fdisplay(output_file_open, "--------------- Input file : %s ---------------", file_name);
        $fdisplay(output_file_open, "------------------------------------------------------\n");

        //Initialize the cache memory
        initialize_cache_mem(cache_mem);

        while(!$feof(input_file_open))
        begin
            //Decode everyline of trace file and store them in cmd and address
            $fscanf(input_file_open, "%h %h", cmd, address);

            //Function call to assign cmd description
            cmd_description = assign_cmd_description(cmd);
            display_val(FULL, $sformatf("Command Description: %s", cmd_description));
            display_val(FULL, $sformatf("Command            : %h", cmd));
            display_val(FULL, $sformatf("Address            : %h\n", address));
            
            //Write to output file
            $fdisplay(output_file_open, "Command Description: %s", cmd_description);
            $fdisplay(output_file_open, "Command            : %h", cmd);
            $fdisplay(output_file_open, "Address            : %h", address);
            $fdisplay(output_file_open, "------------------------------------------------------\n");

            //Pushing back the new line content into queue array(class handle)
            address_slicing(address);

            //0 : read request from L1 data cache
            if(cmd == 0)
            begin
                $display("-----------------------------------------------------------------------------------\n");
                check_for_set_empty_full();
                tag_matched = 0;                //Initialized the value (It is just for internal logic)
                display_val(FULL, $sformatf("Addr = %0h, SET_FULL = %0b, SET_EMPTY = %0d", address, set_full, set_empty));

                //For loop - 1 (For READ-HIT and CONFLICT MISSES)
                for(int i=0; i < `NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
                begin
                    //display_val(MED, $sformatf("SET_EMPTY = %0d, SET_FULL = %0d", set_empty, set_full));
                    if(cache_mem[set_val].cache_line[i].valid == 1)           //Check if line is already valid or not, if yes, executing if loop
                    begin
                        if(set_full == 0 && cache_mem[set_val].cache_line[i].tag == tag_val)
                        begin
                            display_val(MED, $sformatf("\nTAG MATCHED! %0h = %0h", cache_mem[set_val].cache_line[i].tag, tag_val));
                            display_val(MED, $sformatf("1 - READ-HIT for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                            //Upadting PLRU bits
                            update_plru(i);
                            cache_mem[set_val].plru_bits = update_plru_temp;
                            display_val(MED, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                            tag_matched = 1;
                            cache_hit_cnt++;
                            cache_read_cnt++;
                            break;
                        end
                        else if(set_full == 1)
                        begin
                            for(int i=0; i < `NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
                            begin
                                if(tag_matched == 0 && cache_mem[set_val].cache_line[i].tag == tag_val)
                                begin
                                    display_val(MED, $sformatf("\nTAG MATCHED! %0h = %0h", cache_mem[set_val].cache_line[i].tag, tag_val));
                                    display_val(MED, $sformatf("2 - READ-HIT for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                                    //Upadting PLRU bits
                                    update_plru(i);
                                    cache_mem[set_val].plru_bits = update_plru_temp;
                                    display_val(MED, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                                    tag_matched = 1;
                                    break;
                                end
                            end
                                
                            if(tag_matched == 0 && cache_mem[set_val].cache_line[i].valid == 1 && cache_mem[set_val].cache_line[i].tag != tag_val)
                            begin
                                display_val(MED, $sformatf("CONFLICT READ-MISS for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                                victim_plru(update_plru_temp);
                                cache_mem[set_val].plru_bits = update_plru_temp;
                                cache_mem[set_val].cache_line[way_out].valid = 1;
                                cache_mem[set_val].cache_line[way_out].tag = tag_val;
                                break;
                            end
                        end
                    end
                end

                if(tag_matched == 1)
                begin
                    cache_hit_cnt++;
                    cache_read_cnt++;
                end 

                //For loop - 2 (For COMPULSORY MISSES)
                for(int i=0; i < `NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
                begin
                    if(tag_matched == 0)
                    begin
                        if(set_full == 0 && cache_mem[set_val].cache_line[i].valid !== 'h1)
                        begin
                            display_val(MED, $sformatf("\nCOMPULSORY READ-MISS for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                            //Make the valid bit one and assign tag values
                            cache_mem[set_val].cache_line[i].valid = 1;
                            cache_mem[set_val].cache_line[i].tag = tag_val;
                            display_val(MED, $sformatf("cache_mem[%0d].cache_line[%0d].valid = %0d", set_val, i, cache_mem[set_val].cache_line[i].valid));
                            display_val(MED, $sformatf("cache_mem[%0d].cache_line[%0d].tag = %0h = %0h", set_val, i, cache_mem[set_val].cache_line[i].tag, tag_val));
                            //Upadting PLRU bits
                            update_plru(i);
                            cache_mem[set_val].plru_bits = update_plru_temp;
                            display_val(MED, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                            cache_read_cnt++;
                            cache_miss_cnt++;
                            break;
                        end
                    end
                end
            end
        end
    end

    final
    begin
        print_cache_mem(cache_mem);
        display_summary();
    end

endmodule: cache