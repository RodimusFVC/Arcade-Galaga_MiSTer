  /* Copyright 2025 Swarup Saha Roy

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.*/

               `timescale 1ns / 1ps
                module ControlUnit(
                    input  wire        clk,
                    input  wire        rst,
                    input  wire        decoder_reg_write,
                    input  wire        decoder_mem_read,
                    input  wire        decoder_mem_write,
                    input  wire        decoder_use_alu,
                    input  wire        decoder_use_immediate,
                    input  wire        decoder_is_branch,
                    input wire [3:0]   decoder_branch_type,
                    input  wire        decoder_halt,
                    input  wire [1:0]  decoder_inst_length,
                    input  wire [2:0]  decoder_src_reg,
                    input  wire [2:0]  decoder_dst_reg,
                    input  wire [3:0]  decoder_alu_op,
                    input  wire [7:0]  mem_out,
                    input wire[7:0]    FLAGS,
                    input wire         decoder_is_mov,
                    output reg         pc_enable,
                    output reg         ir_load,
                    output reg         mar_load,
                    output reg         mar_sel_wz,
                    output reg         mem_read,
                    output reg         mem_write,
                    output reg         reg_write,
                    output reg         alu_enable,
                    output reg  [2:0]  latched_src_reg,
                    output reg  [2:0]  latched_dst_reg,
                    output reg  [3:0]  latched_alu_op,
                    output reg  [7:0]  W,
                    output reg  [7:0]  Z,
                    output reg latched_use_imm,
                    output reg latch_is_mov,
                    output reg latched_is_branch
                );
                
                    localparam [2:0] FETCH = 3'b000, DECODE = 3'b001, FETCH_OP1 = 3'b010,
                                     FETCH_OP2 = 3'b011, MEM_RD = 3'b100, EXEC = 3'b101,
                                     WB = 3'b110, HALT = 3'b111;
                    // Flag positions
    parameter CARRY_F  = 0;
    parameter PARITY_F = 2;
    parameter AUXC_F   = 4;
    parameter ZERO_F   = 6;
    parameter SIGN_F   = 7;
                
                    reg [2:0] state;
                    reg [2:0] t_state;
                
                    reg latched_reg_write, latched_mem_read, latched_mem_write, latched_use_alu;
                    reg  latched_halt;
                    reg [1:0] latched_inst_len;
                    reg [3:0]   latched_branch_type;
                    
                    always @(posedge clk or posedge rst) begin
                        if (rst) begin
                            state <= FETCH;
                            t_state <= 0;
                            {pc_enable, ir_load, mar_load, mar_sel_wz, mem_read, mem_write, reg_write, alu_enable,latched_inst_len,latched_src_reg,latched_dst_reg,latched_alu_op,latch_is_mov} <= 0;
                            latched_use_imm<=0;
                            latched_branch_type<=0;
                        end 
                        else begin
                            case (state)
                                FETCH: begin
                
                                    case (t_state)
                                        3'd0: begin mar_sel_wz <= 0; mar_load <= 1; end // Load MAR with PC
                                        3'd1: ; // Wait for MAR to latch
                                        3'd2: begin mem_read <= 1; end
                                        3'd3: ; // Wait for memory
                                        3'd4: begin ir_load <= 1; pc_enable <= 1; end
                                        3'd5:pc_enable <= 0;
                                    endcase
                                    if (t_state == 3'd5) begin
                                        state <= DECODE;
                                        t_state <= 0;
                                    end else t_state <= t_state + 1;
                                end
                
                                DECODE: begin
                                    latched_reg_write <= decoder_reg_write;
                                    latched_mem_read  <= decoder_mem_read;
                                    latched_mem_write <= decoder_mem_write;
                                    latched_use_alu   <= decoder_use_alu;
                                    latched_use_imm   <= decoder_use_immediate;
                                    latched_is_branch <= decoder_is_branch;
                                    latched_halt      <= decoder_halt;
                                    latched_inst_len  <= decoder_inst_length;
                                    latched_src_reg   <= decoder_src_reg;
                                    latched_dst_reg   <= decoder_dst_reg;
                                    latched_alu_op    <= decoder_alu_op;
                                    latch_is_mov<=decoder_is_mov;
                                    latched_branch_type<=decoder_branch_type;
                                    if (decoder_halt) state <= HALT;
                                    else if (decoder_inst_length == 2'd2) state <= FETCH_OP1;
                                    else if (decoder_inst_length == 2'd3) state <= FETCH_OP1;
                                    else if (decoder_mem_read) state <= MEM_RD;
                                    else if (decoder_use_alu) state <= EXEC;
                                    else state <= WB;
                                end
                
                                FETCH_OP1: begin
                                    case (t_state)
                                        3'd0: begin mar_sel_wz <= 0; mar_load <= 1; end
                                        3'd1: ; // Wait
                                        3'd2: begin mem_read <= 1; end
                                        3'd3: ; // Wait
                                        3'd4: begin Z <= mem_out; pc_enable <= 1; end
                                        3'd5:pc_enable <= 0;
                                    endcase
                                    if (t_state == 3'd5) begin
                                        if (latched_inst_len == 2'd2)
                                            state <= (latched_use_alu ? EXEC : WB);
                                        else
                                            state <= FETCH_OP2;
                                        t_state <= 0;
                                    end else t_state <= t_state + 1;
                                end
                
                                FETCH_OP2: begin
                                    case (t_state)
                                        3'd0: begin mar_sel_wz <= 0; mar_load <= 1; end
                                        3'd1: ; // Wait
                                        3'd2: begin mem_read <= 1; end
                                        3'd3: ; // Wait
                                        3'd4: begin W <= mem_out; pc_enable <= 1; end
                                        3'd5:pc_enable <= 0;
                                        3'd6:;
                                        3'd7:;
                                    
                                    endcase
                     if (t_state == 3'd5) begin
    if (latched_is_branch) begin
        case (latched_branch_type)
            4'b0000: mar_sel_wz <= 1; // JMP (unconditional)
            4'b0001: if (FLAGS[ZERO_F])       mar_sel_wz <= 1;
            4'b0010: if (!FLAGS[ZERO_F])      mar_sel_wz <= 1;
            4'b0011: if (FLAGS[CARRY_F])      mar_sel_wz <= 1;
            4'b0100: if (!FLAGS[CARRY_F])     mar_sel_wz <= 1;
            4'b0101: if (!FLAGS[SIGN_F])      mar_sel_wz <= 1;
            4'b0110: if (FLAGS[SIGN_F])       mar_sel_wz <= 1;
            4'b0111: if (FLAGS[PARITY_F])     mar_sel_wz <= 1;
            4'b1000: if (!FLAGS[PARITY_F])    mar_sel_wz <= 1;
            default: ; // Do nothing special
        endcase
       
    end 
    end
    if (t_state == 3'd7)  begin
    if(latched_is_branch)begin    
     state <= FETCH; // Always go to FETCH after branch condition is checked
         {pc_enable, ir_load, mar_load, mar_sel_wz, mem_read, mem_write, reg_write, alu_enable,latched_inst_len,latched_src_reg,latched_dst_reg,latched_alu_op,latch_is_mov} <= 0;
                            latched_use_imm<=0;
                            latched_branch_type<=0;
        t_state <= 0;
    end
    else begin
        state <= (latched_mem_read ? MEM_RD : EXEC);
        t_state <= 0;
        end
    end
    
   else begin
    t_state <= t_state + 1;
end

                                    
                               end 
                
                                MEM_RD: begin
                                    case (t_state)
                                        3'd0: begin mar_sel_wz <= 1; mar_load <= 1; end
                                        3'd1: ; // Wait
                                        3'd2: ; // Wait
                                        3'd3: begin mem_read <= 1; end
                                        3'd4: ; // Wait
                                    endcase
                                    if (t_state == 3'd4) begin
                                        state <= (latched_use_alu ? EXEC : WB);
                                        t_state <= 0;
                                    end else t_state <= t_state + 1;
                                end
                
                                EXEC:  begin
                                    case (t_state)
            //                            3'd0:;
                                        3'd0:begin  alu_enable <= 1;end
                                       
                                    endcase
                                     if (t_state == 3'd0) begin
                                         state <= WB;
                                    t_state <= 0;
                                    end 
                                    else t_state <= t_state + 1;
                                  
                                end
                
                            WB: begin
                    reg_write <= latched_reg_write;  // keep high for 3 cycles
                    mem_write <= latched_mem_write;
                
                    case (t_state)
                        3'd0: ;
                        3'd1: ;
                    endcase
                        if(t_state==3'd1)begin
           {pc_enable, ir_load, mar_load, mar_sel_wz, mem_read, mem_write, reg_write, alu_enable,latched_inst_len,latched_src_reg,latched_dst_reg,latched_alu_op,latch_is_mov} <= 0;
                            latched_use_imm<=0;
                            latched_branch_type<=0; 
                            state <= FETCH;
                            t_state <= 0;
                        end 
                        else t_state <= t_state + 1;
                
                end
                
                                    
                                     HALT: begin
                                    pc_enable <= 0;
                                end
                
                                default: begin 
                                state <= FETCH;
            {pc_enable, ir_load, mar_load, mar_sel_wz, mem_read, mem_write, reg_write, alu_enable,latched_inst_len,latched_src_reg,latched_dst_reg,latched_alu_op,latch_is_mov} <= 0;
                            latched_use_imm<=0;
                            latched_branch_type<=0;                  
                             end
                            endcase
                        end
                    end
                endmodule
