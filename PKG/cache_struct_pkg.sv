`include "defines.sv"

package cache_struct_pkg;

    //Counter variables
    bit [`COUNTER_BITS-1:0] cache_read_cnt;
    bit [`COUNTER_BITS-1:0] cache_write_cnt;
    bit [`COUNTER_BITS-1:0] cache_hit_cnt;
    bit [`COUNTER_BITS-1:0] cache_miss_cnt;
    real cache_hit_ratio;

    //PLRU bit-array declaration (Dynamic array)
    bit [`PLRU_BITS-1:0] update_plru_temp;
    int update_plru_index = 0;
    int victim_plru_index = 0;
    int plru_bit_shift = 0;
    bit debug_mode_pkg = 0;
    int way_out;

    typedef enum bit [1:0] {INVALID = 2'b00,
                            SHARED = 2'b01,
                            EXCLUSIVE = 2'b10,
                            MODIFIED = 2'b11} mesi_states_e;

    //One-cache line contains: Valid bit, Dirty bit, Tag bit, MESI State
    //Let's declare user-defined structure for one cache line
    typedef struct {logic valid;
                    logic dirty;
                    mesi_states_e mesi_state;
                    logic [`TAG_BITS-1:0] tag;} cache_line_st;

    //One-set contains: (16-1)=15 PLRU bits, 16 cache-lines 
    typedef struct {logic [`PLRU_BITS-1:0] plru_bits;
                    cache_line_st cache_line [`NUM_OF_WAYS_OF_ASSOCIATIVITY-1:0];} cache_set_st [`NUM_OF_SETS];
    
    // //Cache memory contains: All cache sets inside memory
    // typedef struct {cache_set_st cache_set [`NUM_OF_SETS_BITS-1:0];} cache_mem_st;

    // Verbosity Levels
    typedef enum int { NONE = 0,     // No output
                       LOW = 1,    // Errors only
                       MED = 2,  // Errors and warnings
                       HIGH = 3,     // Errors, warnings, and general info
                       FULL = 4,     // Detailed debug information
                       DEBUG = 5     // Detailed debug information
                       } verbosity_t;
                
    // Global verbosity level (can be set dynamically)
    verbosity_t verbosity_level;     // Default verbosity
                
    // Verbosity-controlled display task
    function void display_val(verbosity_t level, string msg);
        if(debug_mode_pkg == 1)
        begin
            if (level <= verbosity_level) begin
                case (level)
                    NONE    :   $display("%s", msg);
                    LOW     :   $display("%s", msg);
                    MED     :   $display("%s", msg);
                    HIGH    :   $display("%s", msg);
                    FULL    :   $display("%s", msg);
                    DEBUG   :   $display("%s", msg);
                    default :   $display("[UNKNOWN] %s", msg);
                endcase
            end
        end
    endfunction

    //Function: Initialize cache memory
    function void initialize_cache_mem(input cache_set_st cache_mem);
        for (int i = 0; i < `NUM_OF_SETS; i++)
        begin
            for (int j = 0; j < `NUM_OF_WAYS_OF_ASSOCIATIVITY; j++)
            begin
                cache_mem[i].cache_line[j].valid = 0;
                cache_mem[i].cache_line[j].dirty = 0;
                cache_mem[i].cache_line[j].tag = 'hx;
                cache_mem[i].cache_line[j].mesi_state = INVALID;
                cache_mem[i].plru_bits[j] = 'b0;  					// Setting PLRU to 00000000 while initializing
            end
        end
    endfunction
                
    //Function: Prints the contents of each valid cache line.
    function void print_cache_mem(input cache_set_st cache_mem);
        $display("------------------CACHE_MEM [SET][WAY] = [TAG BITS][MESI STATE]--------------------");	
        for (int i = 0; i < `NUM_OF_SETS; i++)
        begin
            for (int j = 0; j < `NUM_OF_WAYS_OF_ASSOCIATIVITY; j++)
            begin
                if(cache_mem[i].cache_line[j].valid == 1)				
                    $display("CACHE_MEM [%0d][%0d] = [%0h][%0s]", i, j, cache_mem[i].cache_line[j].tag, cache_mem[i].cache_line[j].mesi_state.name);
            end
        end
    endfunction
    
    //Function: Display summary of counts
    function void display_summary();
        cache_hit_ratio = real'(real'(cache_hit_cnt)/real'(cache_read_cnt + cache_write_cnt));
        $display("-------------------------------------------------------------------");	
        $display("                            SUMMARY                                ");	
        $display("-------------------------------------------------------------------");	
        $display("NUMBER OF CACHE READS\t = %0d", cache_read_cnt);	
        $display("NUMBER OF CACHE WRITES = %0d", cache_write_cnt);	
        $display("NUMBER OF CACHE HITS\t = %0d", cache_hit_cnt);	
        $display("NUMBER OF CACHE MISSES = %0d", cache_miss_cnt);	
        $display("CACHE HIT RATIO\t = %0.2f %%", cache_hit_ratio);	
        $display("-------------------------------------------------------------------");	
    endfunction

    //Function: PLRU Update logic
    function void update_plru(int w);

        update_plru_index = 0;
        $display("w = %0d", w);

        for(int binary_bit_level = ($clog2(`NUM_OF_WAYS_OF_ASSOCIATIVITY)-1); binary_bit_level >= 0; binary_bit_level--)
        begin
            plru_bit_shift = (w >> binary_bit_level) & 1;          //Extract last bit of given way
            update_plru_temp[update_plru_index] = plru_bit_shift;
            if(binary_bit_level > 0)
            begin
                update_plru_index = (2*update_plru_index) + 1 + plru_bit_shift;
            end
            $display("index = %0d", update_plru_index);
        end

        foreach(update_plru_temp[i])
        begin
            $display("Updated_PLRU[%0d] = %b", i, update_plru_temp[i]);
        end

    endfunction: update_plru

    function void victim_plru(bit [`PLRU_BITS-1:0] PLRU);
        begin
            victim_plru_index = 0;
            way_out = 0;
            PLRU[0] = ~PLRU[0];  // XOR PLRU[0] with 1
            $display("\nInitial - %d ", PLRU[0]);  // Print PLRU[0] and add space
            
            for(int binary_bit_level = ($clog2(`NUM_OF_WAYS_OF_ASSOCIATIVITY)-1); binary_bit_level >= 0; binary_bit_level--)
            begin
                if (PLRU[victim_plru_index] == 0)               // Left child access
                begin
                    victim_plru_index = 2 * victim_plru_index + 1;          // Update index for left child
                    PLRU[victim_plru_index] = ~PLRU[victim_plru_index];
                    way_out = 2*way_out;  
                end
                else if (PLRU[victim_plru_index] == 1)  // Right child access
                begin
                    victim_plru_index = 2 * victim_plru_index + 2;  // Update index for right child
                    PLRU[victim_plru_index] = ~PLRU[victim_plru_index];  // XOR with 1 (toggle the value)
                    way_out = (2*way_out)+1;
                end
            end
            $display("way_out = %0d", way_out);
            update_plru_temp = PLRU;
            foreach(update_plru_temp[i])
            begin
                $display("Updated_PLRU[%0d] = %b", i, update_plru_temp[i]);
            end
        end
    endfunction
    
endpackage: cache_struct_pkg