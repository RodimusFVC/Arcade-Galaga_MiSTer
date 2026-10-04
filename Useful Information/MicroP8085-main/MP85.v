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
    
    module MP85(
        input wire clk,
        input wire rst
    );
    
        // === Program Counter ===
        reg [15:0] PC;
        reg [15:0] MAR;
        reg [7:0] datareg;
        wire is_mov;
        // === WZ Temporary Register Pair ===
        wire [7:0] W_internal, Z_internal;
        wire [15:0] WZ = {W_internal, Z_internal};
    
        // === Instruction Register ===
        reg [7:0] IR;
    
        // === Memory Interface ===
        wire [7:0] mem_data_out;
        reg [7:0] mem_data_in;
        wire mem_read, mem_write;
    
        // === Register File Interface ===
        wire [7:0] reg_data1, reg_data2;
        wire [2:0] src_reg, dst_reg;
        wire reg_write;
    
        // === ALU Interface ===
        wire [7:0] alu_out, alu_flags;
        wire use_alu, use_immediate;
        wire [3:0] alu_op;
        wire flags_write_en;
    
        // === Flags Register ===
        reg [7:0] FLAGS;
    
        // === Instruction Properties ===
        wire inst_is_2B, inst_is_3B;
        wire halt, is_branch;
        wire [3:0] branch_type;
    
        // === Control Unit Signals ===
        wire pc_inc, ir_load, wz_load;
        wire mar_load, reg_write_ctrl, mem_read_ctrl, mem_write_ctrl;
        wire alu_enable;
        wire [2:0] latched_src_reg, latched_dst_reg;wire latched_use_imm;
        wire[3:0] latched_alu_op;
        wire latch_is_mov;
        wire latched_is_barnch;
        // === Decoder ===
        IDecoder decoder (
            .IR(IR),
            .reg_write(reg_write),
            .mem_read(mem_read),
            .mem_write(mem_write),
            .use_alu(use_alu),
            .alu_op(alu_op),
            .use_immediate(use_immediate),
            .src_reg(src_reg),
            .dst_reg(dst_reg),
            .halt(halt),
            .is_branch(is_branch),
            .branch_type(branch_type),
            .inst_length({inst_is_3B, inst_is_2B}),
            .is_mov(is_mov)
        );
    
        reg [7:0] temp;
        always @(posedge clk) begin
            if (alu_enable)
                temp <= alu_out;
            else if (latched_use_imm && reg_write_ctrl)
                temp <= Z_internal;
            else if (mem_read_ctrl)
                temp <= datareg;
            else
                temp <= 8'h00;
        end
    
        // === Register File ===
        registers regfile (
            .clk(clk),
            .rst(rst),
            .write_en(reg_write_ctrl),
            .read_addr1(latched_src_reg),
            .read_addr2(latched_dst_reg),
            .write_addr(latched_dst_reg),
            .write_data(temp),
            .read_data1(reg_data1),
            .read_data2(reg_data2),
            .latch_is_mov(latch_is_mov)
        );
    
        // === Memory ===
        memory mem (
            .clk(clk),
            .rst(rst),
            .mem_read(mem_read_ctrl),
            .mem_write(mem_write_ctrl),
            .address(MAR),
            .data_in(mem_data_in),
            .data_out(mem_data_out)
        );
    
        // === ALU ===
        ALU alu (
            .alu_enable(alu_enable),
            .alu_op(latched_alu_op),
            .iA(reg_data2),
            .iB(latched_use_imm ? Z_internal : reg_data1),
            .iF(FLAGS),
            .oR(alu_out),
            .oF(alu_flags),
            .Flag_read_wrbar(flags_write_en)
        );
    
        // === Control Logic Unit ===
        ControlUnit control_unit (
            .clk(clk),
            .rst(rst),
            .decoder_is_mov(is_mov),
            .decoder_src_reg(src_reg),
            .decoder_dst_reg(dst_reg),
            .decoder_alu_op(alu_op),
            .decoder_use_alu(use_alu),
            .decoder_use_immediate(use_immediate),
            .decoder_reg_write(reg_write),
            .decoder_mem_read(mem_read),
            .decoder_mem_write(mem_write),
            .decoder_is_branch(is_branch),
          
            .decoder_inst_length({inst_is_3B, inst_is_2B}),
            .mem_out(mem_data_out),
            .ir_load(ir_load),
            .pc_enable(pc_inc),
            .mar_load(mar_load),
            .mar_sel_wz(wz_load),
            .mem_read(mem_read_ctrl),
            .mem_write(mem_write_ctrl),
            .reg_write(reg_write_ctrl),
            .alu_enable(alu_enable),
            .latched_src_reg(latched_src_reg),
            .latched_dst_reg(latched_dst_reg),
            .latched_alu_op(latched_alu_op),
            .W(W_internal),
            .Z(Z_internal),
            .latched_use_imm(latched_use_imm),
            .latch_is_mov(latch_is_mov),
              .decoder_branch_type(branch_type),
            .FLAGS(FLAGS),
            .latched_is_branch(latched_is_branch)
        );
    
        // === Sequential Logic (Registers) ===
        always @(posedge clk or posedge rst) begin
            if (rst) begin
                PC     <= 16'h0000;
                IR     <= 8'h00;
                FLAGS  <= 8'h00;
                MAR    <= 16'h0000;
            end else begin
                if (mar_load)
                    MAR <= ((inst_is_3B || inst_is_2B) && wz_load) ? WZ : PC;
    
                if (mem_read_ctrl)
                    datareg <= mem_data_out;
    
                if (ir_load)
                    IR <= mem_data_out;
                    
                   if(latched_is_branch && wz_load)  PC<=WZ;
                   
                if (pc_inc && !(is_branch && wz_load))begin
                   PC <= PC + 16'h0001;
                  end
                if (!flags_write_en && use_alu)
                    FLAGS <= alu_flags;
            end
        end
    
        // === Data Input Selection for Memory Writes ===
        always @(*) begin
            if (mem_write_ctrl)
                mem_data_in = reg_data1;
            else
                mem_data_in = 8'h00;
        end
    
    endmodule
