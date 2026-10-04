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
module registers(
    input  wire        clk,
    input  wire        rst,
    input  wire        write_en,
    input wire    latch_is_mov,
//    input wire         alu_enable,
    input  wire [2:0]  read_addr1,
    input  wire [2:0]  read_addr2,
    input  wire [2:0]  write_addr,
    input  wire [7:0]  write_data,
    output reg  [7:0]  read_data1,
    output reg  [7:0]  read_data2,

    // ? Flattened debug output for testbench
    output wire [63:0] debug_regs_flat
);

    reg [7:0] regs [0:7]; // B, C, D, E, H, L, M, A

    // Write & reset
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regs[0] <= 8'h00;
            regs[1] <= 8'h00;
            regs[2] <= 8'h00;
            regs[3] <= 8'h00;
            regs[4] <= 8'h00;
            regs[5] <= 8'h00;
            regs[6] <= 8'h00;
            regs[7] <= 8'h03;
        end 
        else if (write_en && write_addr != 3'b110) begin
        if(latch_is_mov) regs[read_addr2]<=regs[read_addr1];
           else  regs[write_addr] <= write_data;
        end
    end

    // Read logic
    always @(*) begin
        read_data1 = (read_addr1 == 3'b110) ? 8'hZZ : regs[read_addr1];
        read_data2 = (read_addr2 == 3'b110) ? 8'hZZ : regs[read_addr2];
    end

    // ? Flatten array into 64-bit wire
    assign debug_regs_flat = {
        regs[7], // A
        regs[6], // M (dummy)
        regs[5], // L
        regs[4], // H
        regs[3], // E
        regs[2], // D
        regs[1], // C
        regs[0]  // B
    };

endmodule
