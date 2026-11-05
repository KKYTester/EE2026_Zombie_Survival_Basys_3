`timescale 1ns / 1ps
module map_system #(parameter STAGE=3, parameter INITIAL_SEED=16'h1ACE,
    parameter GEN_LIMIT=4096, parameter VALIDATE_LIMIT=4096)(
    input wire clk, input wire rst, input wire regenerate,
    input wire [15:0] seed_in,
    output reg [255:0] published_map,
    output reg [7:0] p1_addr,p2_addr,
    output reg map_ready, output wire busy,
    output reg [2:0] error_code, output reg [15:0] active_seed,
    output reg [2:0] retry_count);
    localparam S_START=0;     // Pulse the generator with the selected seed.
    localparam S_GENERATE=1;  // Await generation with a bounded watchdog.
    localparam S_VALIDATE=2;  // Pulse the validator after the last map write.
    localparam S_WAIT=3;      // Wait for scan/BFS and publish only a passing map.
    localparam S_RETRY=4;     // Re-seed for at most four additional attempts.
    localparam S_IDLE=5;      // Hold a passing map or terminal error until requested.
    reg [2:0] state;
    reg [15:0] gen_elapsed;
    wire [255:0] working_map;
    wire wr_en,wr_wall,gen_done,gen_busy,val_done,val_pass,val_busy;
    wire [7:0] wr_addr,vp1,vp2;
    wire [2:0] val_error;
    wire [8:0] floors,reached;
    wire abort_generator=(state==S_RETRY);
    map_generator #(.FIXED_MAP(STAGE==1)) generator(
        .clk(clk),.rst(rst || abort_generator),.start(state==S_START),
        .seed(active_seed),.write_en(wr_en),.write_addr(wr_addr),
        .write_wall(wr_wall),.done(gen_done),.busy(gen_busy));
    map_storage storage(.clk(clk),.rst(rst),.write_en(wr_en),
        .write_addr(wr_addr),.write_wall(wr_wall),.map_bits(working_map));
    map_validator #(.CHECK_CONNECTIVITY(STAGE==3),.MAX_CYCLES(VALIDATE_LIMIT)) validator(
        .clk(clk),.rst(rst),.start(state==S_VALIDATE),.map_bits(working_map),
        .busy(val_busy),.done(val_done),.passed(val_pass),.error_code(val_error),
        .p1_addr(vp1),.p2_addr(vp2),.floor_count(floors),.reachable_count(reached));
    assign busy=state!=S_IDLE;
    always @(posedge clk) begin
        if(rst) begin
            state<=S_START; published_map<={256{1'b1}};
            p1_addr<=0; p2_addr<=0; map_ready<=0; error_code<=0;
            active_seed<=(INITIAL_SEED==0) ? 16'h0001 : INITIAL_SEED;
            retry_count<=0; gen_elapsed<=0;
        end else case(state)
            S_START: begin
                map_ready<=0; error_code<=0; gen_elapsed<=0; state<=S_GENERATE;
            end
            S_GENERATE: begin
                if(gen_done) state<=S_VALIDATE;
                else if(gen_elapsed>=GEN_LIMIT-1) begin error_code<=4; state<=S_RETRY; end
                else gen_elapsed<=gen_elapsed+1'b1;
            end
            S_VALIDATE: state<=S_WAIT;
            S_WAIT: if(val_done) begin
                if(val_pass) begin
                    published_map<=working_map; p1_addr<=vp1; p2_addr<=vp2;
                    map_ready<=1; error_code<=0; state<=S_IDLE;
                end else begin error_code<=val_error; state<=S_RETRY; end
            end
            S_RETRY: begin
                if(retry_count<4) begin
                    active_seed<=(active_seed>>1) ^ (active_seed[0] ? 16'hB400 : 16'h0000);
                    retry_count<=retry_count+1'b1; state<=S_START;
                end else state<=S_IDLE;
            end
            S_IDLE: if(regenerate) begin
                active_seed<=(seed_in==0) ? 16'h0001 : seed_in;
                retry_count<=0; map_ready<=0; error_code<=0; state<=S_START;
            end
            default: state<=S_START;
        endcase
    end
endmodule
