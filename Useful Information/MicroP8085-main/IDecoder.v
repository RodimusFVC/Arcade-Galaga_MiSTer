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
module IDecoder(
    input  wire [7:0] IR,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        use_alu,
    output reg [3:0]  alu_op,
    output reg        use_immediate,
    output reg [2:0]  src_reg,
    output reg [2:0]  dst_reg,
    output reg        halt,
    output reg        is_branch,
    output reg  [3:0] branch_type,
    output reg [1:0]  inst_length,
    output reg        is_mov
);

    // Opcodes
    localparam [3:0]
        OP_ADD = 4'b0000,
        OP_ADC = 4'b0001,
        OP_SUB = 4'b0010,
        OP_SBB = 4'b0011,
        OP_AND = 4'b0100,
        OP_OR  = 4'b0101,
        OP_XOR = 4'b0110,
        OP_CMP = 4'b0111,
        OP_INR = 4'b1000,
        OP_DCR = 4'b1001;

    always @(*) begin
        // Defaults
        reg_write      = 0;
        mem_read       = 0;
        mem_write      = 0;
        use_alu        = 0;
        alu_op         = 4'b0000;
        use_immediate  = 0;
        src_reg        = 3'b000;
        dst_reg        = 3'b000;
        halt           = 0;
        is_branch      = 0;
        branch_type = 0;
        inst_length    = 1;
        is_mov         = 0;

        casez (IR)
            
        // === MOV R1, R2 ===
        8'b01??????: begin
            reg_write = 1;
            dst_reg   = IR[5:3];
            src_reg   = IR[2:0];
            is_mov    = 1;
        end

        // === MVI R, D8 ===
        8'b00???110: begin
            reg_write     = 1;
            use_immediate = 1;
            dst_reg       = IR[5:3];
            inst_length   = 2;
        end

        // === ADD R ===
        8'b10000???: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_ADD;
            dst_reg   = 3'b111;      // A
            src_reg   = IR[2:0];     // R
        end

        // === ADC R ===
        8'b10001???: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_ADC;
            dst_reg   = 3'b111;
            src_reg   = IR[2:0];
        end

        // === SUB R ===
        8'b10010???: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_SUB;
            dst_reg   = 3'b111;
            src_reg   = IR[2:0];
        end

        // === SBB R ===
        8'b10011???: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_SBB;
            dst_reg   = 3'b111;
            src_reg   = IR[2:0];
        end

        // === ANA R ===
        8'b10100???: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_AND;
            dst_reg   = 3'b111;
            src_reg   = IR[2:0];
        end

        // === XRA R ===
        8'b10101???: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_XOR;
            dst_reg   = 3'b111;
            src_reg   = IR[2:0];
        end

        // === ORA R ===
        8'b10110???: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_OR;
            dst_reg   = 3'b111;
            src_reg   = IR[2:0];
        end

        // === CMP R ===
        8'b10111???: begin
            reg_write = 0;
            use_alu   = 1;
            alu_op    = OP_CMP;
            dst_reg   = 3'b111;
            src_reg   = IR[2:0];
        end

        // === INR R ===
        8'b00???100: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_INR;
            dst_reg   = IR[5:3];
            src_reg   = IR[5:3];
        end

        // === DCR R ===
        8'b00???101: begin
            reg_write = 1;
            use_alu   = 1;
            alu_op    = OP_DCR;
            dst_reg   = IR[5:3];
            src_reg   = IR[5:3];
        end

        // === LDA addr ===
        8'h3A: begin
            mem_read    = 1;
            reg_write   = 1;
            dst_reg     = 3'b111; // A
            inst_length = 2'b11;
        end

        // === STA addr ===
        8'h32: begin
            mem_write   = 1;
            src_reg     = 3'b111; // A
            inst_length = 2'b11;
        end

        // === HLT ===
        8'h76: begin
            halt = 1;
        end

              // === JUMP instructions ===
        8'hC3: begin // JMP addr
            is_branch   = 1;
            branch_type = 4'b0000;
            inst_length = 2'b11;
        end
        8'hCA: begin // JZ addr
            is_branch   = 1;
            branch_type = 4'b0001;
            inst_length = 2'b11;
        end
        8'hC2: begin // JNZ addr
            is_branch   = 1;
            branch_type = 4'b0010;
            inst_length = 2'b11;
        end
        8'hDA: begin // JC addr
            is_branch   = 1;
            branch_type = 4'b0011;
            inst_length = 2'b11;
        end
        8'hD2: begin // JNC addr
            is_branch   = 1;
            branch_type = 4'b0100;
            inst_length = 2'b11;
        end
        8'hF2: begin // JP addr
            is_branch   = 1;
            branch_type = 4'b0101;
            inst_length = 2'b11;
        end
        8'hFA: begin // JM addr
            is_branch   = 1;
            branch_type = 4'b0110;
            inst_length = 2'b11;
        end
        8'hEA: begin // JPE addr
            is_branch   = 1;
            branch_type = 4'b0111;
            inst_length = 2'b11;
        end
        8'hE2: begin // JPO addr
            is_branch   = 1;
            branch_type = 4'b1000;
            inst_length = 2'b11;
        end
        default: begin
            // Invalid or unimplemented opcode
        end
        endcase
    end

endmodule
