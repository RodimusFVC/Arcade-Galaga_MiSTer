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
// Memory Module with preloaded instruction/data for 8085
module memory #(
    parameter MEM_DEPTH = 512
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [15:0] address,
    input  wire [7:0]  data_in,
    output reg [7:0]  data_out
);

    integer i;
    reg [7:0] mem [0:MEM_DEPTH-1];
always @(posedge clk)
begin
   data_out <= (mem_read && address < MEM_DEPTH) ? mem[address] : 8'd0;
end
    always @(posedge clk) begin
if (rst) begin
    for (i = 0; i < MEM_DEPTH; i = i + 1)
        mem[i] <= 8'd0;

    // === Load A with 0x0F ===
    mem[16'h0000] <= 8'h3E;  // MVI A, 0F
    mem[16'h0001] <= 8'h0F;

    // === Load C with 0x05 ===
    mem[16'h0002] <= 8'h0E;  // MVI C, 05
    mem[16'h0003] <= 8'h05;

    // === INR C ===
    mem[16'h0004] <= 8'h0C;  // INR C  ? C = 06

    // === DCR C ===
    mem[16'h0005] <= 8'h0D;  // DCR C  ? C = 05

    // === CMP C ===
    mem[16'h0006] <= 8'hB9;  // CMP C  ? flags updated (A = 0F, C = 05)

    // === ANA C ===
    mem[16'h0007] <= 8'hA1;  // ANA C  ? A = 0F & 05 = 05

    // === ORA C ===
    mem[16'h0008] <= 8'hB1;  // ORA C  ? A = 05 | 05 = 05

    // === XRA C ===
    mem[16'h0009] <= 8'hA9;  // XRA C  ? A = 05 ^ 05 = 00 ? Zero flag set

    // === Load C with 0x01 again ===
    mem[16'h000A] <= 8'h0E;  // MVI C, 01
    mem[16'h000B] <= 8'h01;

    // === Load A with 0x05 again ===
    mem[16'h000C] <= 8'h3E;  // MVI A, 05
    mem[16'h000D] <= 8'h05;

    // === SUB C ===
    mem[16'h000E] <= 8'h91;  // SUB C  ? A = 05 - 01 = 04

    // === HALT ===
    mem[16'h000F] <= 8'h76;  // HLT
end

         else if (mem_write && address < MEM_DEPTH) begin
            mem[address] <= data_in;
        end
    end
endmodule
