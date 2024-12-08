`timescale 1ns/1ns

`include "../PKG/defines.sv"

import trace_pkg::*;
import cache_struct_pkg::*;

module cache;
    
    //Declare physical address
    string file_name;                           //Variable to store filename input
    int input_file_open;                        //Variable to store open file content
    int output_file_open;                       //Variable to store open file content
    int line_count;
    string line;

    //Local variables
    int trans_cnt;
    int valid_cnt;
    int invalid_cnt;
    bit set_empty;
    bit set_full;
    bit tag_matched;
    int temp_f;
    logic [`PHYSICAL_ADDR_BITS-1:0] evict_address;

    //MESI Signals
    logic PrRd;
    logic PrWr;
    logic BusRd_in;
    logic BusRdX_in;
    logic BusUpgr_in;
    logic BusRd_out;
    logic BusRdX_out;
    logic BusUpgr_out;
    logic flush;
    int saved_i;

    //Declare cache memory
    cache_set_st cache_mem;

    //Function: Read command line arguments
    function void read_cmd_line_args();
        if($value$plusargs("MODE=%s", mode))
        begin
            if(mode == "SILENT")
            begin
                debug_mode_pkg = 0;
                $display("SILENT MODE is Enabled");
            end
            if(mode == "NORMAL")
            begin
                debug_mode_pkg = 1;
                $display("NORMAL MODE is Enabled");
            end
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

    //MESI Protocol Implementation - FSM (Transition when CPU request)
    assign rst = (cmd == 8);
    assign PrRd = (cmd == 0 || cmd == 2);
    assign PrWr = (cmd == 1);
    assign BusRd_in = (cmd == 3);
    assign BusRdX_in = (cmd == 4 || cmd == 5);
    assign BusUpgr_in = (cmd == 6);

    function void mesi_state_assignment();
        case(cache_mem[set_val].cache_line[saved_i].mesi_state)
        INVALID     :   begin
                            if(PrRd)
                            begin
                                if(snoop_result == HIT)
                                begin
                                    mesi_state_temp = SHARED;
                                    BusRd_out = 1;
                                    BusRdX_out = 0;
                                    BusUpgr_out = 0;
                                    flush = 0;
                                    bus_operation(READ, address);
                                    message_to_L1_cache(SENDLINE, address);
                                end
                                else if(snoop_result == HITM)
                                begin
                                    mesi_state_temp = SHARED;
                                    BusRd_out = 1;
                                    BusRdX_out = 0;
                                    BusUpgr_out = 0;
                                    flush = 0;
                                    bus_operation(READ, address);
                                    message_to_L1_cache(SENDLINE, address);
                                end
                                else
                                begin
                                    mesi_state_temp = EXCLUSIVE;
                                    BusRd_out = 1;
                                    BusRdX_out = 0;
                                    BusUpgr_out = 0;
                                    flush = 0;
                                    bus_operation(READ, address);
                                    message_to_L1_cache(SENDLINE, address);
                                end
                            end
                            else if(PrWr)
                            begin
                                mesi_state_temp = MODIFIED;
                                BusRd_out = 0;
                                BusRdX_out = 1;
                                BusUpgr_out = 0;
                                flush = 0;
                                bus_operation(RWIM, address);
                                message_to_L1_cache(SENDLINE, address);
                            end
                            else if(BusRd_in || BusRdX_in || BusUpgr_in)
                            begin
                                mesi_state_temp = INVALID;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                cache_mem[set_val].cache_line[saved_i].valid = 0;
                                cache_mem[set_val].cache_line[saved_i].tag = 'hx;
                                put_snoop_result(address, NOHIT);
                            end
                            else
                            begin
                                mesi_state_temp = INVALID;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                cache_mem[set_val].cache_line[saved_i].valid = 0;
                                cache_mem[set_val].cache_line[saved_i].tag = 'hx;
                            end
                        end

        EXCLUSIVE   :   begin
                            if(PrRd)
                            begin
                                mesi_state_temp = EXCLUSIVE;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                message_to_L1_cache(SENDLINE, address);
                            end
                            else if(PrWr)
                            begin
                                mesi_state_temp = MODIFIED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                message_to_L1_cache(SENDLINE, address);
                            end
                            else if(BusRdX_in)
                            begin
                                mesi_state_temp = INVALID;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                cache_mem[set_val].cache_line[saved_i].valid = 0;
                                cache_mem[set_val].cache_line[saved_i].tag = 'hx;
                                put_snoop_result(address, HIT);
                            end
                            else if(BusRd_in)
                            begin
                                mesi_state_temp = SHARED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                put_snoop_result(address, HIT);
                            end
                        end

        SHARED      :   begin
                            if(PrRd)
                            begin
                                mesi_state_temp = SHARED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                message_to_L1_cache(SENDLINE, address);
                            end
                            else if(PrWr)
                            begin
                                mesi_state_temp = MODIFIED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 1;
                                flush = 0;
                                message_to_L1_cache(SENDLINE, address);
                                bus_operation(INVALIDATE, address);
                            end
                            else if(BusRd_in)
                            begin
                                mesi_state_temp = SHARED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                put_snoop_result(address, HIT);
                            end
                            else if(BusRdX_in || BusUpgr_in)
                            begin
                                mesi_state_temp = INVALID;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                cache_mem[set_val].cache_line[saved_i].valid = 0;
                                cache_mem[set_val].cache_line[saved_i].tag = 'hx;
                                put_snoop_result(address, HIT);
                            end
                        end

        MODIFIED    :   begin
                            if(PrRd)
                            begin
                                mesi_state_temp = MODIFIED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                message_to_L1_cache(SENDLINE, address);
                            end
                            else if(PrWr)
                            begin
                                mesi_state_temp = MODIFIED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 0;
                                message_to_L1_cache(SENDLINE, address);
                            end
                            else if(BusRd_in)
                            begin
                                mesi_state_temp = SHARED;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 1;
                                put_snoop_result(address, HITM);
                            end
                            else if(BusRdX_in)
                            begin
                                mesi_state_temp = INVALID;
                                BusRd_out = 0;
                                BusRdX_out = 0;
                                BusUpgr_out = 0;
                                flush = 1;
                                cache_mem[set_val].cache_line[saved_i].valid = 0;
                                cache_mem[set_val].cache_line[saved_i].tag = 'hx;
                                put_snoop_result(address, HITM);
                            end
                        end
            
        default     :   begin
                            mesi_state_temp = INVALID;
                            BusRd_out = 0;
                            BusRdX_out = 0;
                            BusUpgr_out = 0;
                            flush = 0;
                            cache_mem[set_val].cache_line[saved_i].valid = 0;
                            cache_mem[set_val].cache_line[saved_i].tag = 'hx;
                        end
        endcase
        display_val(DEBUG, $sformatf("---------- MESI Function Display ----------"));
        display_val(DEBUG, $sformatf("Saved_i = %0d", saved_i));
        display_val(DEBUG, $sformatf("PrRd = %0d", PrRd));
        display_val(DEBUG, $sformatf("PrWr = %0d", PrWr));
        display_val(MED, $sformatf("PREVIOUS MESI STATE = %s" ,cache_mem[set_val].cache_line[saved_i].mesi_state));
        cache_mem[set_val].cache_line[saved_i].mesi_state = mesi_state_temp;
        display_val(MED, $sformatf("CURRENT MESI STATE = %s" , mesi_state_temp));
        display_val(DEBUG, $sformatf("-------------------------------------------"));
    endfunction: mesi_state_assignment

    initial
    begin
        forever
        begin
            #(`INTERVAL/2) clk = ~clk;
        end
    end

    //Procedural block to perform operation
    initial begin

        //Displaying the given data of cache memory
        display_given_data();

        //Function call to read command line arguments
        read_cmd_line_args();

        //Open input and output files
        input_file_open = $fopen($sformatf("../%s",file_name), "r");
        if(input_file_open == 0)
        begin
            $warning("File %s doesn't exist in the directory, I'm running with default input file rwims.din", file_name);
            input_file_open = $fopen($sformatf("../rwims.din",file_name), "r");
        end
        output_file_open = $fopen("../output.txt", "w");

        $fdisplay(output_file_open, "--------------------- PROJECT #9 ---------------------");
        $fdisplay(output_file_open, "-------------------- Parsed Data  --------------------");
        $fdisplay(output_file_open, "--------------- Input file : %s ---------------", file_name);
        $fdisplay(output_file_open, "------------------------------------------------------\n");

        //Initialize the cache memory
        initialize_cache_mem(cache_mem);

        while(!$feof(input_file_open))
        begin

            trans_cnt++;
            //Decode everyline of trace file and store them in cmd and address
            temp_f = $fscanf(input_file_open, "%h %h", cmd, address);

            //Function call to assign cmd description
            cmd_description = assign_cmd_description(cmd);
            display_val(DEBUG, $sformatf("Command Description: %s", cmd_description));
            display_val(DEBUG, $sformatf("Command            : %h", cmd));
            display_val(DEBUG, $sformatf("Address            : %h\n", address));

            display_val(LOW, "\n-----------------------------------------------------------------------------------");
            display_val(LOW, $sformatf("                                TRANSACTION : %0d                                  ", trans_cnt));
            display_val(LOW, "-----------------------------------------------------------------------------------");
            
            //Write to output file
            $fdisplay(output_file_open, "Command Description: %s", cmd_description);
            $fdisplay(output_file_open, "Command            : %h", cmd);
            $fdisplay(output_file_open, "Address            : %h", address);
            $fdisplay(output_file_open, "------------------------------------------------------\n");

            //Pushing back the new line content into queue array(class handle)
            address_slicing(address);

            //Transaction delay (You may use clock edge here)
            //#(`INTERVAL);
            @(posedge clk);

            //0 : read request from L1 data cache
            if(cmd == 0 || cmd == 2)
            begin
                
                display_val(MED, "-------------- CPU Read Request --------------\n");
                check_for_set_empty_full();
                tag_matched = 0;                //Initialized the value (It is just for internal logic)
                display_val(DEBUG, $sformatf("Addr = %0h, SET_FULL = %0b, SET_EMPTY = %0d", address, set_full, set_empty));

                //For loop - 1 (For READ-HIT and CONFLICT MISSES)
                for(int i=0; i < `NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
                begin
                    //display_val(MED, $sformatf("SET_EMPTY = %0d, SET_FULL = %0d", set_empty, set_full));
                    if(cache_mem[set_val].cache_line[i].valid == 1)           //Check if line is already valid or not, if yes, executing if loop
                    begin
                        if(set_full == 0 && cache_mem[set_val].cache_line[i].tag == tag_val)
                        begin
                            display_val(MED, $sformatf("\nTAG MATCHED! %0h = %0h", cache_mem[set_val].cache_line[i].tag, tag_val));
                            display_val(MED, $sformatf("READ-HIT for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                            //Upadting PLRU bits
                            cache_mem[set_val].plru_bits = update_plru_temp;
                            update_plru(i);
                            //MESI state assignment function call to assign respective mesi states
                            saved_i = i;
                            mesi_state_assignment();
                            display_val(DEBUG, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                            tag_matched = 1;
                            //cache_hit_cnt++;
                            //cache_read_cnt++;
                            break;
                        end
                        else if(set_full == 1)
                        begin
                            for(int i=0; i < `NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
                            begin
                                if(tag_matched == 0 && cache_mem[set_val].cache_line[i].tag == tag_val)
                                begin
                                    display_val(MED, $sformatf("\nTAG MATCHED! %0h = %0h", cache_mem[set_val].cache_line[i].tag, tag_val));
                                    display_val(MED, $sformatf("READ-HIT for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                                    //Upadting PLRU bits
                                    update_plru(i);
                                    cache_mem[set_val].plru_bits = update_plru_temp;
                                    //MESI state assignment function call to assign respective mesi states 
                                    saved_i = i;
                                    mesi_state_assignment();
                                    display_val(DEBUG, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                                    tag_matched = 1;
                                    break;
                                end
                            end
                                
                            if(tag_matched == 0 && cache_mem[set_val].cache_line[i].valid == 1 && cache_mem[set_val].cache_line[i].tag != tag_val)
                            begin
                                display_val(MED, $sformatf("CONFLICT READ-MISS for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                                //Function call for PLRU Eviction
                                victim_plru(update_plru_temp);
                                cache_mem[set_val].plru_bits = update_plru_temp;
                                //Fetch evict_address
                                evict_address = {cache_mem[set_val].cache_line[way_out].tag, set_val, 6'hx};
                                message_to_L1_cache(EVICTLINE, evict_address);
                                bus_operation(WRITE, evict_address);
                                bus_operation(READ, address);
                                message_to_L1_cache(SENDLINE, address);
                                //MESI state assignment function call to assign respective mesi states
                                saved_i = i;
                                mesi_state_assignment();
                                //Make the valid bit one and assign tag values
                                cache_mem[set_val].cache_line[way_out].valid = 1;
                                cache_mem[set_val].cache_line[way_out].tag = tag_val;
                                cache_miss_cnt++;
                                cache_read_cnt++;
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
                            //MESI state assignment function call to assign respective mesi states
                            saved_i = i;
                            mesi_state_assignment();
                            display_val(DEBUG, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                            cache_read_cnt++;
                            cache_miss_cnt++;
                            break;
                        end
                    end
                end
            end

            //1 : write request from L1 data cache
            else if(cmd == 1)
            begin

                display_val(MED, "-------------- CPU Write Request --------------\n");

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
                            display_val(MED, $sformatf("1 - WRITE-HIT for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                            //Upadting PLRU bits
                            update_plru(i);
                            cache_mem[set_val].plru_bits = update_plru_temp;
                            //MESI state assignment function call to assign respective mesi states
                            saved_i = i;
                            mesi_state_assignment();
                            display_val(DEBUG, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                            tag_matched = 1;
                            //cache_hit_cnt++;
                            //cache_write_cnt++;
                            break;
                        end
                        else if(set_full == 1)
                        begin
                            for(int i=0; i < `NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
                            begin
                                if(tag_matched == 0 && cache_mem[set_val].cache_line[i].tag == tag_val)
                                begin
                                    display_val(MED, $sformatf("\nTAG MATCHED! %0h = %0h", cache_mem[set_val].cache_line[i].tag, tag_val));
                                    display_val(MED, $sformatf("2 - WRITE-HIT for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                                    //Upadting PLRU bits
                                    update_plru(i);
                                    cache_mem[set_val].plru_bits = update_plru_temp;
                                    //MESI state assignment function call to assign respective mesi states
                                    saved_i = i;
                                    mesi_state_assignment();
                                    display_val(DEBUG, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                                    tag_matched = 1;
                                    break;
                                end
                            end
                                
                            if(tag_matched == 0 && cache_mem[set_val].cache_line[i].valid == 1 && cache_mem[set_val].cache_line[i].tag != tag_val)
                            begin
                                display_val(MED, $sformatf("CONFLICT WRITE-MISS for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                                //Make the valid bit one and assign tag values
                                //Upadting PLRU bits
                                victim_plru(update_plru_temp);
                                cache_mem[set_val].plru_bits = update_plru_temp;

                                //Fetch evict_address
                                evict_address = {cache_mem[set_val].cache_line[way_out].tag, set_val, 6'hx};
                                message_to_L1_cache(EVICTLINE, evict_address);
                                bus_operation(WRITE, evict_address);
                                bus_operation(RWIM, address);
                                message_to_L1_cache(SENDLINE, address);
                                
                                cache_mem[set_val].cache_line[way_out].valid = 1;
                                cache_mem[set_val].cache_line[way_out].tag = tag_val;
                                //MESI state assignment function call to assign respective mesi states
                                saved_i = i;
                                mesi_state_assignment();
                                cache_miss_cnt++;
                                cache_write_cnt++;
                                break;
                            end
                        end
                    end
                end

                if(tag_matched == 1)
                begin
                    cache_hit_cnt++;
                    cache_write_cnt++;
                end 

                //For loop - 2 (For COMPULSORY MISSES)
                for(int i=0; i < `NUM_OF_WAYS_OF_ASSOCIATIVITY; i++)
                begin
                    if(tag_matched == 0)
                    begin
                        if(set_full == 0 && cache_mem[set_val].cache_line[i].valid !== 'h1)
                        begin
                            display_val(MED, $sformatf("\nCOMPULSORY WRITE-MISS for %h at CACHE_MEM [SET=%0d][WAY=%0d]", address, set_val, i));
                            //Make the valid bit one and assign tag values
                            cache_mem[set_val].cache_line[i].valid = 1;
                            cache_mem[set_val].cache_line[i].tag = tag_val;
                            display_val(MED, $sformatf("cache_mem[%0d].cache_line[%0d].valid = %0d", set_val, i, cache_mem[set_val].cache_line[i].valid));
                            display_val(MED, $sformatf("cache_mem[%0d].cache_line[%0d].tag = %0h = %0h", set_val, i, cache_mem[set_val].cache_line[i].tag, tag_val));
                            //Upadting PLRU bits
                            update_plru(i);
                            cache_mem[set_val].plru_bits = update_plru_temp;
                            display_val(DEBUG, $sformatf("PLRU = %b", cache_mem[set_val].plru_bits));
                            //MESI state assignment function call to assign respective mesi states
                            saved_i = i;
                            mesi_state_assignment();
                            cache_write_cnt++;
                            cache_miss_cnt++;
                            break;
                        end
                    end
                end
            end

            else if(cmd == 3)
            begin
                display_val(MED, "-------------- Snoop Read Request --------------\n");
                bus_op = READ;
                // bus_operation(bus_op, address, snoop_result);
                mesi_state_assignment();
                
            end
            
            else if(cmd == 4)
            begin
                display_val(MED, "-------------- Snoop Write Request --------------\n");

                bus_op = WRITE;
                // bus_operation(bus_op, address, snoop_result);
                mesi_state_assignment();
                //put_snoop_result(address, snoop_result);
            end
            
            else if(cmd == 5)
            begin
                display_val(MED, "-------------- Snoop Read with Intent to Modify Request --------------\n");

                bus_op = RWIM;
                // bus_operation(bus_op, address, snoop_result);
                mesi_state_assignment();
                //put_snoop_result(address, snoop_result);
            end
            
            else if(cmd == 6)
            begin
                display_val(MED, "-------------- Snoop Invalidate Command --------------\n");

                bus_op = INVALIDATE;
                // bus_operation(bus_op, address, snoop_result);
                mesi_state_assignment();
                //put_snoop_result(address, snoop_result);
            end

            else if(cmd == 8)
            begin
                display_val(MED, "-------------- Clear the Cache and Reset all State --------------\n");

                initialize_cache_mem(cache_mem);
            end
            
            else if(cmd == 9)
            begin
                display_val(MED, "-------------- Print Contents and State of Each Valid Cache Line --------------\n");

                print_cache_mem(cache_mem);
            end
        end
        $finish;
    end

    final
    begin
        print_cache_mem(cache_mem);
        display_summary();
    end

endmodule: cache