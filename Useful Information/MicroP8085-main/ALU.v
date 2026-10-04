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
module ALU (
    input  alu_enable,
    input  [3:0] alu_op,
    input  [7:0] iA, iB, iF,
    output reg [7:0] oR,
    output reg [7:0] oF,
    output reg       Flag_read_wrbar
);

    // Flag positions
    parameter CARRY_F  = 0;
    parameter PARITY_F = 2;
    parameter AUXC_F   = 4;
    parameter ZERO_F   = 6;
    parameter SIGN_F   = 7;

    reg aux_carry_add, aux_carry_sub;
    reg [8:0] cmp_result;
    wire [8:0] sum, diff;
    wire parity;

    assign sum  = iA + iB + ((alu_op == 4'b0001) ? iF[CARRY_F] : 0); // ADC
    assign diff = iA - iB - ((alu_op == 4'b0011) ? iF[CARRY_F] : 0); // SBB
    assign parity = ~^oR; // Even parity

    always @(*) begin
        oF = 0;
        oR = 0;
        Flag_read_wrbar = 1; // Default: do not write to flags
       if(alu_enable) begin
        case (alu_op)
            4'b0000: begin // ADD
                {oF[CARRY_F], oR} = sum;
                Flag_read_wrbar = 0;
            end
            4'b0001: begin // ADC
                {oF[CARRY_F], oR} = sum;
                Flag_read_wrbar = 0;
            end
            4'b0010: begin // SUB
                {oF[CARRY_F], oR} = diff;
                Flag_read_wrbar = 0;
            end
            4'b0011: begin // SBB
                {oF[CARRY_F], oR} = diff;
                Flag_read_wrbar = 0;
            end
            4'b0100: begin // AND
                oR = iA & iB;
                Flag_read_wrbar = 0;
            end
            4'b0101: begin // OR
                oR = iA | iB;
                Flag_read_wrbar = 0;
            end
            4'b0110: begin // XOR
                oR = iA ^ iB;
                Flag_read_wrbar = 0;
            end
            4'b0111: begin // CMP
                cmp_result = iA - iB;
                oF[CARRY_F]  = cmp_result[8];
                oF[ZERO_F]   = (cmp_result[7:0] == 8'd0);
                oF[SIGN_F]   = cmp_result[7];
                oF[PARITY_F] = ~^cmp_result[7:0];
                oF[AUXC_F]   = (iA[3:0] < iB[3:0]);
                oR = 8'hZZ;
                Flag_read_wrbar = 0;
            end
            4'b1000: begin // INR
                oR = iA + 1;
                oF[CARRY_F] = iF[CARRY_F];
                Flag_read_wrbar = 0;
            end
            4'b1001: begin // DCR
                oR = iA - 1;
                oF[CARRY_F] = iF[CARRY_F];
                Flag_read_wrbar = 0;
            end
            default: begin
                oR = 8'hzz;
                oF = 8'hzz;
            end
        endcase
        end
        oF[ZERO_F] = (oR == 0);  

        if (alu_op != 4'b0111 && alu_op <= 4'b1001) begin
            oF[ZERO_F]   = (oR == 0);
            oF[SIGN_F]   = oR[7];
            oF[PARITY_F] = parity;

            aux_carry_add = ((iA[3:0] + iB[3:0] + (alu_op == 4'b0001 ? iF[CARRY_F] : 0)) > 4'hF);
            aux_carry_sub = ((iA[3:0] - iB[3:0] - (alu_op == 4'b0011 ? iF[CARRY_F] : 0)) < 0);
            oF[AUXC_F] = (alu_op <= 4'b0001) ? aux_carry_add :
                         (alu_op <= 4'b0011) ? aux_carry_sub :
                         0;
        end
    end

endmodule
