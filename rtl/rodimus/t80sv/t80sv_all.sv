// t80sv_all.sv - t80sv_alu.sv + t80sv_mcode.sv + t80sv_core.sv + t80sv.sv + t80sv_tops.sv in one file (generated, identical content)
//  Copyright (C) 2026 Rodimus  (SystemVerilog translation; Phoenix 8080 / 8085 additions)
//  Based on T80 (VHDL):
//    Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
//    T80 versions by MikeJ (2005), TobiFlex, Sean Riddle; Copyright (c) 2018 Sorgelig (MiSTer-devel);
//    T80a bus timing by Fabio Belavenuto and Charlie Ingley; T80pa top level by Sorgelig.
//  Redistribution and use in source and synthezised forms, with or without modification, are permitted provided
//  that the following conditions are met: Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer. Redistributions in synthesized form must reproduce the
//  above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
//  materials provided with the distribution. Neither the name of the author nor the names of other contributors
//  may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
//  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// ===== t80sv_alu.sv =====
//============================================================================
//  t80sv_alu - Z80 / 8080 ALU (combinational)
//
//  SystemVerilog translation of T80_ALU.vhd. T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex,
//  Sean Riddle; T80(c) v350 / 351 (c) 2018 Sorgelig and contributors (MiSTer-devel lineage). Phoenix core
//  additions (runtime 8080 mode) by Rodimus.
//  Copyright (C) 2026 Rodimus  (SystemVerilog translation; Phoenix 8080 / 8085 additions)
//  Based on T80 (VHDL):
//    Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
//    T80 versions by MikeJ (2005), TobiFlex, Sean Riddle; Copyright (c) 2018 Sorgelig (MiSTer-devel);
//    T80a bus timing by Fabio Belavenuto and Charlie Ingley; T80pa top level by Sorgelig.
//  Redistribution and use in source and synthezised forms, with or without modification, are permitted provided
//  that the following conditions are met: Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer. Redistributions in synthesized form must reproduce the
//  above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
//  materials provided with the distribution. Neither the name of the author nor the names of other contributors
//  may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
//  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//============================================================================

module t80sv_alu #(
    parameter int Flag_C = 0,
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic [1:0]  mode,          // 0 Z80, 1 fast Z80, 2 8080, 3 GB
    input  logic        Arith16,
    input  logic        Z16,
    input  logic        WZ13,          // MEMPTR bits 13 and 11: BIT n,(HL) X / Y flags
    input  logic        WZ11,
    input  logic [1:0]  XY_State,
    input  logic [3:0]  ALU_Op,
    input  logic        Rot_Akku,
    input  logic [5:0]  IR,
    input  logic [1:0]  ISet,
    input  logic [7:0]  BusA,
    input  logic [7:0]  BusB,
    input  logic [7:0]  F_In,
    output logic [7:0]  Q,
    output logic [7:0]  F_Out
);

logic [7:0] BitMask;
logic       UseCarry, Carry7_v, Overflow_v, HalfCarry_v, Carry_v;
logic [7:0] Q_v;
logic [7:0] B_i;

assign BitMask  = 8'd1 << IR[5:3];
assign UseCarry = ~ALU_Op[2] & ALU_Op[0];
assign B_i      = ALU_Op[1] ? ~BusB : BusB;

// three-stage adder: half carry out of bit 3, carry out of bit 6 and bit 7
assign {HalfCarry_v, Q_v[3:0]} = {1'b0, BusA[3:0]} + {1'b0, B_i[3:0]} + {4'd0, ALU_Op[1] ^ (UseCarry & F_In[Flag_C])};
assign {Carry7_v, Q_v[6:4]}    = {1'b0, BusA[6:4]} + {1'b0, B_i[6:4]} + {3'd0, HalfCarry_v};
assign {Carry_v, Q_v[7]}       = {1'b0, BusA[7]} + {1'b0, B_i[7]} + {1'b0, Carry7_v};

// 8080: P is parity for add / sub too
assign Overflow_v = (mode == 2'd2) ? ~^Q_v : (Carry_v ^ Carry7_v);

logic [7:0] Q_t;
logic [8:0] DAA_Q;

always_comb begin
    Q_t   = 8'h00;     // VHDL "--------"
    F_Out = F_In;
    DAA_Q = 9'h000;
    case (ALU_Op)
    4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101, 4'b0110, 4'b0111: begin
        F_Out[Flag_N] = 1'b0;
        F_Out[Flag_C] = 1'b0;
        case (ALU_Op[2:0])
        3'b000, 3'b001: begin                  // ADD, ADC
            Q_t = Q_v;
            F_Out[Flag_C] = Carry_v;
            F_Out[Flag_H] = HalfCarry_v;
            F_Out[Flag_P] = Overflow_v;
        end
        3'b010, 3'b011, 3'b111: begin          // SUB, SBC, CP
            Q_t = Q_v;
            F_Out[Flag_N] = 1'b1;
            F_Out[Flag_C] = ~Carry_v;
            F_Out[Flag_H] = ~HalfCarry_v;
            F_Out[Flag_P] = Overflow_v;
        end
        3'b100: begin                          // AND
            Q_t = BusA & BusB;
            F_Out[Flag_H] = 1'b1;
        end
        3'b101: begin                          // XOR
            Q_t = BusA ^ BusB;
            F_Out[Flag_H] = 1'b0;
        end
        default: begin                         // OR
            Q_t = BusA | BusB;
            F_Out[Flag_H] = 1'b0;
        end
        endcase
        if (ALU_Op[2:0] == 3'b111) begin       // CP: X / Y from the operand
            F_Out[Flag_X] = BusB[3];
            F_Out[Flag_Y] = BusB[5];
        end else begin
            F_Out[Flag_X] = Q_t[3];
            F_Out[Flag_Y] = Q_t[5];
        end
        if (Q_t == 8'h00) begin
            F_Out[Flag_Z] = 1'b1;
            if (Z16)
                F_Out[Flag_Z] = F_In[Flag_Z];  // 16-bit ADC / SBC
        end else begin
            F_Out[Flag_Z] = 1'b0;
        end
        F_Out[Flag_S] = Q_t[7];
        case (ALU_Op[2:0])
        3'b000, 3'b001, 3'b010, 3'b011, 3'b111: ;
        default: F_Out[Flag_P] = ~^Q_t;
        endcase
        if (Arith16) begin
            F_Out[Flag_S] = F_In[Flag_S];
            F_Out[Flag_Z] = F_In[Flag_Z];
            F_Out[Flag_P] = F_In[Flag_P];
        end
    end
    4'b1100: begin                             // DAA
        if (mode == 2'd3) begin
            F_Out[Flag_H] = 1'b0;
            F_Out[Flag_C] = F_In[Flag_C];
            DAA_Q = {1'b0, BusA};
            if (!F_In[Flag_N]) begin
                if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H])
                    DAA_Q = DAA_Q + 9'd6;
                if (DAA_Q[8:4] > 5'd9 || F_In[Flag_C])
                    DAA_Q = DAA_Q + 9'd96;
            end else begin
                if (F_In[Flag_H]) begin
                    DAA_Q = DAA_Q - 9'd6;
                    if (!F_In[Flag_C])
                        DAA_Q[8] = 1'b0;
                end
                if (F_In[Flag_C])
                    DAA_Q = DAA_Q - 9'd96;
            end
        end else begin
            F_Out[Flag_H] = F_In[Flag_H];
            F_Out[Flag_C] = F_In[Flag_C];
            DAA_Q = {1'b0, BusA};
            if (!F_In[Flag_N]) begin
                if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H]) begin
                    F_Out[Flag_H] = (DAA_Q[3:0] > 4'd9);
                    DAA_Q = DAA_Q + 9'd6;
                end
                if (DAA_Q[8:4] > 5'd9 || F_In[Flag_C])
                    DAA_Q = DAA_Q + 9'd96;
            end else begin
                if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H]) begin
                    if (DAA_Q[3:0] > 4'd5)
                        F_Out[Flag_H] = 1'b0;
                    DAA_Q[7:0] = DAA_Q[7:0] - 8'd6;
                end
                if (BusA > 8'd153 || F_In[Flag_C])
                    DAA_Q = DAA_Q - 9'd352;
            end
        end
        F_Out[Flag_X] = DAA_Q[3];
        F_Out[Flag_Y] = DAA_Q[5];
        F_Out[Flag_C] = F_In[Flag_C] | DAA_Q[8];
        Q_t = DAA_Q[7:0];
        F_Out[Flag_Z] = (DAA_Q[7:0] == 8'h00);
        F_Out[Flag_S] = DAA_Q[7];
        F_Out[Flag_P] = ~^DAA_Q[7:0];
    end
    4'b1101, 4'b1110: begin                    // RLD, RRD
        Q_t[7:4] = BusA[7:4];
        Q_t[3:0] = ALU_Op[0] ? BusB[7:4] : BusB[3:0];
        F_Out[Flag_H] = 1'b0;
        F_Out[Flag_N] = 1'b0;
        F_Out[Flag_X] = Q_t[3];
        F_Out[Flag_Y] = Q_t[5];
        F_Out[Flag_Z] = (Q_t == 8'h00);
        F_Out[Flag_S] = Q_t[7];
        F_Out[Flag_P] = ~^Q_t;
    end
    4'b1001: begin                             // BIT
        Q_t = BusB & BitMask;
        F_Out[Flag_S] = Q_t[7];
        F_Out[Flag_Z] = (Q_t == 8'h00);
        F_Out[Flag_P] = (Q_t == 8'h00);
        F_Out[Flag_H] = 1'b1;
        F_Out[Flag_N] = 1'b0;
        if (IR[2:0] == 3'b110 || XY_State != 2'b00) begin  // BIT n,(HL) / (IX+d): X / Y from MEMPTR
            F_Out[Flag_X] = WZ11;
            F_Out[Flag_Y] = WZ13;
        end else begin
            F_Out[Flag_X] = BusB[3];
            F_Out[Flag_Y] = BusB[5];
        end
    end
    4'b1010: Q_t = BusB | BitMask;             // SET
    4'b1011: Q_t = BusB & ~BitMask;            // RES
    4'b1000: begin                             // rotate / shift
        case (IR[5:3])
        3'b000: begin Q_t = {BusA[6:0], BusA[7]};     F_Out[Flag_C] = BusA[7]; end  // RLC
        3'b010: begin Q_t = {BusA[6:0], F_In[Flag_C]}; F_Out[Flag_C] = BusA[7]; end // RL
        3'b001: begin Q_t = {BusA[0], BusA[7:1]};     F_Out[Flag_C] = BusA[0]; end  // RRC
        3'b011: begin Q_t = {F_In[Flag_C], BusA[7:1]}; F_Out[Flag_C] = BusA[0]; end // RR
        3'b100: begin Q_t = {BusA[6:0], 1'b0};        F_Out[Flag_C] = BusA[7]; end  // SLA
        3'b110: begin                                                               // SLL (undocumented) / GB SWAP
            if (mode == 2'd3) begin
                Q_t = {BusA[3:0], BusA[7:4]};
                F_Out[Flag_C] = 1'b0;
            end else begin
                Q_t = {BusA[6:0], 1'b1};
                F_Out[Flag_C] = BusA[7];
            end
        end
        3'b101: begin Q_t = {BusA[7], BusA[7:1]};     F_Out[Flag_C] = BusA[0]; end  // SRA
        default: begin Q_t = {1'b0, BusA[7:1]};       F_Out[Flag_C] = BusA[0]; end  // SRL
        endcase
        F_Out[Flag_H] = 1'b0;
        F_Out[Flag_N] = 1'b0;
        F_Out[Flag_X] = Q_t[3];
        F_Out[Flag_Y] = Q_t[5];
        F_Out[Flag_S] = Q_t[7];
        F_Out[Flag_Z] = (Q_t == 8'h00);
        F_Out[Flag_P] = ~^Q_t;
        if (ISet == 2'b00) begin               // RLCA / RLA / RRCA / RRA keep S, Z, P
            F_Out[Flag_P] = F_In[Flag_P];
            F_Out[Flag_S] = F_In[Flag_S];
            F_Out[Flag_Z] = F_In[Flag_Z];
        end
        if (mode == 2'd3 && Rot_Akku)
            F_Out[Flag_Z] = 1'b0;
    end
    default: ;
    endcase
    Q = Q_t;
end

endmodule

// ===== t80sv_mcode.sv =====
//============================================================================
//  t80sv_mcode - Z80 / 8080 microcode decoder (combinational)
//
//  SystemVerilog translation of T80_MCode.vhd. T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex,
//  Sean Riddle; T80(c) v350 / 351 (c) 2018 Sorgelig and contributors (MiSTer-devel lineage). Phoenix core
//  additions (runtime 8080 mode) by Rodimus.
//  Copyright (C) 2026 Rodimus  (SystemVerilog translation; Phoenix 8080 / 8085 additions)
//  Based on T80 (VHDL):
//    Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
//    T80 versions by MikeJ (2005), TobiFlex, Sean Riddle; Copyright (c) 2018 Sorgelig (MiSTer-devel);
//    T80a bus timing by Fabio Belavenuto and Charlie Ingley; T80pa top level by Sorgelig.
//  Redistribution and use in source and synthezised forms, with or without modification, are permitted provided
//  that the following conditions are met: Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer. Redistributions in synthesized form must reproduce the
//  above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
//  materials provided with the distribution. Neither the name of the author nor the names of other contributors
//  may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
//  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//  The case body is generated from the VHDL by verify/tools/mcode2sv.py.
//============================================================================

module t80sv_mcode #(
    parameter int MODE   = 0,          // build mode; is_cc_true follows it (GB has no PO / PE / P / M)
    parameter int Flag_C = 0,
    parameter int Flag_P = 2,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic [1:0] mode,           // runtime mode: 0 Z80, 1 fast Z80, 2 8080, 3 GB
    input  logic [7:0] IR,
    input  logic [1:0] ISet,
    input  logic [2:0] MCycle,
    input  logic [7:0] F,
    input  logic       NMICycle,
    input  logic       IntCycle,
    input  logic [1:0] XY_State,
    input  logic       R800_mode,
    output logic [2:0] MCycles,
    output logic [2:0] TStates,
    output logic [1:0] Prefix,         // none, CB, ED, DD / FD
    output logic       Inc_PC,
    output logic       Inc_WZ,
    output logic [3:0] IncDec_16,      // BC, DE, HL, SP; bit 3 = decrement
    output logic       Read_To_Reg,
    output logic       Read_To_Acc,
    output logic [3:0] Set_BusA_To,    // B, C, D, E, H, L, DI, A, SP(L), SP(M), 0, F
    output logic [3:0] Set_BusB_To,    // B, C, D, E, H, L, DI, A, SP(L), SP(M), 1, F, PC(L), PC(M), 0
    output logic [3:0] ALU_Op,
    output logic       Save_ALU,
    output logic       Rot_Akku,
    output logic       PreserveC,
    output logic       Arith16,
    output logic [2:0] Set_Addr_To,
    output logic       IORQ,
    output logic       Jump,
    output logic       JumpE,
    output logic       JumpXY,
    output logic       Call,
    output logic       RstP,
    output logic       LDZ,
    output logic       LDW,
    output logic       LDSPHL,
    output logic       LDHLSP,
    output logic       ADDSPdd,
    output logic [2:0] Special_LD,     // A,I; A,R; I,A; R,A; none
    output logic       ExchangeDH,
    output logic       ExchangeRp,
    output logic       ExchangeAF,
    output logic       ExchangeRS,
    output logic       ExchangeWH,
    output logic       I_DJNZ,
    output logic       I_CPL,
    output logic       I_CCF,
    output logic       I_SCF,
    output logic       I_RETN,
    output logic       I_BT,
    output logic       I_BC,
    output logic       I_BTR,
    output logic       I_RLD,
    output logic       I_RRD,
    output logic       I_INRC,
    output logic       I_MULUB,
    output logic       I_MULU,
    output logic [1:0] SetWZ,
    output logic       SetDI,
    output logic       SetEI,
    output logic [1:0] IMode,
    output logic       Halt,
    output logic       NoRead,
    output logic       Write,
    output logic       No_PC,
    output logic       XYbit_undoc
);

localparam logic [2:0] aNone = 3'b111;
localparam logic [2:0] aBC   = 3'b000;
localparam logic [2:0] aDE   = 3'b001;
localparam logic [2:0] aXY   = 3'b010;
localparam logic [2:0] aIOA  = 3'b100;
localparam logic [2:0] aSP   = 3'b101;
localparam logic [2:0] aZI   = 3'b110;

function automatic logic is_cc_true(input logic [7:0] f, input logic [2:0] cc);
    if (MODE == 3) begin
        case (cc)
        3'b000: is_cc_true = ~f[Flag_Z];
        3'b001: is_cc_true =  f[Flag_Z];
        3'b010: is_cc_true = ~f[Flag_C];
        3'b011: is_cc_true =  f[Flag_C];
        default: is_cc_true = 1'b0;
        endcase
    end else begin
    case (cc)
    3'b000: is_cc_true = ~f[Flag_Z];   // NZ
    3'b001: is_cc_true =  f[Flag_Z];   // Z
    3'b010: is_cc_true = ~f[Flag_C];   // NC
    3'b011: is_cc_true =  f[Flag_C];   // C
    3'b100: is_cc_true = ~f[Flag_P];   // PO
    3'b101: is_cc_true =  f[Flag_P];   // PE
    3'b110: is_cc_true = ~f[Flag_S];   // P
    default: is_cc_true = f[Flag_S];   // M
    endcase
    end
endfunction

logic [2:0] DDD, SSS;
logic [1:0] DPair;
assign DDD   = IR[5:3];
assign SSS   = IR[2:0];
assign DPair = IR[5:4];

always_comb begin
	MCycles = 3'b001;
	if (MCycle == 3'b001) begin
		TStates = 3'b100;
	end else begin
		TStates = 3'b011;
	end
	Prefix = 2'b00;
	Inc_PC = 1'b0;
	Inc_WZ = 1'b0;
	IncDec_16 = 4'b0000;
	Read_To_Acc = 1'b0;
	Read_To_Reg = 1'b0;
	Set_BusB_To = 4'b0000;
	Set_BusA_To = 4'b0000;
	ALU_Op = {1'b0, IR[5:3]};
	Save_ALU = 1'b0;
	Rot_Akku = 1'b0;
	PreserveC = 1'b0;
	Arith16 = 1'b0;
	IORQ = 1'b0;
	Set_Addr_To = aNone;
	Jump = 1'b0;
	JumpE = 1'b0;
	JumpXY = 1'b0;
	Call = 1'b0;
	RstP = 1'b0;
	LDZ = 1'b0;
	LDW = 1'b0;
	LDSPHL = 1'b0;
	LDHLSP = 1'b0;
	ADDSPdd = 1'b0;
	Special_LD = 3'b000;
	ExchangeDH = 1'b0;
	ExchangeRp = 1'b0;
	ExchangeAF = 1'b0;
	ExchangeRS = 1'b0;
	ExchangeWH = 1'b0;
	I_DJNZ = 1'b0;
	I_CPL = 1'b0;
	I_CCF = 1'b0;
	I_SCF = 1'b0;
	I_RETN = 1'b0;
	I_BT = 1'b0;
	I_BC = 1'b0;
	I_BTR = 1'b0;
	I_RLD = 1'b0;
	I_RRD = 1'b0;
	I_INRC = 1'b0;
	I_MULUB = 1'b0;
	I_MULU = 1'b0;
	SetDI = 1'b0;
	SetEI = 1'b0;
	IMode = 2'b11;
	Halt = 1'b0;
	NoRead = 1'b0;
	Write = 1'b0;
	No_PC = 1'b0;
	XYbit_undoc = 1'b0;
	SetWZ = 2'b00;
	case (ISet)
	2'b00: begin
		case (IR)
		8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h47, 8'h48,
		8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4F, 8'h50, 8'h51,
		8'h52, 8'h53, 8'h54, 8'h55, 8'h57, 8'h58, 8'h59, 8'h5A,
		8'h5B, 8'h5C, 8'h5D, 8'h5F, 8'h60, 8'h61, 8'h62, 8'h63,
		8'h64, 8'h65, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C,
		8'h6D, 8'h6F, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7C, 8'h7D,
		8'h7F: begin
			Set_BusB_To[2:0] = SSS;
			ExchangeRp = 1'b1;
			Set_BusA_To[2:0] = DDD;
			Read_To_Reg = 1'b1;
		end
		8'h06, 8'h0E, 8'h16, 8'h1E, 8'h26, 8'h2E, 8'h3E: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				Set_BusA_To[2:0] = DDD;
				Read_To_Reg = 1'b1;
			end
			default: ;
			endcase
		end
		8'h46, 8'h4E, 8'h56, 8'h5E, 8'h66, 8'h6E, 8'h7E: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Set_BusA_To[2:0] = DDD;
				Read_To_Reg = 1'b1;
			end
			default: ;
			endcase
		end
		8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h77: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
				Set_BusB_To[2:0] = SSS;
				Set_BusB_To[3] = 1'b0;
			end
			3'd2: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h36: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				Set_Addr_To = aXY;
				Set_BusB_To[2:0] = SSS;
				Set_BusB_To[3] = 1'b0;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h0A: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
			end
			3'd2: begin
				Read_To_Acc = 1'b1;
			end
			default: ;
			endcase
		end
		8'h1A: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aDE;
			end
			3'd2: begin
				Read_To_Acc = 1'b1;
			end
			default: ;
			endcase
		end
		8'h3A: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					Read_To_Acc = 1'b1;
					IncDec_16 = 4'b1110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
				end
				3'd4: begin
					Read_To_Acc = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h02: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
				Set_BusB_To = 4'b0111;
				SetWZ = 2'b10;
			end
			3'd2: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h12: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aDE;
				Set_BusB_To = 4'b0111;
				SetWZ = 2'b10;
			end
			3'd2: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h32: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
					Set_BusB_To = 4'b0111;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b1110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					SetWZ = 2'b10;
					Inc_PC = 1'b1;
					Set_BusB_To = 4'b0111;
				end
				3'd4: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h01, 8'h11, 8'h21, 8'h31: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b1000;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b1;
				end
			end
			3'd3: begin
				Inc_PC = 1'b1;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b1001;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b0;
				end
			end
			default: ;
			endcase
		end
		8'h2A: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					Read_To_Acc = 1'b1;
					IncDec_16 = 4'b0110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b101;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
					LDW = 1'b1;
				end
				3'd4: begin
					Set_BusA_To[2:0] = 3'b101;
					Read_To_Reg = 1'b1;
					Inc_WZ = 1'b1;
					Set_Addr_To = aZI;
				end
				3'd5: begin
					Set_BusA_To[2:0] = 3'b100;
					Read_To_Reg = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h22: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
					Set_BusB_To = 4'b0111;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b0110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b101;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
					LDW = 1'b1;
					Set_BusB_To = 4'b0101;
				end
				3'd4: begin
					Inc_WZ = 1'b1;
					Set_Addr_To = aZI;
					Write = 1'b1;
					Set_BusB_To = 4'b0100;
				end
				3'd5: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hF9: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				if (MCycle == 3'b010) begin
					LDSPHL = 1'b1;
				end
			end else begin
				TStates = 3'b110;
				LDSPHL = 1'b1;
			end
		end
		8'hC5, 8'hD5, 8'hE5, 8'hF5: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b0111;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b0;
						Set_BusB_To[3] = 1'b0;
					end
				end
				3'd3: begin
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b1011;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b1;
						Set_BusB_To[3] = 1'b0;
					end
					Write = 1'b1;
				end
				3'd4: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b0111;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b0;
						Set_BusB_To[3] = 1'b0;
					end
				end
				3'd2: begin
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b1011;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b1;
						Set_BusB_To[3] = 1'b0;
					end
					Write = 1'b1;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hC1, 8'hD1, 8'hE1, 8'hF1: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aSP;
			end
			3'd2: begin
				IncDec_16 = 4'b0111;
				Set_Addr_To = aSP;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b1011;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b1;
				end
			end
			3'd3: begin
				IncDec_16 = 4'b0111;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b0111;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b0;
				end
			end
			default: ;
			endcase
		end
		8'hEB: begin
			if (mode != 3) begin
				ExchangeDH = 1'b1;
			end
		end
		8'h08: begin
			if (mode == 3) begin
				MCycles = 3'b101;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
					LDW = 1'b1;
					Set_BusB_To = 4'b1000;
				end
				3'd4: begin
					Inc_WZ = 1'b1;
					Set_Addr_To = aZI;
					Write = 1'b1;
					Set_BusB_To = 4'b1001;
				end
				3'd5: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end else if (mode < 2) begin
				ExchangeAF = 1'b1;
			end
		end
		8'hD9: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aSP;
				end
				3'd2: begin
					IncDec_16 = 4'b0111;
					Set_Addr_To = aSP;
					LDZ = 1'b1;
				end
				3'd3: begin
					Jump = 1'b1;
					IncDec_16 = 4'b0111;
					SetEI = 1'b1;
				end
				default: ;
				endcase
			end else if (mode < 2) begin
				ExchangeRS = 1'b1;
			end
		end
		8'hE3: begin
			if (mode != 3) begin
				MCycles = 3'b101;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aSP;
				end
				3'd2: begin
					Set_Addr_To = aSP;
					LDZ = 1'b1;
					IncDec_16 = 4'b0111;
				end
				3'd3: begin
					TStates = 3'b100;
					Set_BusB_To = 4'b0100;
					Set_Addr_To = aSP;
					LDW = 1'b1;
				end
				3'd4: begin
					Set_BusB_To = 4'b0101;
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
				end
				3'd5: begin
					ExchangeWH = 1'b1;
					TStates = 3'b101;
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h87, 8'h88,
		8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8F, 8'h90, 8'h91,
		8'h92, 8'h93, 8'h94, 8'h95, 8'h97, 8'h98, 8'h99, 8'h9A,
		8'h9B, 8'h9C, 8'h9D, 8'h9F, 8'hA0, 8'hA1, 8'hA2, 8'hA3,
		8'hA4, 8'hA5, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC,
		8'hAD, 8'hAF, 8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5,
		8'hB7, 8'hB8, 8'hB9, 8'hBA, 8'hBB, 8'hBC, 8'hBD, 8'hBF: begin
			Set_BusB_To[2:0] = SSS;
			Set_BusA_To[2:0] = 3'b111;
			Read_To_Reg = 1'b1;
			Save_ALU = 1'b1;
		end
		8'h86, 8'h8E, 8'h96, 8'h9E, 8'hA6, 8'hAE, 8'hB6, 8'hBE: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusB_To[2:0] = SSS;
				Set_BusA_To[2:0] = 3'b111;
			end
			default: ;
			endcase
		end
		8'hC6, 8'hCE, 8'hD6, 8'hDE, 8'hE6, 8'hEE, 8'hF6, 8'hFE: begin
			MCycles = 3'b010;
			if (MCycle == 3'b010) begin
				Inc_PC = 1'b1;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusB_To[2:0] = SSS;
				Set_BusA_To[2:0] = 3'b111;
			end
		end
		8'h04, 8'h0C, 8'h14, 8'h1C, 8'h24, 8'h2C, 8'h3C: begin
			Set_BusB_To = 4'b1010;
			Set_BusA_To[2:0] = DDD;
			Read_To_Reg = 1'b1;
			Save_ALU = 1'b1;
			PreserveC = 1'b1;
			ALU_Op = 4'b0000;
		end
		8'h34: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				TStates = 3'b100;
				Set_Addr_To = aXY;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				PreserveC = 1'b1;
				ALU_Op = 4'b0000;
				Set_BusB_To = 4'b1010;
				Set_BusA_To[2:0] = DDD;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h05, 8'h0D, 8'h15, 8'h1D, 8'h25, 8'h2D, 8'h3D: begin
			Set_BusB_To = 4'b1010;
			Set_BusA_To[2:0] = DDD;
			Read_To_Reg = 1'b1;
			Save_ALU = 1'b1;
			PreserveC = 1'b1;
			ALU_Op = 4'b0010;
		end
		8'h35: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				TStates = 3'b100;
				Set_Addr_To = aXY;
				ALU_Op = 4'b0010;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				PreserveC = 1'b1;
				Set_BusB_To = 4'b1010;
				Set_BusA_To[2:0] = DDD;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h27: begin
			Set_BusA_To[2:0] = 3'b111;
			Read_To_Reg = 1'b1;
			ALU_Op = 4'b1100;
			Save_ALU = 1'b1;
		end
		8'h2F: begin
			I_CPL = 1'b1;
		end
		8'h3F: begin
			I_CCF = 1'b1;
		end
		8'h37: begin
			I_SCF = 1'b1;
		end
		8'h00: begin
			if (NMICycle == 1'b1) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1101;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end else if (IntCycle == 1'b1) begin
				if (mode == 3) begin
					MCycles = 3'b100;
					case (MCycle)
					3'd1: begin
						TStates = 3'b110;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1101;
					end
					3'd2: begin
						Write = 1'b1;
					end
					3'd3: begin
						LDZ = 1'b1;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1100;
					end
					3'd4: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end else begin
					MCycles = 3'b101;
					case (MCycle)
					3'd1: begin
						TStates = 3'b101;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1101;
					end
					3'd2: begin
						Write = 1'b1;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1100;
					end
					3'd3: begin
						Write = 1'b1;
					end
					3'd4: begin
						Inc_PC = 1'b1;
						LDZ = 1'b1;
					end
					3'd5: begin
						Jump = 1'b1;
					end
					default: ;
					endcase
				end
			end
		end
		8'h76: begin
			Halt = 1'b1;
		end
		8'hF3: begin
			SetDI = 1'b1;
		end
		8'hFB: begin
			SetEI = 1'b1;
		end
		8'h09, 8'h19, 8'h29, 8'h39: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					NoRead = 1'b1;
					ALU_Op = 4'b0000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_BusA_To[2:0] = 3'b101;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
						Set_BusB_To[0] = 1'b1;
					end
					default: begin
						Set_BusB_To = 4'b1000;
					end
					endcase
					TStates = 3'b100;
					Arith16 = 1'b1;
					SetWZ = 2'b11;
				end
				3'd2: begin
					NoRead = 1'b1;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					ALU_Op = 4'b0001;
					Set_BusA_To[2:0] = 3'b100;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
					end
					default: begin
						Set_BusB_To = 4'b1001;
					end
					endcase
					Arith16 = 1'b1;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					No_PC = 1'b1;
				end
				3'd2: begin
					NoRead = 1'b1;
					ALU_Op = 4'b0000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_BusA_To[2:0] = 3'b101;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
						Set_BusB_To[0] = 1'b1;
					end
					default: begin
						Set_BusB_To = 4'b1000;
					end
					endcase
					TStates = 3'b100;
					Arith16 = 1'b1;
					SetWZ = 2'b11;
					No_PC = 1'b1;
				end
				3'd3: begin
					NoRead = 1'b1;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					ALU_Op = 4'b0001;
					Set_BusA_To[2:0] = 3'b100;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
					end
					default: begin
						Set_BusB_To = 4'b1001;
					end
					endcase
					Arith16 = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h03, 8'h13, 8'h23, 8'h33: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd2: begin
					IncDec_16[3:2] = 2'b01;
					IncDec_16[1:0] = DPair;
				end
				default: ;
				endcase
			end else begin
				TStates = 3'b110;
				IncDec_16[3:2] = 2'b01;
				IncDec_16[1:0] = DPair;
			end
		end
		8'h0B, 8'h1B, 8'h2B, 8'h3B: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd2: begin
					IncDec_16[3:2] = 2'b11;
					IncDec_16[1:0] = DPair;
				end
				default: ;
				endcase
			end else begin
				TStates = 3'b110;
				IncDec_16[3:2] = 2'b11;
				IncDec_16[1:0] = DPair;
			end
		end
		8'h07, 8'h17, 8'h0F, 8'h1F: begin
			Set_BusA_To[2:0] = 3'b111;
			ALU_Op = 4'b1000;
			Read_To_Reg = 1'b1;
			Rot_Akku = 1'b1;
			Save_ALU = 1'b1;
		end
		8'hC3: begin
			if (mode == 3) begin
				MCycles = 3'b100;
			end else begin
				MCycles = 3'b011;
			end
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				Inc_PC = 1'b1;
				Jump = 1'b1;
				if (mode != 3) begin
					LDW = 1'b1;
				end
			end
			default: ;
			endcase
		end
		8'hC2, 8'hCA, 8'hD2, 8'hDA, 8'hE2, 8'hEA, 8'hF2, 8'hFA: begin
			if (IR[5] == 1'b1 && mode == 3) begin
				case (IR[4:3])
				2'b00: begin
					MCycles = 3'b010;
					case (MCycle)
					3'd1: begin
						Set_Addr_To = aBC;
						Set_BusB_To = 4'b0111;
						IORQ = 1'b1;
					end
					3'd2: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end
				2'b01: begin
					MCycles = 3'b100;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						LDZ = 1'b1;
					end
					3'd3: begin
						Set_Addr_To = aZI;
						Inc_PC = 1'b1;
						Set_BusB_To = 4'b0111;
					end
					3'd4: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end
				2'b10: begin
					MCycles = 3'b010;
					case (MCycle)
					3'd1: begin
						Set_Addr_To = aBC;
						IORQ = 1'b1;
					end
					3'd2: begin
						Read_To_Acc = 1'b1;
					end
					default: ;
					endcase
				end
				2'b11: begin
					MCycles = 3'b100;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						LDZ = 1'b1;
					end
					3'd3: begin
						Set_Addr_To = aZI;
						Inc_PC = 1'b1;
					end
					3'd4: begin
						Read_To_Acc = 1'b1;
					end
					default: ;
					endcase
				end
				endcase
			end else begin
				if (mode == 3) begin
					MCycles = 3'b100;
				end else begin
					MCycles = 3'b011;
				end
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					if (mode != 3) begin
						LDW = 1'b1;
					end
					Inc_PC = 1'b1;
					if (is_cc_true(F, IR[5:3])) begin
						Jump = 1'b1;
					end else if (mode == 3) begin
						MCycles = 3'b011;
					end
				end
				default: ;
				endcase
			end
		end
		8'h18: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					No_PC = 1'b1;
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h38: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_C] == 1'b0) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h30: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_C] == 1'b1) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h28: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_Z] == 1'b0) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h20: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_Z] == 1'b1) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'hE9: begin
			JumpXY = 1'b1;
		end
		8'h10: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				I_DJNZ = 1'b1;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
				end
				default: ;
				endcase
			end else if (mode < 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					I_DJNZ = 1'b1;
					Set_BusB_To = 4'b1010;
					Set_BusA_To[2:0] = 3'b000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					ALU_Op = 4'b0010;
				end
				3'd2: begin
					I_DJNZ = 1'b1;
					Inc_PC = 1'b1;
					No_PC = 1'b1;
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'hCD: begin
			if (mode == 3) begin
				MCycles = 3'b110;
			end else begin
				MCycles = 3'b101;
			end
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				IncDec_16 = 4'b1111;
				Inc_PC = 1'b1;
				TStates = 3'b100;
				Set_Addr_To = aSP;
				LDW = 1'b1;
				Set_BusB_To = 4'b1101;
			end
			3'd4: begin
				Write = 1'b1;
				IncDec_16 = 4'b1111;
				Set_Addr_To = aSP;
				Set_BusB_To = 4'b1100;
			end
			3'd5: begin
				Write = 1'b1;
				Call = 1'b1;
			end
			default: ;
			endcase
		end
		8'hC4, 8'hCC, 8'hD4, 8'hDC, 8'hE4, 8'hEC, 8'hF4, 8'hFC: begin
			if (IR[5] == 1'b0 || mode != 3) begin
				if (mode == 3) begin
					MCycles = 3'b110;
				end else begin
					MCycles = 3'b101;
				end
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Inc_PC = 1'b1;
					LDW = 1'b1;
					if (is_cc_true(F, IR[5:3])) begin
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						TStates = 3'b100;
						Set_BusB_To = 4'b1101;
					end else begin
						MCycles = 3'b011;
					end
				end
				3'd4: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd5: begin
					Write = 1'b1;
					Call = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hC9: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					Set_Addr_To = aSP;
				end
				3'd3: begin
					IncDec_16 = 4'b0111;
					Set_Addr_To = aSP;
					LDZ = 1'b1;
				end
				3'd4: begin
					Jump = 1'b1;
					IncDec_16 = 4'b0111;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aSP;
				end
				3'd2: begin
					IncDec_16 = 4'b0111;
					Set_Addr_To = aSP;
					LDZ = 1'b1;
				end
				3'd3: begin
					Jump = 1'b1;
					IncDec_16 = 4'b0111;
				end
				default: ;
				endcase
			end
		end
		8'hC0, 8'hC8, 8'hD0, 8'hD8, 8'hE0, 8'hE8, 8'hF0, 8'hF8: begin
			if (IR[5] == 1'b1 && mode == 3) begin
				case (IR[4:3])
				2'b00: begin
					MCycles = 3'b011;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						Set_Addr_To = aIOA;
						Set_BusB_To = 4'b0111;
					end
					3'd3: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end
				2'b01: begin
					MCycles = 3'b100;
					case (MCycle)
					3'd3: begin
						Inc_PC = 1'b1;
						ADDSPdd = 1'b1;
					end
					default: ;
					endcase
				end
				2'b10: begin
					MCycles = 3'b011;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						Set_Addr_To = aIOA;
					end
					3'd3: begin
						Read_To_Acc = 1'b1;
					end
					default: ;
					endcase
				end
				2'b11: begin
					MCycles = 3'b011;
					case (MCycle)
					3'd1: begin
						Inc_PC = 1'b1;
					end
					3'd2: begin
						LDHLSP = 1'b1;
						Inc_PC = 1'b1;
					end
					3'd3: begin
						LDHLSP = 1'b1;
					end
					default: ;
					endcase
				end
				endcase
			end else begin
				if (mode == 3) begin
					MCycles = 3'b101;
					case (MCycle)
					3'd2: begin
						if (is_cc_true(F, IR[5:3])) begin
							Set_Addr_To = aSP;
						end else begin
							MCycles = 3'b010;
						end
						TStates = 3'b101;
					end
					3'd3: begin
						IncDec_16 = 4'b0111;
						Set_Addr_To = aSP;
						LDZ = 1'b1;
					end
					3'd4: begin
						Jump = 1'b1;
						IncDec_16 = 4'b0111;
					end
					default: ;
					endcase
				end else begin
					MCycles = 3'b011;
					case (MCycle)
					3'd1: begin
						if (is_cc_true(F, IR[5:3])) begin
							Set_Addr_To = aSP;
						end else begin
							MCycles = 3'b001;
						end
						TStates = 3'b101;
					end
					3'd2: begin
						IncDec_16 = 4'b0111;
						Set_Addr_To = aSP;
						LDZ = 1'b1;
					end
					3'd3: begin
						Jump = 1'b1;
						IncDec_16 = 4'b0111;
					end
					default: ;
					endcase
				end
			end
		end
		8'hC7, 8'hCF, 8'hD7, 8'hDF, 8'hE7, 8'hEF, 8'hF7, 8'hFF: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1101;
				end
				3'd3: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd4: begin
					Write = 1'b1;
					RstP = 1'b1;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1101;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd3: begin
					Write = 1'b1;
					RstP = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hDB: begin
			if (mode != 3) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					Set_Addr_To = aIOA;
				end
				3'd3: begin
					Read_To_Acc = 1'b1;
					IORQ = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hD3: begin
			if (mode != 3) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					Set_Addr_To = aIOA;
					Set_BusB_To = 4'b0111;
				end
				3'd3: begin
					Write = 1'b1;
					IORQ = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hCB: begin
			if (mode != 2) begin
				Prefix = 2'b01;
			end
		end
		8'hED: begin
			if (mode < 2) begin
				Prefix = 2'b10;
			end
		end
		8'hDD, 8'hFD: begin
			if (mode < 2) begin
				Prefix = 2'b11;
			end
		end
		endcase
	end
	2'b01: begin
		Set_BusA_To[2:0] = IR[2:0];
		Set_BusB_To[2:0] = IR[2:0];
		case (IR)
		8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h07, 8'h10,
		8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h17, 8'h08, 8'h09,
		8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0F, 8'h18, 8'h19, 8'h1A,
		8'h1B, 8'h1C, 8'h1D, 8'h1F, 8'h20, 8'h21, 8'h22, 8'h23,
		8'h24, 8'h25, 8'h27, 8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C,
		8'h2D, 8'h2F, 8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35,
		8'h37, 8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3F: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					ALU_Op = 4'b1000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
				end
			end else begin
				MCycles = 3'b011;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_Addr_To = aXY;
					TStates = 3'b100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h06, 8'h16, 8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h26, 8'h36: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1000;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_Addr_To = aXY;
				TStates = 3'b100;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h47, 8'h48,
		8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4F, 8'h50, 8'h51,
		8'h52, 8'h53, 8'h54, 8'h55, 8'h57, 8'h58, 8'h59, 8'h5A,
		8'h5B, 8'h5C, 8'h5D, 8'h5F, 8'h60, 8'h61, 8'h62, 8'h63,
		8'h64, 8'h65, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C,
		8'h6D, 8'h6F, 8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75,
		8'h77, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7C, 8'h7D, 8'h7F: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					Set_BusB_To[2:0] = IR[2:0];
					ALU_Op = 4'b1001;
				end
			end else begin
				MCycles = 3'b010;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1001;
					TStates = 3'b100;
				end
				default: ;
				endcase
			end
		end
		8'h46, 8'h4E, 8'h56, 8'h5E, 8'h66, 8'h6E, 8'h76, 8'h7E: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1001;
				TStates = 3'b100;
			end
			default: ;
			endcase
		end
		8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC7, 8'hC8,
		8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD, 8'hCF, 8'hD0, 8'hD1,
		8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD7, 8'hD8, 8'hD9, 8'hDA,
		8'hDB, 8'hDC, 8'hDD, 8'hDF, 8'hE0, 8'hE1, 8'hE2, 8'hE3,
		8'hE4, 8'hE5, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC,
		8'hED, 8'hEF, 8'hF0, 8'hF1, 8'hF2, 8'hF3, 8'hF4, 8'hF5,
		8'hF7, 8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD, 8'hFF: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					ALU_Op = 4'b1010;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
				end
			end else begin
				MCycles = 3'b011;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1010;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_Addr_To = aXY;
					TStates = 3'b100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hC6, 8'hCE, 8'hD6, 8'hDE, 8'hE6, 8'hEE, 8'hF6, 8'hFE: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1010;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_Addr_To = aXY;
				TStates = 3'b100;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h87, 8'h88,
		8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8F, 8'h90, 8'h91,
		8'h92, 8'h93, 8'h94, 8'h95, 8'h97, 8'h98, 8'h99, 8'h9A,
		8'h9B, 8'h9C, 8'h9D, 8'h9F, 8'hA0, 8'hA1, 8'hA2, 8'hA3,
		8'hA4, 8'hA5, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC,
		8'hAD, 8'hAF, 8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5,
		8'hB7, 8'hB8, 8'hB9, 8'hBA, 8'hBB, 8'hBC, 8'hBD, 8'hBF: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					ALU_Op = 4'b1011;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
				end
			end else begin
				MCycles = 3'b011;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1011;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_Addr_To = aXY;
					TStates = 3'b100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h86, 8'h8E, 8'h96, 8'h9E, 8'hA6, 8'hAE, 8'hB6, 8'hBE: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1011;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_Addr_To = aXY;
				TStates = 3'b100;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		endcase
	end
	default: begin
		case (IR)
		8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
		8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
		8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
		8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F,
		8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
		8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F,
		8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
		8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F,
		8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87,
		8'h88, 8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8E, 8'h8F,
		8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97,
		8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F,
		8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hAC, 8'hAD, 8'hAE, 8'hAF,
		8'hB4, 8'hB5, 8'hB6, 8'hB7, 8'hBC, 8'hBD, 8'hBE, 8'hBF,
		8'hC0, 8'hC2, 8'hC4, 8'hC5, 8'hC6, 8'hC7, 8'hC8, 8'hCA,
		8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF, 8'hD0, 8'hD2, 8'hD3,
		8'hD4, 8'hD5, 8'hD6, 8'hD7, 8'hD8, 8'hDA, 8'hDB, 8'hDC,
		8'hDD, 8'hDE, 8'hDF, 8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE4,
		8'hE5, 8'hE6, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC,
		8'hED, 8'hEE, 8'hEF, 8'hF0, 8'hF1, 8'hF2, 8'hF4, 8'hF5,
		8'hF6, 8'hF7, 8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD,
		8'hFE, 8'hFF: ;
		8'h77, 8'h7F: ;
		8'h57: begin
			Special_LD = 3'b100;
			TStates = 3'b101;
		end
		8'h5F: begin
			Special_LD = 3'b101;
			TStates = 3'b101;
		end
		8'h47: begin
			Special_LD = 3'b110;
			TStates = 3'b101;
		end
		8'h4F: begin
			Special_LD = 3'b111;
			TStates = 3'b101;
		end
		8'h4B, 8'h5B, 8'h6B, 8'h7B: begin
			MCycles = 3'b101;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				Set_Addr_To = aZI;
				Inc_PC = 1'b1;
				LDW = 1'b1;
			end
			3'd4: begin
				Read_To_Reg = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusA_To = 4'b1000;
				end else begin
					Set_BusA_To[2:1] = IR[5:4];
					Set_BusA_To[0] = 1'b1;
				end
				Inc_WZ = 1'b1;
				Set_Addr_To = aZI;
			end
			3'd5: begin
				Read_To_Reg = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusA_To = 4'b1001;
				end else begin
					Set_BusA_To[2:1] = IR[5:4];
					Set_BusA_To[0] = 1'b0;
				end
			end
			default: ;
			endcase
		end
		8'h43, 8'h53, 8'h63, 8'h73: begin
			MCycles = 3'b101;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				Set_Addr_To = aZI;
				Inc_PC = 1'b1;
				LDW = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusB_To = 4'b1000;
				end else begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b1;
					Set_BusB_To[3] = 1'b0;
				end
			end
			3'd4: begin
				Inc_WZ = 1'b1;
				Set_Addr_To = aZI;
				Write = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusB_To = 4'b1001;
				end else begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b0;
					Set_BusB_To[3] = 1'b0;
				end
			end
			3'd5: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'hA0, 8'hA8, 8'hB0, 8'hB8: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
				IncDec_16 = 4'b1100;
			end
			3'd2: begin
				Set_BusB_To = 4'b0110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b0000;
				Set_Addr_To = aDE;
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
			end
			3'd3: begin
				I_BT = 1'b1;
				TStates = 3'b101;
				Write = 1'b1;
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0101;
				end else begin
					IncDec_16 = 4'b1101;
				end
				No_PC = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'hA1, 8'hA9, 8'hB1, 8'hB9: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
				IncDec_16 = 4'b1100;
			end
			3'd2: begin
				Set_BusB_To = 4'b0110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b0111;
				Save_ALU = 1'b1;
				PreserveC = 1'b1;
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
				No_PC = 1'b1;
			end
			3'd3: begin
				NoRead = 1'b1;
				I_BC = 1'b1;
				TStates = 3'b101;
				No_PC = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'h44, 8'h4C, 8'h54, 8'h5C, 8'h64, 8'h6C, 8'h74, 8'h7C: begin
			ALU_Op = 4'b0010;
			Set_BusB_To = 4'b0111;
			Set_BusA_To = 4'b1010;
			Read_To_Acc = 1'b1;
			Save_ALU = 1'b1;
		end
		8'h46, 8'h4E, 8'h66, 8'h6E: begin
			IMode = 2'b00;
		end
		8'h56, 8'h76: begin
			IMode = 2'b01;
		end
		8'h5E, 8'h7E: begin
			IMode = 2'b10;
		end
		8'h4A, 8'h5A, 8'h6A, 8'h7A: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				No_PC = 1'b1;
			end
			3'd2: begin
				NoRead = 1'b1;
				ALU_Op = 4'b0001;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusA_To[2:0] = 3'b101;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b1;
				end
				default: begin
					Set_BusB_To = 4'b1000;
				end
				endcase
				TStates = 3'b100;
				SetWZ = 2'b11;
				No_PC = 1'b1;
			end
			3'd3: begin
				NoRead = 1'b1;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				ALU_Op = 4'b0001;
				Set_BusA_To[2:0] = 3'b100;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b0;
				end
				default: begin
					Set_BusB_To = 4'b1001;
				end
				endcase
			end
			default: ;
			endcase
		end
		8'h42, 8'h52, 8'h62, 8'h72: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				No_PC = 1'b1;
			end
			3'd2: begin
				NoRead = 1'b1;
				ALU_Op = 4'b0011;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusA_To[2:0] = 3'b101;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b1;
				end
				default: begin
					Set_BusB_To = 4'b1000;
				end
				endcase
				TStates = 3'b100;
				SetWZ = 2'b11;
				No_PC = 1'b1;
			end
			3'd3: begin
				NoRead = 1'b1;
				ALU_Op = 4'b0011;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusA_To[2:0] = 3'b100;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
				end
				default: begin
					Set_BusB_To = 4'b1001;
				end
				endcase
			end
			default: ;
			endcase
		end
		8'h6F: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Read_To_Reg = 1'b1;
				Set_BusB_To[2:0] = 3'b110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b1101;
				Save_ALU = 1'b1;
				No_PC = 1'b1;
			end
			3'd3: begin
				TStates = 3'b100;
				I_RLD = 1'b1;
				NoRead = 1'b1;
				Set_Addr_To = aXY;
			end
			3'd4: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h67: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Read_To_Reg = 1'b1;
				Set_BusB_To[2:0] = 3'b110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b1110;
				Save_ALU = 1'b1;
				No_PC = 1'b1;
			end
			3'd3: begin
				TStates = 3'b100;
				I_RRD = 1'b1;
				NoRead = 1'b1;
				Set_Addr_To = aXY;
			end
			3'd4: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h45, 8'h4D, 8'h55, 8'h5D, 8'h65, 8'h6D, 8'h75, 8'h7D: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aSP;
			end
			3'd2: begin
				IncDec_16 = 4'b0111;
				Set_Addr_To = aSP;
				LDZ = 1'b1;
			end
			3'd3: begin
				Jump = 1'b1;
				IncDec_16 = 4'b0111;
				LDW = 1'b1;
				I_RETN = 1'b1;
			end
			default: ;
			endcase
		end
		8'h40, 8'h48, 8'h50, 8'h58, 8'h60, 8'h68, 8'h70, 8'h78: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
				SetWZ = 2'b01;
			end
			3'd2: begin
				IORQ = 1'b1;
				if (IR[5:3] != 3'b110) begin
					Read_To_Reg = 1'b1;
					Set_BusA_To[2:0] = IR[5:3];
				end
				I_INRC = 1'b1;
			end
			default: ;
			endcase
		end
		8'h41, 8'h49, 8'h51, 8'h59, 8'h61, 8'h69, 8'h71, 8'h79: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
				SetWZ = 2'b01;
				Set_BusB_To[2:0] = IR[5:3];
				if (IR[5:3] == 3'b110) begin
					Set_BusB_To[3] = 1'b1;
				end
			end
			3'd2: begin
				Write = 1'b1;
				IORQ = 1'b1;
			end
			default: ;
			endcase
		end
		8'hA2, 8'hAA, 8'hB2, 8'hBA: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				TStates = 3'b101;
				Set_Addr_To = aBC;
				Set_BusB_To = 4'b1010;
				Set_BusA_To = 4'b0000;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				ALU_Op = 4'b0010;
				SetWZ = 2'b11;
				IncDec_16[3] = IR[3];
			end
			3'd2: begin
				IORQ = 1'b1;
				Set_BusB_To = 4'b0110;
				Set_Addr_To = aXY;
			end
			3'd3: begin
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
				Write = 1'b1;
				I_BTR = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'hA3, 8'hAB, 8'hB3, 8'hBB: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				TStates = 3'b101;
				Set_Addr_To = aXY;
				Set_BusB_To = 4'b1010;
				Set_BusA_To = 4'b0000;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				ALU_Op = 4'b0010;
			end
			3'd2: begin
				Set_BusB_To = 4'b0110;
				Set_Addr_To = aBC;
				SetWZ = 2'b11;
				IncDec_16[3] = IR[3];
			end
			3'd3: begin
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
				IORQ = 1'b1;
				Write = 1'b1;
				I_BTR = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'hC1, 8'hC9, 8'hD1, 8'hD9: begin
			if (R800_mode == 1'b1) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					NoRead = 1'b1;
					I_MULUB = 1'b1;
					Set_BusB_To[2:0] = IR[5:3];
					Set_BusB_To[3] = 1'b0;
				end
				3'd2: begin
					NoRead = 1'b1;
					I_MULU = 1'b1;
					Set_BusA_To[2:0] = 3'b100;
				end
				default: ;
				endcase
			end
		end
		8'hC3, 8'hF3: begin
			if (R800_mode == 1'b1) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					NoRead = 1'b1;
					if (DPair == 2'b11) begin
						Set_BusB_To[3:0] = 4'b1000;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b0;
						Set_BusB_To[3] = 1'b0;
					end
					Set_BusA_To[2:0] = 3'b100;
				end
				3'd2: begin
					TStates = 3'b101;
					NoRead = 1'b1;
					I_MULU = 1'b1;
					Set_BusA_To[2:0] = 3'b100;
				end
				default: ;
				endcase
			end
		end
		endcase
	end
	endcase
	if (mode == 1) begin
		if (!(MCycle == 3'b001)) begin
			TStates = 3'b011;
		end
	end
	if (mode == 3) begin
		if (!(MCycle == 3'b001)) begin
			TStates = 3'b100;
		end
	end
	if (mode < 2) begin
		if (MCycle == 3'b110) begin
			Inc_PC = 1'b1;
			if (mode == 1) begin
				Set_Addr_To = aXY;
				TStates = 3'b100;
				Set_BusB_To[2:0] = SSS;
				Set_BusB_To[3] = 1'b0;
			end
			if (IR == 8'h36 || IR == 8'hCB) begin
				Set_Addr_To = aNone;
			end
			if (!(IR == 8'h36 || ISet == 2'b01)) begin
				No_PC = 1'b1;
			end
		end
		if (MCycle == 3'b111) begin
			if (mode == 0) begin
				TStates = 3'b101;
			end
			if (ISet != 2'b01) begin
				Set_Addr_To = aXY;
			end
			Set_BusB_To[2:0] = SSS;
			Set_BusB_To[3] = 1'b0;
			if (IR == 8'h36 || ISet == 2'b01) begin
				Inc_PC = 1'b1;
			end else begin
				NoRead = 1'b1;
			end
		end
	end
end

endmodule

// ===== t80sv_core.sv =====
//============================================================================
//  t80sv_core - Z80 / 8080 / 8085-subset CPU core, cycle-identical to T80 (MiSTer-devel T80 v350 / 351)
//
//  SystemVerilog translation of T80.vhd + T80_Reg.vhd. T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ,
//  TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018 Sorgelig and contributors (MiSTer-devel lineage).
//  Phoenix core additions (runtime I8080 = 8080 mode, I8085 RIM / SIM / SOD) by Rodimus.
//  Copyright (C) 2026 Rodimus  (SystemVerilog translation; Phoenix 8080 / 8085 additions)
//  Based on T80 (VHDL):
//    Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
//    T80 versions by MikeJ (2005), TobiFlex, Sean Riddle; Copyright (c) 2018 Sorgelig (MiSTer-devel);
//    T80a bus timing by Fabio Belavenuto and Charlie Ingley; T80pa top level by Sorgelig.
//  Redistribution and use in source and synthezised forms, with or without modification, are permitted provided
//  that the following conditions are met: Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer. Redistributions in synthesized form must reproduce the
//  above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
//  materials provided with the distribution. Neither the name of the author nor the names of other contributors
//  may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
//  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//============================================================================

module t80sv_core #(
    parameter int MODE   = 0,          // 0 Z80, 1 fast Z80, 2 8080, 3 GB
    parameter int IOWAIT = 0,          // 0 single-cycle I/O, 1 standard I/O cycle
    parameter int Flag_C = 0,          // flag bit positions (GB: C 4, H 5, N 6, Z 7, S / P / X / Y 0)
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        IORQ,
    output logic        NoRead,
    output logic        Write,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DInst,
    input  logic [7:0]  DI,
    output logic [7:0]  DO,
    output logic [2:0]  MC,
    output logic [2:0]  TS,
    output logic        IntCycle_n,
    output logic        IntE,
    output logic        Stop,
    input  logic        R800_mode,
    input  logic        out0,          // 0: OUT (C),0; 1: OUT (C),255
    output logic [211:0] REG,          // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    input  logic        DIRSet,        // load all registers from DIR
    input  logic [211:0] DIR,
    input  logic        I8080,         // MODE 0 build: 8080 mode while high
    input  logic        I8085,         // 8080 mode: opcode 20 = RIM (A <= RIM_D), 30 = SIM (SOD)
    input  logic [7:0]  RIM_D,
    output logic        SOD
);

localparam logic [2:0] aBC  = 3'b000;
localparam logic [2:0] aDE  = 3'b001;
localparam logic [2:0] aXY  = 3'b010;
localparam logic [2:0] aIOA = 3'b100;
localparam logic [2:0] aSP  = 3'b101;
localparam logic [2:0] aZI  = 3'b110;

localparam logic [1:0] MODE2 = MODE[1:0];
logic [1:0] mode;                      // MODE, or 2 (8080) while I8080 = 1 on a MODE 0 build
assign mode = (MODE == 0 && I8080) ? 2'd2 : MODE2;

// Registers
logic [7:0]  ACC, F, Ap, Fp, I, R;
logic [15:0] SP, PC;

logic [7:0]  RegDIH, RegDIL;
logic [15:0] RegBusA, RegBusB, RegBusC;
logic [2:0]  RegAddrA_r, RegAddrA, RegAddrB_r, RegAddrB, RegAddrC;
logic        RegWEH, RegWEL;
logic        Alternate;

// Help registers
logic [15:0] WZ;                       // MEMPTR
logic [7:0]  IR;
logic [1:0]  ISet;
logic [15:0] RegBusA_r;
logic [15:0] ID16;
logic [7:0]  Save_Mux;
logic [31:0] MULU_Prod32, MULU_tmp;
logic [15:0] MULU_Fakt1;
logic [15:0] TmpAddr2;
logic [127:0] DOR;

logic [2:0]  TState;
logic [2:0]  MCycle;
logic        IntE_FF1, IntE_FF2;
logic        Halt_FF;
logic        BusReq_s = 1'b0;
logic        BusAck = 1'b0;
logic        ClkEn;
logic        NMI_s;
logic        OldNMI_n;
logic [1:0]  IStatus;

logic [7:0]  DI_Reg;
logic        T_Res;
logic [1:0]  XY_State;
logic [2:0]  Pre_XY_F_M;
logic        NextIs_XY_Fetch;
logic        XY_Ind;
logic        No_BTR;
logic        BTR_r;
logic        Auto_Wait;
logic        Auto_Wait_t1;
logic        Auto_Wait_t2;
logic        IncDecZ;
logic        SOD_r;

// ALU
logic [7:0]  BusB, BusA, ALU_Q, F_Out;

// Registered microcode outputs
logic [4:0]  Read_To_Reg_r;
logic        Arith16_r, Z16_r;
logic [3:0]  ALU_Op_r;
logic        Save_ALU_r, PreserveC_r;
logic [2:0]  MCycles;
logic        I_RXDD;

// Microcode outputs
logic [2:0]  MCycles_d, TStates;
logic        IntCycle, NMICycle;
logic        Inc_PC, Inc_WZ;
logic [3:0]  IncDec_16;
logic [1:0]  Prefix;
logic        Read_To_Acc, Read_To_Reg;
logic [3:0]  Set_BusB_To, Set_BusA_To, ALU_Op;
logic        Save_ALU, Rot_Akku, PreserveC, Arith16;
logic [2:0]  Set_Addr_To;
logic        Jump, JumpE, JumpXY, Call, RstP, LDZ, LDW, LDSPHL, LDHLSP, ADDSPdd;
logic        IORQ_i;
logic [2:0]  Special_LD;
logic        ExchangeDH, ExchangeRp, ExchangeAF, ExchangeRS, ExchangeWH;
logic        I_DJNZ, I_CPL, I_CCF, I_SCF, I_RETN, I_BT, I_BC, I_BTR, I_RLD, I_RRD, I_INRC, I_MULUB, I_MULU;
logic [1:0]  SetWZ;
logic        SetDI, SetEI;
logic [1:0]  IMode;
logic        Halt, XYbit_undoc, No_PC;

assign REG = Alternate ? {IntE_FF2, IntE_FF1, IStatus, DOR[127:112], DOR[47:0], DOR[63:48], DOR[111:64], PC, SP, R, I, Fp, Ap, F, ACC}
                       : {IntE_FF2, IntE_FF1, IStatus, DOR, PC, SP, R, I, Fp, Ap, F, ACC};

t80sv_mcode #(.MODE(MODE), .Flag_C(Flag_C), .Flag_P(Flag_P), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) mcode (
    .mode(mode), .IR(IR), .ISet(ISet), .MCycle(MCycle), .F(F), .NMICycle(NMICycle), .IntCycle(IntCycle),
    .XY_State(XY_State), .R800_mode(R800_mode), .Rot_Akku(Rot_Akku), .LDHLSP(LDHLSP), .ADDSPdd(ADDSPdd),
    .I_MULUB(I_MULUB), .I_MULU(I_MULU), .MCycles(MCycles_d), .TStates(TStates), .Prefix(Prefix), .Inc_PC(Inc_PC),
    .Inc_WZ(Inc_WZ), .IncDec_16(IncDec_16), .Read_To_Reg(Read_To_Reg), .Read_To_Acc(Read_To_Acc),
    .Set_BusA_To(Set_BusA_To), .Set_BusB_To(Set_BusB_To), .ALU_Op(ALU_Op), .Save_ALU(Save_ALU),
    .PreserveC(PreserveC), .Arith16(Arith16), .Set_Addr_To(Set_Addr_To), .IORQ(IORQ_i), .Jump(Jump),
    .JumpE(JumpE), .JumpXY(JumpXY), .Call(Call), .RstP(RstP), .LDZ(LDZ), .LDW(LDW), .LDSPHL(LDSPHL),
    .Special_LD(Special_LD), .ExchangeDH(ExchangeDH), .ExchangeRp(ExchangeRp), .ExchangeAF(ExchangeAF),
    .ExchangeRS(ExchangeRS), .ExchangeWH(ExchangeWH), .I_DJNZ(I_DJNZ), .I_CPL(I_CPL), .I_CCF(I_CCF),
    .I_SCF(I_SCF), .I_RETN(I_RETN), .I_BT(I_BT), .I_BC(I_BC), .I_BTR(I_BTR), .I_RLD(I_RLD), .I_RRD(I_RRD),
    .I_INRC(I_INRC), .SetWZ(SetWZ), .SetDI(SetDI), .SetEI(SetEI), .IMode(IMode), .Halt(Halt),
    .NoRead(NoRead), .Write(Write), .No_PC(No_PC), .XYbit_undoc(XYbit_undoc)
);

t80sv_alu #(.Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X), .Flag_H(Flag_H), .Flag_Y(Flag_Y),
            .Flag_Z(Flag_Z), .Flag_S(Flag_S)) alu (
    .mode(mode), .Arith16(Arith16_r), .Z16(Z16_r), .WZ13(WZ[13]), .WZ11(WZ[11]), .XY_State(XY_State),
    .ALU_Op(ALU_Op_r), .Rot_Akku(Rot_Akku), .IR(IR[5:0]), .ISet(ISet), .BusA(BusA), .BusB(BusB), .F_In(F), .Q(ALU_Q), .F_Out(F_Out)
);

// asynchronous reset as posedge of the inverted input: also takes effect when RESET_n is low from time 0
logic rst;
assign rst = ~RESET_n;

assign ClkEn = CEN & ~BusAck;

assign T_Res = (TState == TStates);

assign NextIs_XY_Fetch = XY_State != 2'b00 && !XY_Ind &&
                         (Set_Addr_To == aXY || (MCycle == 3'b001 && IR == 8'hCB) || (MCycle == 3'b001 && IR == 8'h36));

assign Save_Mux = ExchangeRp ? BusB : (!Save_ALU_r ? DI_Reg : ALU_Q);

// process-variable equivalents; only some bits of each are used
/* verilator lint_off UNUSED */
logic [15:0] DI_sext;
logic [8:0]  ioq_sum, ioq_par;
logic [7:0]  bc_n;
assign DI_sext = {{8{DI_Reg[7]}}, DI_Reg};
assign ioq_sum = {1'b0, DI_Reg} + {1'b0, ID16[7:0]};             // INI / OUTI etc. flag source
assign ioq_par = (ioq_sum & 9'b000000111) ^ {1'b0, BusA};
assign bc_n    = ALU_Q - {7'd0, F_Out[Flag_H]};
logic [8:0]  temp_c;
logic [4:0]  temp_h;
assign temp_c  = {1'b0, SP[7:0]} + {1'b0, Save_Mux};             // LD HL,SP+e / ADD SP,e (GB) flags
assign temp_h  = {1'b0, SP[3:0]} + {1'b0, Save_Mux[3:0]};
/* verilator lint_on UNUSED */

always_ff @(posedge CLK_n or posedge rst) begin
    if (rst) begin
        PC <= 16'h0000;
        A <= 16'h0000;
        WZ <= 16'h0000;
        IR <= 8'h00;
        ISet <= 2'b00;
        XY_State <= 2'b00;
        IStatus <= 2'b00;
        MCycles <= 3'b000;
        DO <= 8'h00;
        ACC <= (MODE == 3) ? 8'h00 : 8'hFF;
        F <= (MODE == 3) ? 8'hF0 : 8'hFF;
        Ap <= 8'hFF;
        Fp <= 8'hFF;
        I <= 8'h00;
        R <= 8'h00;
        SP <= 16'hFFFF;
        Alternate <= 1'b0;
        Read_To_Reg_r <= 5'b00000;
        Arith16_r <= 1'b0;
        BTR_r <= 1'b0;
        Z16_r <= 1'b0;
        ALU_Op_r <= 4'b0000;
        Save_ALU_r <= 1'b0;
        PreserveC_r <= 1'b0;
        XY_Ind <= 1'b0;
        I_RXDD <= 1'b0;
        SOD_r <= 1'b0;
    end else if (DIRSet) begin
        ACC <= DIR[7:0];
        F <= DIR[15:8];
        Ap <= DIR[23:16];
        Fp <= DIR[31:24];
        I <= DIR[39:32];
        R <= DIR[47:40];
        SP <= DIR[63:48];
        PC <= DIR[79:64];
        A <= DIR[79:64];
        IStatus <= DIR[209:208];
    end else if (ClkEn) begin
        ALU_Op_r <= 4'b0000;
        Save_ALU_r <= 1'b0;
        Read_To_Reg_r <= 5'b00000;

        MCycles <= MCycles_d;

        if (LDHLSP && MCycle == 3'b011 && TState == 3'd1) begin
            F[Flag_Z] <= 1'b0;
            F[Flag_N] <= 1'b0;
            F[Flag_H] <= temp_h[4];
            F[Flag_C] <= temp_c[8];
        end

        if (ADDSPdd && TState == 3'd1) begin
            F[Flag_Z] <= 1'b0;
            F[Flag_N] <= 1'b0;
            F[Flag_H] <= temp_h[4];
            F[Flag_C] <= temp_c[8];
        end

        if (mode == 2'd3)
            IStatus <= 2'b10;
        else if (IMode != 2'b11)
            IStatus <= IMode;

        Arith16_r <= Arith16;
        PreserveC_r <= PreserveC;
        Z16_r <= (ISet == 2'b10 && !ALU_Op[2] && ALU_Op[0] && MCycle == 3'b011);

        if (MCycle == 3'b001 && !TState[2]) begin
            // MCycle 1, TState 1..3
            if (TState == 3'd2 && WAIT_n) begin
                if (mode < 2) begin
                    A[7:0] <= R;
                    A[15:8] <= I;
                    R[6:0] <= R[6:0] + 7'd1;
                end

                if (!Jump && !Call && !NMICycle && !IntCycle && !(Halt_FF || Halt))
                    PC <= PC + 16'd1;

                if (IntCycle && IStatus == 2'b01)
                    IR <= 8'hFF;
                else if (Halt_FF || (IntCycle && IStatus == 2'b10) || NMICycle)
                    IR <= 8'h00;
                else
                    IR <= DInst;

                if (mode <= 1 && IntCycle && IStatus == 2'b10)
                    WZ[7:0] <= DInst;          // IM 2 vector low byte

                ISet <= 2'b00;
                if (Prefix != 2'b00) begin
                    if (Prefix == 2'b11) begin
                        if (IR[5])
                            XY_State <= 2'b10;
                        else
                            XY_State <= 2'b01;
                    end else begin
                        if (Prefix == 2'b10) begin
                            XY_State <= 2'b00;
                            XY_Ind <= 1'b0;
                        end
                        ISet <= Prefix;
                    end
                end else begin
                    XY_State <= 2'b00;
                    XY_Ind <= 1'b0;
                end
            end
        end else begin
            // MCycle > 1, or MCycle 1 TState > 3
            if (MCycle == 3'b110) begin
                XY_Ind <= 1'b1;
                if (Prefix == 2'b01)
                    ISet <= 2'b01;
            end

            if (T_Res) begin
                BTR_r <= (I_BT | I_BC | I_BTR) & ~No_BTR;
                if (Jump) begin
                    A[15:8] <= DI_Reg;
                    A[7:0] <= WZ[7:0];
                    PC[15:8] <= DI_Reg;
                    PC[7:0] <= WZ[7:0];
                end else if (JumpXY) begin
                    A <= RegBusC;
                    PC <= RegBusC;
                end else if (Call || RstP) begin
                    A <= WZ;
                    PC <= WZ;
                end else if (MCycle == MCycles && NMICycle) begin
                    A <= 16'h0066;
                    PC <= 16'h0066;
                end else if (((mode != 2'd3 && MCycle == 3'b011) || (mode == 2'd3 && MCycle == 3'b100)) && IntCycle && IStatus == 2'b10) begin
                    A[15:8] <= I;
                    A[7:0] <= WZ[7:0];
                    PC[15:8] <= I;
                    PC[7:0] <= WZ[7:0];
                end else begin
                    case (Set_Addr_To)
                    aXY: begin
                        if (XY_State == 2'b00)
                            A <= RegBusC;
                        else if (NextIs_XY_Fetch)
                            A <= PC;
                        else
                            A <= WZ;
                    end
                    aIOA: begin
                        if (mode == 2'd3)
                            A[15:8] <= 8'hFF;      // GB: memory-mapped I/O
                        else if (mode == 2'd2)
                            A[15:8] <= DI_Reg;     // 8080 duplicates the port number
                        else
                            A[15:8] <= ACC;
                        A[7:0] <= DI_Reg;
                        WZ <= {ACC, DI_Reg} + 16'd1;
                    end
                    aSP: A <= SP;
                    aBC: begin
                        if (mode == 2'd3 && IORQ_i) begin
                            A[15:8] <= 8'hFF;      // GB: memory-mapped I/O
                            A[7:0] <= RegBusC[7:0];
                        end else begin
                            A <= RegBusC;
                            if (SetWZ == 2'b01)
                                WZ <= RegBusC + 16'd1;
                            if (SetWZ == 2'b10) begin
                                WZ[7:0] <= RegBusC[7:0] + 8'd1;
                                WZ[15:8] <= ACC;
                            end
                        end
                    end
                    aDE: begin
                        A <= RegBusC;
                        if (SetWZ == 2'b10) begin
                            WZ[7:0] <= RegBusC[7:0] + 8'd1;
                            WZ[15:8] <= ACC;
                        end
                    end
                    aZI: begin
                        if (Inc_WZ)
                            A <= WZ + 16'd1;
                        else begin
                            A[15:8] <= DI_Reg;
                            A[7:0] <= WZ[7:0];
                            if (SetWZ == 2'b10) begin
                                WZ[7:0] <= WZ[7:0] + 8'd1;
                                WZ[15:8] <= ACC;
                            end
                        end
                    end
                    default: begin
                        if (ISet == 2'b10 && IR[7:4] == 4'hB && IR[2:1] == 2'b01 && MCycle == 3'b011 && !No_BTR)
                            A <= RegBusA_r;    // INIR, INDR, OTIR, OTDR
                        else if (!No_PC || No_BTR || (I_DJNZ && IncDecZ) || mode > 1)
                            A <= PC;
                    end
                    endcase
                end

                if (SetWZ == 2'b11)
                    WZ <= ID16;

                Save_ALU_r <= Save_ALU;
                ALU_Op_r <= ALU_Op;

                if (mode == 2'd3) begin
                    if (I_CPL) begin
                        ACC <= ~ACC;
                        F[Flag_H] <= 1'b1;
                        F[Flag_N] <= 1'b1;
                    end
                    if (I_CCF) begin
                        F[Flag_C] <= ~F[Flag_C];
                        F[Flag_H] <= 1'b0;
                        F[Flag_N] <= 1'b0;
                    end
                    if (I_SCF) begin
                        F[Flag_C] <= 1'b1;
                        F[Flag_H] <= 1'b0;
                        F[Flag_N] <= 1'b0;
                    end
                end else begin
                    if (I_CPL) begin
                        ACC <= ~ACC;
                        F[Flag_Y] <= ~ACC[5];
                        F[Flag_H] <= 1'b1;
                        F[Flag_X] <= ~ACC[3];
                        F[Flag_N] <= 1'b1;
                    end
                    if (I_CCF) begin
                        F[Flag_C] <= ~F[Flag_C];
                        F[Flag_Y] <= ACC[5];
                        F[Flag_H] <= F[Flag_C];
                        F[Flag_X] <= ACC[3];
                        F[Flag_N] <= 1'b0;
                    end
                    if (I_SCF) begin
                        F[Flag_C] <= 1'b1;
                        F[Flag_Y] <= ACC[5];
                        F[Flag_H] <= 1'b0;
                        F[Flag_X] <= ACC[3];
                        F[Flag_N] <= 1'b0;
                    end
                end
            end

            if ((TState == 3'd2 && I_BTR && IR[0]) || (TState == 3'd1 && I_BTR && !IR[0])) begin
                F[Flag_N] <= DI_Reg[7];
                F[Flag_C] <= ioq_sum[8];
                F[Flag_H] <= ioq_sum[8];
                F[Flag_P] <= ~^ioq_par[7:0];
            end

            if (TState == 3'd2 && WAIT_n) begin
                if (ISet == 2'b01 && MCycle == 3'b111)
                    IR <= DInst;
                if (JumpE) begin
                    PC <= PC + DI_sext;
                    WZ <= PC + DI_sext;
                end else if (Inc_PC) begin
                    PC <= PC + 16'd1;
                end
                if (BTR_r)
                    PC <= PC - 16'd2;
                if (RstP) begin
                    WZ <= 16'h0000;
                    WZ[5:3] <= IR[5:3];
                end
            end
            if (TState == 3'd3 && MCycle == 3'b110)
                WZ <= RegBusC + DI_sext;

            if (MCycle == 3'b011 && TState == 3'd4 && !No_BTR) begin
                if (I_BT || I_BC)
                    WZ <= PC - 16'd1;
            end

            if ((TState == 3'd2 && WAIT_n) || (TState == 3'd4 && MCycle == 3'b001)) begin
                if (IncDec_16[2:0] == 3'b111) begin
                    if (IncDec_16[3])
                        SP <= SP - 16'd1;
                    else
                        SP <= SP + 16'd1;
                end
            end

            if (ADDSPdd && TState == 3'd2) begin
                WZ <= SP;
                SP <= SP + {{8{Save_Mux[7]}}, Save_Mux};
            end

            if (LDSPHL)
                SP <= RegBusC;
            if (ExchangeAF) begin
                Ap <= ACC;
                ACC <= Ap;
                Fp <= F;
                F <= Fp;
            end
            if (ExchangeRS)
                Alternate <= ~Alternate;
        end

        if (TState == 3'd3) begin
            if (LDZ)
                WZ[7:0] <= DI_Reg;
            if (LDW)
                WZ[15:8] <= DI_Reg;

            if (Special_LD[2]) begin
                case (Special_LD[1:0])
                2'b00: begin
                    ACC <= I;
                    F[Flag_P] <= IntE_FF2;
                    F[Flag_S] <= I[7];
                    F[Flag_Z] <= (I == 8'h00);
                    F[Flag_Y] <= I[5];
                    F[Flag_H] <= 1'b0;
                    F[Flag_X] <= I[3];
                    F[Flag_N] <= 1'b0;
                end
                2'b01: begin
                    ACC <= R;
                    F[Flag_P] <= IntE_FF2;
                    F[Flag_S] <= R[7];
                    F[Flag_Z] <= (R == 8'h00);
                    F[Flag_Y] <= R[5];
                    F[Flag_H] <= 1'b0;
                    F[Flag_X] <= R[3];
                    F[Flag_N] <= 1'b0;
                end
                2'b10: I <= ACC;
                default: R <= ACC;
                endcase
            end
        end

        if ((!I_DJNZ && Save_ALU_r) || ALU_Op_r == 4'b1001) begin
            if (mode == 2'd3) begin
                F[6] <= F_Out[6];
                F[5] <= F_Out[5];
                F[7] <= F_Out[7];
                if (!PreserveC_r)
                    F[4] <= F_Out[4];
            end else begin
                F[7:1] <= F_Out[7:1];
                if (!PreserveC_r)
                    F[Flag_C] <= F_Out[0];
            end
        end
        if (T_Res && I_INRC) begin
            F[Flag_H] <= 1'b0;
            F[Flag_N] <= 1'b0;
            F[Flag_X] <= DI_Reg[3];
            F[Flag_Y] <= DI_Reg[5];
            F[Flag_Z] <= (DI_Reg == 8'h00);
            F[Flag_S] <= DI_Reg[7];
            F[Flag_P] <= ~^DI_Reg;
        end

        if (TState == 3'd1 && !Auto_Wait_t1) begin
            I_RXDD <= I_RLD | I_RRD;   // keep DO from M3 for RLD / RRD
            if (!I_RXDD)
                DO <= BusB;
            if (I_RLD) begin
                DO[3:0] <= BusA[3:0];
                DO[7:4] <= BusB[3:0];
            end
            if (I_RRD) begin
                DO[3:0] <= BusB[7:4];
                DO[7:4] <= BusA[3:0];
            end
        end

        if (T_Res) begin
            Read_To_Reg_r[3:0] <= Set_BusA_To;
            Read_To_Reg_r[4] <= Read_To_Reg;
            if (Read_To_Acc) begin
                Read_To_Reg_r[3:0] <= 4'b0111;
                Read_To_Reg_r[4] <= 1'b1;
            end
        end

        if (TState == 3'd1 && I_BT) begin
            F[Flag_X] <= ALU_Q[3];
            F[Flag_Y] <= ALU_Q[1];
            F[Flag_H] <= 1'b0;
            F[Flag_N] <= 1'b0;
        end
        if (TState == 3'd1 && I_BC) begin
            F[Flag_X] <= bc_n[3];
            F[Flag_Y] <= bc_n[1];
        end
        if (I_BC || I_BT)
            F[Flag_P] <= IncDecZ;

        if ((TState == 3'd1 && !Save_ALU_r && !Auto_Wait_t1) || (Save_ALU_r && ALU_Op_r != 4'b0111)) begin
            case (Read_To_Reg_r)
            5'b10111: ACC <= Save_Mux;
            5'b10110: DO <= Save_Mux;
            5'b11000: SP[7:0] <= Save_Mux;
            5'b11001: SP[15:8] <= Save_Mux;
            5'b11011: begin
                if (mode == 2'd3) begin
                    F[7:4] <= Save_Mux[7:4];
                    F[3:0] <= 4'b0000;     // GB: F bits 3..0 always read 0
                end else begin
                    F <= Save_Mux;
                end
            end
            default: ;
            endcase
            if (XYbit_undoc)
                DO <= ALU_Q;
        end

        // 8085 RIM: opcode 20 loads A last in M1 (after any write-back of the previous instruction)
        if (I8085 && mode == 2'd2 && MCycle == 3'b001 && TState == 3'd4 && ISet == 2'b00 && IR == 8'h20)
            ACC <= RIM_D;
        // 8085 SIM: opcode 30, A[6] (SOE) latches A[7] into SOD; the interrupt-mask half is not modelled
        if (I8085 && mode == 2'd2 && MCycle == 3'b001 && TState == 3'd4 && ISet == 2'b00 && IR == 8'h30 && ACC[6])
            SOD_r <= ACC[7];
    end
end

//----------------------------------------------------------------------------
// R800 multiply (MULUB / MULUW)
//----------------------------------------------------------------------------
logic [19:0] MULU_hi;
assign MULU_hi  = (MULU_Fakt1 * MULU_Prod32[3:0]) + {4'd0, MULU_Prod32[31:16]};
assign MULU_tmp = {MULU_hi, MULU_Prod32[15:4]};

always_ff @(posedge CLK_n) begin
    if (ClkEn) begin
        if (T_Res) begin
            if (I_MULUB) begin
                MULU_Prod32[7:0] <= ACC;
                MULU_Prod32[15:8] <= 8'h00;     // VHDL "--------"
                MULU_Prod32[31:16] <= 16'h0000;
                MULU_Fakt1[7:0] <= 8'h00;
                if (Set_BusB_To[0])
                    MULU_Fakt1[15:8] <= RegBusB[7:0];
                else
                    MULU_Fakt1[15:8] <= RegBusB[15:8];
            end else begin
                MULU_Prod32[15:0] <= RegBusA;
                MULU_Prod32[31:16] <= 16'h0000;
                MULU_Fakt1 <= RegBusB;
            end
        end else begin
            MULU_Prod32 <= MULU_tmp;
        end
    end
end

//----------------------------------------------------------------------------
// BC('), DE('), HL('), IX and IY
//----------------------------------------------------------------------------
always_ff @(posedge CLK_n) begin
    if (ClkEn) begin
        // Bus A / write
        RegAddrA_r <= {Alternate, Set_BusA_To[2:1]};
        if (!XY_Ind && XY_State != 2'b00 && Set_BusA_To[2:1] == 2'b10)
            RegAddrA_r <= {XY_State[1], 2'b11};

        // Bus B
        RegAddrB_r <= {Alternate, Set_BusB_To[2:1]};
        if (!XY_Ind && XY_State != 2'b00 && Set_BusB_To[2:1] == 2'b10)
            RegAddrB_r <= {XY_State[1], 2'b11};

        // Address from register
        RegAddrC <= {Alternate, Set_Addr_To[1:0]};
        // JP (HL), LD SP,HL
        if (JumpXY || LDSPHL)
            RegAddrC <= {Alternate, 2'b10};
        if (((JumpXY || LDSPHL) && XY_State != 2'b00) || MCycle == 3'b110)
            RegAddrC <= {XY_State[1], 2'b11};

        if (I_DJNZ && Save_ALU_r && mode < 2)
            IncDecZ <= F_Out[Flag_Z];
        if ((TState == 3'd2 || (TState == 3'd3 && MCycle == 3'b001)) && IncDec_16[2:0] == 3'b100)
            IncDecZ <= (ID16 != 16'h0000);

        RegBusA_r <= RegBusA;
    end
end

always_comb begin
    if ((TState == 3'd2 || (TState == 3'd3 && MCycle == 3'b001 && IncDec_16[2])) && XY_State == 2'b00)
        RegAddrA = {Alternate, IncDec_16[1:0]};            // 16-bit increment / decrement
    else if ((TState == 3'd2 || (TState == 3'd3 && MCycle == 3'b001 && IncDec_16[2])) && IncDec_16[1:0] == 2'b10)
        RegAddrA = {XY_State[1], 2'b11};
    else if (ExchangeDH && TState == 3'd3)
        RegAddrA = {Alternate, 2'b10};                     // EX DE,HL
    else if ((ExchangeDH || I_MULU) && TState == 3'd4)
        RegAddrA = {Alternate, 2'b01};
    else if (ExchangeWH && XY_State == 2'b00 && TState == 3'd4)
        RegAddrA = {Alternate, 2'b10};                     // EX (SP),HL: HL (IX, IY) <= WZ
    else if (ExchangeWH && TState == 3'd4)
        RegAddrA = {XY_State[1], 2'b11};
    else if (LDHLSP && TState == 3'd4)
        RegAddrA = 3'b010;
    else
        RegAddrA = RegAddrA_r;
end

assign RegAddrB = (ExchangeDH && TState == 3'd3) ? {Alternate, 2'b01} : RegAddrB_r;

assign ID16 = IncDec_16[3] ? RegBusA - 16'd1 : RegBusA + 16'd1;

always_comb begin
    RegWEH = 1'b0;
    RegWEL = 1'b0;
    if ((TState == 3'd1 && !Save_ALU_r && !Auto_Wait_t1) || (Save_ALU_r && ALU_Op_r != 4'b0111)) begin
        case (Read_To_Reg_r)
        5'b10000, 5'b10001, 5'b10010, 5'b10011, 5'b10100, 5'b10101: begin
            RegWEH = ~Read_To_Reg_r[0];
            RegWEL = Read_To_Reg_r[0];
        end
        default: ;
        endcase
    end
    if (I_MULU && (T_Res || TState == 3'd4)) begin       // TState 4: DE write
        RegWEH = 1'b1;
        RegWEL = 1'b1;
    end
    if (ExchangeDH && (TState == 3'd3 || TState == 3'd4)) begin
        RegWEH = 1'b1;
        RegWEL = 1'b1;
    end
    if (((LDHLSP && MCycle == 3'b010) || ExchangeWH) && TState == 3'd4) begin
        RegWEH = 1'b1;
        RegWEL = 1'b1;
    end
    if (IncDec_16[2] && ((TState == 3'd2 && WAIT_n && MCycle != 3'b001) || (TState == 3'd3 && MCycle == 3'b001))) begin
        case (IncDec_16[1:0])
        2'b00, 2'b01, 2'b10: begin
            RegWEH = 1'b1;
            RegWEL = 1'b1;
        end
        default: ;
        endcase
    end
end

always_comb begin
    RegDIH = Save_Mux;
    RegDIL = Save_Mux;
    if (I_MULU) begin
        if (T_Res) begin
            RegDIH = MULU_Prod32[31:24];
            RegDIL = MULU_Prod32[23:16];
        end else begin
            RegDIH = MULU_tmp[15:8];               // TState 4: DE write
            RegDIL = MULU_tmp[7:0];
        end
    end
    if (LDHLSP && MCycle == 3'b010 && TState == 3'd4) begin
        RegDIH = TmpAddr2[15:8];
        RegDIL = TmpAddr2[7:0];
    end
    if (ExchangeDH && TState == 3'd3) begin
        RegDIH = RegBusB[15:8];
        RegDIL = RegBusB[7:0];
    end
    if (ExchangeDH && TState == 3'd4) begin
        RegDIH = RegBusA_r[15:8];
        RegDIL = RegBusA_r[7:0];
    end
    if (ExchangeWH && TState == 3'd4) begin
        RegDIH = WZ[15:8];
        RegDIL = WZ[7:0];
    end
    if (IncDec_16[2] && ((TState == 3'd2 && MCycle != 3'b001) || (TState == 3'd3 && MCycle == 3'b001))) begin
        RegDIH = ID16[15:8];
        RegDIL = ID16[7:0];
    end
end

assign TmpAddr2 = SP + {{8{Save_Mux[7]}}, Save_Mux};

// register file (T80_Reg): 8 x 16 bits, write port A, asynchronous read ports A, B, C
logic [7:0] RegsH [0:7];
logic [7:0] RegsL [0:7];

always_ff @(posedge CLK_n) begin
    if (DIRSet) begin
        RegsL[0] <= DIR[87:80];   RegsH[0] <= DIR[95:88];
        RegsL[1] <= DIR[103:96];  RegsH[1] <= DIR[111:104];
        RegsL[2] <= DIR[119:112]; RegsH[2] <= DIR[127:120];
        RegsL[3] <= DIR[135:128]; RegsH[3] <= DIR[143:136];
        RegsL[4] <= DIR[151:144]; RegsH[4] <= DIR[159:152];
        RegsL[5] <= DIR[167:160]; RegsH[5] <= DIR[175:168];
        RegsL[6] <= DIR[183:176]; RegsH[6] <= DIR[191:184];
        RegsL[7] <= DIR[199:192]; RegsH[7] <= DIR[207:200];
    end else if (ClkEn) begin
        if (RegWEH)
            RegsH[RegAddrA] <= RegDIH;
        if (RegWEL)
            RegsL[RegAddrA] <= RegDIL;
    end
end

assign RegBusA = {RegsH[RegAddrA], RegsL[RegAddrA]};
assign RegBusB = {RegsH[RegAddrB], RegsL[RegAddrB]};
assign RegBusC = {RegsH[RegAddrC], RegsL[RegAddrC]};
assign DOR = {RegsH[7], RegsL[7], RegsH[6], RegsL[6], RegsH[5], RegsL[5], RegsH[4], RegsL[4],
              RegsH[3], RegsL[3], RegsH[2], RegsL[2], RegsH[1], RegsL[1], RegsH[0], RegsL[0]};

//----------------------------------------------------------------------------
// Buses
//----------------------------------------------------------------------------
always_ff @(posedge CLK_n) begin
    if (ClkEn) begin
        case (Set_BusB_To)
        4'b0111: BusB <= ACC;
        4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101: BusB <= Set_BusB_To[0] ? RegBusB[7:0] : RegBusB[15:8];
        4'b0110: BusB <= DI_Reg;
        4'b1000: BusB <= SP[7:0];
        4'b1001: BusB <= SP[15:8];
        4'b1010: BusB <= 8'h01;
        4'b1011: BusB <= F;
        4'b1100: BusB <= PC[7:0];
        4'b1101: BusB <= PC[15:8];
        4'b1110: BusB <= (IR == 8'h71 && out0) ? 8'hFF : 8'h00;
        default: BusB <= 8'h00;        // VHDL "--------"
        endcase

        case (Set_BusA_To)
        4'b0111: BusA <= ACC;
        4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101: BusA <= Set_BusA_To[0] ? RegBusA[7:0] : RegBusA[15:8];
        4'b0110: BusA <= DI_Reg;
        4'b1000: BusA <= SP[7:0];
        4'b1001: BusA <= SP[15:8];
        4'b1010: BusA <= 8'h00;
        default: BusA <= 8'h00;        // VHDL "--------"
        endcase
        if (XYbit_undoc) begin
            BusA <= DI_Reg;
            BusB <= DI_Reg;
        end
    end
end

//----------------------------------------------------------------------------
// External control signals
//----------------------------------------------------------------------------
always_ff @(posedge CLK_n or posedge rst) begin
    if (rst)
        RFSH_n <= 1'b1;
    else if (!DIRSet && CEN)
        RFSH_n <= ~(MCycle == 3'b001 && ((TState == 3'd2 && WAIT_n) || TState == 3'd3));
end

assign MC         = MCycle;
assign TS         = TState;
assign DI_Reg     = DI;
assign HALT_n     = ~Halt_FF;
assign BUSAK_n    = ~(BusAck & RESET_n);
assign IntCycle_n = ~IntCycle;
assign IntE       = IntE_FF1;
assign IORQ       = IORQ_i;
assign Stop       = I_DJNZ;
assign SOD        = SOD_r;

//----------------------------------------------------------------------------
// Main state machine
//----------------------------------------------------------------------------
// OldNMI_n and BusReq_s / BusAck are not reset in T80 (BusReq_s / BusAck power up 0)
always_ff @(posedge CLK_n) begin
    if (RESET_n && !DIRSet)
        OldNMI_n <= NMI_n;
end

always_ff @(posedge CLK_n or posedge rst) begin
    if (rst) begin
        MCycle <= 3'b001;
        TState <= 3'd0;
        Pre_XY_F_M <= 3'b000;
        Halt_FF <= 1'b0;
        NMICycle <= 1'b0;
        IntCycle <= 1'b0;
        IntE_FF1 <= 1'b0;
        IntE_FF2 <= 1'b0;
        No_BTR <= 1'b0;
        Auto_Wait_t1 <= 1'b0;
        Auto_Wait_t2 <= 1'b0;
        M1_n <= 1'b1;
        NMI_s <= 1'b0;
    end else if (DIRSet) begin
        IntE_FF2 <= DIR[211];
        IntE_FF1 <= DIR[210];
    end else begin
        if (!NMI_n && OldNMI_n)
            NMI_s <= 1'b1;

        if (CEN) begin
            Auto_Wait_t2 <= Auto_Wait_t1;
            if (T_Res) begin
                Auto_Wait_t1 <= 1'b0;
                Auto_Wait_t2 <= 1'b0;
            end else begin
                Auto_Wait_t1 <= Auto_Wait | IORQ_i;
            end
            No_BTR <= (I_BT & (~IR[4] | ~F[Flag_P])) |
                      (I_BC & (~IR[4] | F[Flag_Z] | ~F[Flag_P])) |
                      (I_BTR & (~IR[4] | F[Flag_Z]));
            if (TState == 3'd2) begin
                if (SetEI) begin
                    IntE_FF1 <= 1'b1;
                    IntE_FF2 <= 1'b1;
                end
                if (I_RETN)
                    IntE_FF1 <= IntE_FF2;
            end
            if (TState == 3'd3) begin
                if (SetDI) begin
                    IntE_FF1 <= 1'b0;
                    IntE_FF2 <= 1'b0;
                end
            end
            if (IntCycle || NMICycle)
                Halt_FF <= 1'b0;
            if (MCycle == 3'b001 && TState == 3'd2 && WAIT_n)
                M1_n <= 1'b1;
            if (!(BusReq_s && BusAck)) begin
                if (TState == 3'd2 && !WAIT_n) begin
                end else if (T_Res) begin
                    if (Halt && !(mode == 2'd3 && !INT_n && !IntE_FF1))  // GB halt bug: INT_n low with IME 0
                        Halt_FF <= 1'b1;
                    if (!BusReq_s) begin
                        TState <= 3'd1;
                        if (IntCycle && mode == 2'd3) begin              // GB: interrupt read in MCycle 3
                            if (MCycle == 3'b010)
                                M1_n <= 1'b0;
                            else
                                M1_n <= 1'b1;
                        end
                        if (NextIs_XY_Fetch) begin
                            MCycle <= 3'b110;
                            Pre_XY_F_M <= MCycle;
                            if (IR == 8'h36 && mode == 2'd0)
                                Pre_XY_F_M <= 3'b010;
                        end else if (MCycle == 3'b111 || (MCycle == 3'b110 && mode == 2'd1 && ISet != 2'b01)) begin
                            MCycle <= Pre_XY_F_M + 3'd1;
                        end else if (MCycle == MCycles || No_BTR || (MCycle == 3'b010 && I_DJNZ && IncDecZ)) begin
                            M1_n <= 1'b0;
                            MCycle <= 3'b001;
                            IntCycle <= 1'b0;
                            NMICycle <= 1'b0;
                            if (NMI_s && Prefix == 2'b00) begin
                                NMI_s <= 1'b0;
                                NMICycle <= 1'b1;
                                IntE_FF1 <= 1'b0;
                            end else if (IntE_FF1 && !INT_n && Prefix == 2'b00 && !SetEI) begin
                                IntCycle <= 1'b1;
                                IntE_FF1 <= 1'b0;
                                IntE_FF2 <= 1'b0;
                            end else if (Halt_FF && !INT_n && mode == 2'd3) begin
                                Halt_FF <= 1'b0;
                            end
                        end else begin
                            MCycle <= MCycle + 3'd1;
                        end
                    end
                end else begin
                    if (!((Auto_Wait && !Auto_Wait_t2) || (IOWAIT == 1 && IORQ_i && !Auto_Wait_t1)))
                        TState <= TState + 3'd1;
                end
            end
            if (TState == 3'd0)
                M1_n <= 1'b0;
        end
    end
end

// BusReq_s / BusAck: same clocking as the state machine above, without its reset
always_ff @(posedge CLK_n) begin
    if (RESET_n && !DIRSet && CEN) begin
        BusReq_s <= ~BUSRQ_n;
        if (!(BusReq_s && BusAck)) begin
            BusAck <= 1'b0;
            if (!(TState == 3'd2 && !WAIT_n) && T_Res && BusReq_s)
                BusAck <= 1'b1;
        end
    end
end

assign Auto_Wait = IntCycle && MCycle == 3'b001;

endmodule

// ===== t80sv.sv =====
//============================================================================
//  t80sv - Z80 / 8080 / 8085-subset / GB-Z80 CPU with the T80 bus front ends, cycle-identical to T80
//
//  One module for every T80 top; BUS selects the front end:
//    BUS_S      T80s / T80se   single CEN; T2WRITE: WR_n in T2 (1) or T3 (0)
//    BUS_SED    T80sed         single CEN; MREQ / RD / WR held through T2
//    BUS_PA     T80pa          CEN_p / CEN_n phases; WAIT_n sampled by the front end
//    BUS_8080SE T8080se        8080 pins: DBIN, SYNC, VAIT, HLDA, status word on DO in T1
//    BUS_GB     GBse           single CEN; GB-Z80 (set MODE 3 and the GB flag positions)
//    BUS_A      T80a           both clock edges, no enable; tri-state bus (see t80sv_t80a for the pins)
//    BUS_AS     T80as          both clock edges, no enable; separate DI / DO / DOE
//  The superset port list is meant to become one fleet bus type; inputs a front end does not use are ignored.
//
//  SystemVerilog translation of T80s / T80se / T80sed / T80pa / T8080se / GBse / T80a / T80as.vhd.
//  T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018
//  Sorgelig and contributors (MiSTer-devel lineage); T80a bus timing by Fabio Belavenuto and Charlie Ingley.
//  Phoenix core additions (I8080 / I8085 / RIM_D / SOD) by Rodimus.
//  Copyright (C) 2026 Rodimus  (SystemVerilog translation; Phoenix 8080 / 8085 additions)
//  Based on T80 (VHDL):
//    Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
//    T80 versions by MikeJ (2005), TobiFlex, Sean Riddle; Copyright (c) 2018 Sorgelig (MiSTer-devel);
//    T80a bus timing by Fabio Belavenuto and Charlie Ingley; T80pa top level by Sorgelig.
//  Redistribution and use in source and synthezised forms, with or without modification, are permitted provided
//  that the following conditions are met: Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer. Redistributions in synthesized form must reproduce the
//  above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
//  materials provided with the distribution. Neither the name of the author nor the names of other contributors
//  may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
//  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//============================================================================

module t80sv #(
    parameter int MODE    = 0,         // 0 Z80, 1 fast Z80, 2 8080, 3 GB
    parameter int T2WRITE = 1,         // BUS_S / BUS_8080SE / BUS_GB: 0 WR_n active in T3, 1 in T2
    parameter int IOWAIT  = 1,         // BUS_S / BUS_8080SE / BUS_GB / BUS_A: 0 single-cycle I/O, 1 standard
    parameter int BUS     = 0,         // 0 S, 1 SED, 2 PA, 3 8080SE, 4 GB, 5 A, 6 AS
    parameter int Flag_C  = 0,         // flag bit positions; GB: C 4, H 5, N 6, Z 7, S / P / X / Y 0
    parameter int Flag_N  = 1,
    parameter int Flag_P  = 2,
    parameter int Flag_X  = 3,
    parameter int Flag_H  = 4,
    parameter int Flag_Y  = 5,
    parameter int Flag_Z  = 6,
    parameter int Flag_S  = 7
) (
    input  logic         clk,
    input  logic         reset_n,
    input  logic         cen,          // BUS_S / BUS_SED / BUS_8080SE / BUS_GB
    input  logic         cen_p,        // BUS_PA
    input  logic         cen_n,        // BUS_PA
    input  logic         wait_n,       // BUS_8080SE: READY
    input  logic         int_n,        // BUS_8080SE: ~INT
    input  logic         nmi_n,
    input  logic         busrq_n,      // BUS_8080SE: unused (T8080se ignores HOLD)
    input  logic [7:0]   di,           // BUS_A: the resolved data bus
    input  logic         out0,         // 0: OUT (C),0; 1: OUT (C),255
    input  logic         r800_mode,    // R800 MULUB / MULUW
    input  logic         dirset,       // load every register from dir
    input  logic [211:0] dir,          // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    input  logic         i8080,        // MODE 0: 8080 mode while high (Phoenix)
    input  logic         i8085,        // 8080 mode: RIM (opcode 20) / SIM (opcode 30)
    input  logic [7:0]   rim_d,
    output logic [15:0]  a,
    output logic [7:0]   dout,
    output logic         m1_n,
    output logic         mreq_n,
    output logic         iorq_n,
    output logic         rd_n,
    output logic         wr_n,
    output logic         rfsh_n,
    output logic         halt_n,
    output logic         busak_n,
    output logic         inte,         // IFF1 (8080 INTE)
    output logic         stop,         // GB STOP (T80 Stop = I_DJNZ)
    output logic [211:0] reg_o,        // register dump, layout as dir
    output logic         sod,
    output logic         doe,          // BUS_A / BUS_AS: CPU drives the data bus
    output logic         bus_oe,       // BUS_A: address / control drivers enabled (BUSAK_n high)
    output logic         dbin,         // BUS_8080SE
    output logic         sync,         // BUS_8080SE
    output logic         vait,         // BUS_8080SE
    output logic         hlda          // BUS_8080SE
);

localparam int BUS_SED    = 1;
localparam int BUS_PA     = 2;
localparam int BUS_8080SE = 3;
localparam int BUS_GB     = 4;
localparam int BUS_A      = 5;
localparam int BUS_AS     = 6;

// BUS_S = 0 is the default branch below
localparam int CORE_IOWAIT = (BUS == BUS_SED || BUS == BUS_PA || BUS == BUS_AS) ? 1 : IOWAIT;

logic        core_reset_n, core_cen, core_wait_n, core_busrq_n, core_nmi_n;
logic        IntCycle_n, NoRead, Write, IORQ, core_busak_n, core_m1_n, core_halt_n, core_rfsh_n;
logic [2:0]  MCycle, TState;
logic [7:0]  DI_Reg, core_do;
logic [15:0] core_a;
logic        rst;                      // asynchronous resets as posedge of the inverted input (see t80sv_core)
assign rst = ~reset_n;

t80sv_core #(.MODE(MODE), .IOWAIT(CORE_IOWAIT), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X),
             .Flag_H(Flag_H), .Flag_Y(Flag_Y), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) u0 (
    .RESET_n(core_reset_n), .CLK_n(clk), .CEN(core_cen), .WAIT_n(core_wait_n), .INT_n(int_n), .NMI_n(core_nmi_n),
    .BUSRQ_n(core_busrq_n), .M1_n(core_m1_n), .IORQ(IORQ), .NoRead(NoRead), .Write(Write), .RFSH_n(core_rfsh_n),
    .HALT_n(core_halt_n), .BUSAK_n(core_busak_n), .A(core_a), .DInst(di), .DI(DI_Reg), .DO(core_do), .MC(MCycle),
    .TS(TState), .IntCycle_n(IntCycle_n), .IntE(inte), .Stop(stop), .R800_mode(r800_mode), .out0(out0),
    .REG(reg_o), .DIRSet(dirset), .DIR(dir), .I8080(i8080), .I8085(i8085), .RIM_D(rim_d), .SOD(sod)
);

assign halt_n = core_halt_n;
assign a      = core_a;

generate
if (BUS == BUS_PA) begin : g_pa
    logic CEN_pol;
    logic [1:0] IntCycleD_n;           // no reset in T80pa
    wire unused_pa = &{1'b0, cen, rst};

    assign core_reset_n = reset_n;
    assign core_cen     = cen_p & ~CEN_pol;
    assign core_wait_n  = 1'b1;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n         = core_m1_n;
    assign rfsh_n       = core_rfsh_n;
    assign busak_n      = core_busak_n;
    assign dout         = core_do;
    assign doe    = 1'b0;
    assign bus_oe = 1'b1;
    assign dbin   = 1'b0;
    assign sync   = 1'b0;
    assign vait   = 1'b0;
    assign hlda   = 1'b0;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            wr_n    <= 1'b1;
            rd_n    <= 1'b1;
            iorq_n  <= 1'b1;
            mreq_n  <= 1'b1;
            DI_Reg  <= 8'h00;
            CEN_pol <= 1'b0;
        end else if (cen_p && !CEN_pol) begin
            CEN_pol <= 1'b1;
            if (MCycle == 3'b001) begin
                if (TState == 3'd2) begin
                    iorq_n <= 1'b1;
                    mreq_n <= 1'b1;
                    rd_n   <= 1'b1;
                end
            end else begin
                if (TState == 3'd1 && IORQ) begin
                    wr_n   <= ~Write;
                    rd_n   <= Write;
                    iorq_n <= 1'b0;
                end
            end
        end else if (cen_n && CEN_pol) begin
            if (TState == 3'd2)
                CEN_pol <= ~wait_n;
            else
                CEN_pol <= 1'b0;
            if (TState == 3'd3 && core_busak_n)
                DI_Reg <= di;
            if (MCycle == 3'b001) begin
                if (TState == 3'd1) begin
                    IntCycleD_n <= {IntCycleD_n[0], IntCycle_n};
                    rd_n   <= ~IntCycle_n;
                    mreq_n <= ~IntCycle_n;
                    iorq_n <= IntCycleD_n[1];
                end
                if (TState == 3'd3) begin
                    IntCycleD_n <= 2'b11;
                    rd_n   <= 1'b1;
                    mreq_n <= 1'b0;
                end
                if (TState == 3'd4)
                    mreq_n <= 1'b1;
            end else begin
                if (!NoRead && !IORQ) begin
                    if (TState == 3'd1) begin
                        rd_n   <= Write;
                        mreq_n <= 1'b0;
                    end
                end
                if (TState == 3'd2)
                    wr_n <= ~Write;
                if (TState == 3'd3) begin
                    wr_n   <= 1'b1;
                    rd_n   <= 1'b1;
                    iorq_n <= 1'b1;
                    mreq_n <= 1'b1;
                end
            end
        end
    end
end else if (BUS == BUS_8080SE) begin : g_8080se
    assign core_reset_n = reset_n;
    assign core_cen     = cen;
    assign core_wait_n  = wait_n;
    assign core_busrq_n = 1'b1;        // T8080se ignores HOLD
    assign core_nmi_n   = 1'b1;
    wire unused_8080se = &{1'b0, cen_p, cen_n, nmi_n, busrq_n, core_m1_n, core_rfsh_n};
    assign m1_n    = 1'b1;
    assign rfsh_n  = 1'b1;
    assign mreq_n  = 1'b1;
    assign iorq_n  = 1'b1;
    assign rd_n    = ~dbin;
    assign busak_n = core_busak_n;
    assign doe     = 1'b0;
    assign bus_oe  = 1'b1;
    assign sync    = (TState == 3'd1);
    assign vait    = (TState == 3'd2);
    assign hlda    = ~core_busak_n;

    // status word in T1
    always_comb begin
        dout = core_do;
        if (TState == 3'd1) begin
            dout[0] = ~IntCycle_n;                     // INTA
            dout[1] = Write;                           // WO_n
            dout[3] = ~core_halt_n;                    // HLTA
            dout[4] = IORQ & Write;                    // OUT
            dout[5] = (MCycle == 3'b001);              // M1
            dout[6] = IORQ & ~Write;                   // INP
            dout[7] = ~IORQ & ~Write & IntCycle_n;     // MEMR
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dbin   <= 1'b0;
            wr_n   <= 1'b1;
            DI_Reg <= 8'h00;
        end else if (cen) begin
            dbin <= 1'b0;
            wr_n <= 1'b1;
            if (MCycle == 3'b001) begin
                if (TState == 3'd1 || (TState == 3'd2 && !wait_n))
                    dbin <= IntCycle_n;
            end else begin
                if ((TState == 3'd1 || (TState == 3'd2 && !wait_n)) && !NoRead && !Write)
                    dbin <= 1'b1;
                if (T2WRITE == 0) begin
                    if (TState == 3'd2 && Write)
                        wr_n <= 1'b0;
                end else begin
                    if ((TState == 3'd1 || (TState == 3'd2 && !wait_n)) && Write)
                        wr_n <= 1'b0;
                end
            end
            if (TState == 3'd2 && wait_n)
                DI_Reg <= di;
        end
    end
end else if (BUS == BUS_A) begin : g_a
    logic Reset_s, Wait_s, WR_t2, Req_Inhibit, MReq_Inhibit, RD, MREQ, IORQ_int, IORQ_t1, IORQ_t2;
    logic rst_s;
    assign rst_s = ~Reset_s;
    logic [2:0] IORQ_int_inhibit;
    logic MREQ_rw, IORQ_rw;
    wire unused_a = &{1'b0, cen, cen_p, cen_n};

    assign core_reset_n = Reset_s;
    assign core_cen     = 1'b1;
    assign core_wait_n  = Wait_s;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n    = core_m1_n;
    assign rfsh_n  = core_rfsh_n;
    assign busak_n = core_busak_n;
    assign dout    = core_do;
    assign bus_oe  = core_busak_n;
    assign doe     = Write & core_busak_n;
    assign dbin = 1'b0;
    assign sync = 1'b0;
    assign vait = 1'b0;
    assign hlda = 1'b0;

    assign MREQ_rw = MREQ & (Req_Inhibit | MReq_Inhibit);
    assign IORQ_rw = IORQ & ~(IORQ_t1 | IORQ_t2);
    assign mreq_n  = ~MREQ_rw;
    assign iorq_n  = ~((IORQ_int & ~IORQ_int_inhibit[2]) | IORQ_rw);
    assign rd_n    = ~(RD & (MREQ_rw | IORQ_rw));
    assign wr_n    = ~(Write & ((WR_t2 & MREQ_rw) | IORQ_rw));

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            Reset_s <= 1'b0;
        else
            Reset_s <= 1'b1;
    end

    always_ff @(negedge clk) begin
        Wait_s <= wait_n;
        if (TState == 3'd3 && core_busak_n)
            DI_Reg <= di;
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            WR_t2 <= 1'b0;
        end else begin
            if (MCycle != 3'b001) begin
                if (TState == 3'd2)
                    WR_t2 <= Write;            // WR starts on the falling edge of T2 for MREQ
            end
            if (TState == 3'd3)
                WR_t2 <= 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst_s) begin
        if (rst_s)
            Req_Inhibit <= 1'b1;
        else
            Req_Inhibit <= ~(MCycle == 3'b001 && TState == 3'd2 && wait_n);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s)
            MReq_Inhibit <= 1'b1;
        else
            MReq_Inhibit <= ~(MCycle == 3'b001 && TState == 3'd2 && wait_n);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            RD   <= 1'b0;
            MREQ <= 1'b0;
        end else begin
            if (MCycle == 3'b001) begin
                if (TState == 3'd1) begin
                    RD   <= IntCycle_n;
                    MREQ <= IntCycle_n;
                end
                if (TState == 3'd3) begin
                    RD   <= 1'b0;
                    MREQ <= 1'b1;
                end
                if (TState == 3'd4)
                    MREQ <= 1'b0;
            end else begin
                if (TState == 3'd1 && !NoRead) begin
                    RD   <= ~Write;
                    MREQ <= ~IORQ;
                end
                if (TState == 3'd3) begin
                    RD   <= 1'b0;
                    MREQ <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst_s) begin
        if (rst_s) begin
            IORQ_int <= 1'b0;
        end else if (MCycle == 3'b001) begin
            if (TState == 3'd1)
                IORQ_int <= ~IntCycle_n;
            if (TState == 3'd2)
                IORQ_int <= 1'b0;
        end
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            IORQ_int_inhibit <= 3'b111;
        end else if (!IntCycle_n) begin
            if (MCycle == 3'b001)
                IORQ_int_inhibit <= {IORQ_int_inhibit[1:0], 1'b0};
            if (MCycle == 3'b010)
                IORQ_int_inhibit <= 3'b111;
        end
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            IORQ_t1 <= 1'b1;
        end else begin
            if (TState == 3'd1)
                IORQ_t1 <= ~IntCycle_n;
            if (TState == 3'd3)
                IORQ_t1 <= 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin  // T80a clears IORQ_t2 on RESET_n, not Reset_s
        if (rst)
            IORQ_t2 <= 1'b1;
        else
            IORQ_t2 <= IORQ_t1;
    end
end else if (BUS == BUS_AS) begin : g_as
    logic Reset_s, Wait_s, WR_n_i, IORQ_n_i, Req_Inhibit, MReq_Inhibit, RD, MREQ;
    logic rst_s;
    assign rst_s = ~Reset_s;
    wire unused_as = &{1'b0, cen, cen_p, cen_n};

    assign core_reset_n = Reset_s;
    assign core_cen     = 1'b1;
    assign core_wait_n  = Wait_s;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n    = core_m1_n;
    assign rfsh_n  = core_rfsh_n;
    assign busak_n = core_busak_n;
    assign dout    = core_do;
    assign bus_oe  = 1'b1;
    assign doe     = core_busak_n ? Write : 1'b0;
    assign dbin = 1'b0;
    assign sync = 1'b0;
    assign vait = 1'b0;
    assign hlda = 1'b0;

    assign mreq_n = ~MREQ | (Req_Inhibit & MReq_Inhibit);
    assign rd_n   = ~RD | Req_Inhibit;
    assign wr_n   = WR_n_i;
    assign iorq_n = IORQ_n_i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            Reset_s <= 1'b0;
        else
            Reset_s <= 1'b1;
    end

    always_ff @(negedge clk) begin
        Wait_s <= wait_n;
        if (TState == 3'd3 && core_busak_n)
            DI_Reg <= di;
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            WR_n_i <= 1'b1;
        end else begin
            WR_n_i <= 1'b1;
            if (TState == 3'd2)
                WR_n_i <= ~Write;
        end
    end

    always_ff @(posedge clk or posedge rst_s) begin
        if (rst_s)
            Req_Inhibit <= 1'b0;
        else
            Req_Inhibit <= (MCycle == 3'b001 && TState == 3'd2);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s)
            MReq_Inhibit <= 1'b0;
        else
            MReq_Inhibit <= (MCycle == 3'b001 && TState == 3'd2);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            RD       <= 1'b0;
            IORQ_n_i <= 1'b1;
            MREQ     <= 1'b0;
        end else begin
            if (MCycle == 3'b001) begin
                if (TState == 3'd1) begin
                    RD       <= IntCycle_n;
                    MREQ     <= IntCycle_n;
                    IORQ_n_i <= IntCycle_n;
                end
                if (TState == 3'd3) begin
                    RD       <= 1'b0;
                    IORQ_n_i <= 1'b1;
                    MREQ     <= 1'b1;
                end
                if (TState == 3'd4)
                    MREQ <= 1'b0;
            end else begin
                if (TState == 3'd1 && !NoRead) begin
                    RD       <= ~Write;
                    IORQ_n_i <= ~IORQ;
                    MREQ     <= ~IORQ;
                end
                if (TState == 3'd3) begin
                    RD       <= 1'b0;
                    IORQ_n_i <= 1'b1;
                    MREQ     <= 1'b0;
                end
            end
        end
    end
end else begin : g_s
    // BUS_S (T80s / T80se), BUS_SED (T80sed), BUS_GB (GBse)
    localparam bit SED = (BUS == BUS_SED);
    localparam bit GB  = (BUS == BUS_GB);
    wire unused_s = &{1'b0, cen_p, cen_n};

    assign core_reset_n = reset_n;
    assign core_cen     = cen;
    assign core_wait_n  = wait_n;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n         = core_m1_n;
    assign rfsh_n       = core_rfsh_n;
    assign busak_n      = core_busak_n;
    assign dout         = core_do;
    assign doe    = 1'b0;
    assign bus_oe = 1'b1;
    assign dbin   = 1'b0;
    assign sync   = 1'b0;
    assign vait   = 1'b0;
    assign hlda   = 1'b0;

    logic t1w;                         // T1, or T2 while WAIT_n is low (T80sed: T1 or T2)
    assign t1w = TState == 3'd1 || (TState == 3'd2 && (!wait_n || SED));

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_n   <= 1'b1;
            wr_n   <= 1'b1;
            iorq_n <= 1'b1;
            mreq_n <= 1'b1;
            DI_Reg <= 8'h00;
        end else if (cen) begin
            rd_n   <= 1'b1;
            wr_n   <= 1'b1;
            iorq_n <= 1'b1;
            mreq_n <= 1'b1;
            if (MCycle == 3'b001) begin
                if (TState == 3'd1 || (TState == 3'd2 && !wait_n)) begin
                    rd_n   <= ~IntCycle_n;
                    mreq_n <= ~IntCycle_n;
                    if (!GB)
                        iorq_n <= IntCycle_n;
                end
                if (TState == 3'd3)
                    mreq_n <= 1'b0;
            end else if (GB && MCycle == 3'b011 && !IntCycle_n) begin
                if (TState == 3'd1)
                    iorq_n <= 1'b0;            // GB: interrupt acknowledge
            end else begin
                if (t1w && !NoRead && !Write) begin
                    rd_n   <= 1'b0;
                    iorq_n <= ~IORQ;
                    mreq_n <= IORQ;
                end
                if (T2WRITE == 0 && !SED) begin
                    if (TState == 3'd2 && Write) begin
                        wr_n   <= 1'b0;
                        iorq_n <= ~IORQ;
                        mreq_n <= IORQ;
                    end
                end else begin
                    if (t1w && Write) begin
                        wr_n   <= 1'b0;
                        iorq_n <= ~IORQ;
                        mreq_n <= IORQ;
                    end
                end
            end
            if (TState == 3'd2 && wait_n)
                DI_Reg <= di;
        end
    end
end
endgenerate

endmodule

// ===== t80sv_tops.sv =====
//============================================================================
//  t80sv_tops - drop-in replacements for the T80 VHDL tops: same ports, same generics (as parameters)
//
//    t80sv_T80s  t80sv_T80se  t80sv_T80sed  t80sv_T80pa  t80sv_T80pa_phx (Phoenix ports)  t80sv_T8080se
//    t80sv_GBse  t80sv_T80a  t80sv_T80as
//
//  T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018
//  Sorgelig and contributors (MiSTer-devel lineage); T80a bus timing by Fabio Belavenuto and Charlie Ingley.
//  Phoenix core additions (I8080 / I8085 / RIM_D / SOD on t80sv_T80pa) by Rodimus.
//  Copyright (C) 2026 Rodimus  (SystemVerilog translation; Phoenix 8080 / 8085 additions)
//  Based on T80 (VHDL):
//    Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
//    T80 versions by MikeJ (2005), TobiFlex, Sean Riddle; Copyright (c) 2018 Sorgelig (MiSTer-devel);
//    T80a bus timing by Fabio Belavenuto and Charlie Ingley; T80pa top level by Sorgelig.
//  Redistribution and use in source and synthezised forms, with or without modification, are permitted provided
//  that the following conditions are met: Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer. Redistributions in synthesized form must reproduce the
//  above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
//  materials provided with the distribution. Neither the name of the author nor the names of other contributors
//  may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
//  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  Inputs that have a default value in the VHDL top are tri1 / tri0 nets: an instance may leave them unconnected,
//  as with the VHDL, and they read as that default.
//============================================================================

module t80sv_T80s #(
    parameter int Mode    = 0,
    parameter int T2Write = 1,
    parameter int IOWait  = 1
) (
    input  logic        RESET_n,
    input  logic        CLK,
    input  tri1  CEN,
    input  tri1  WAIT_n,
    input  tri1  INT_n,
    input  tri1  NMI_n,
    input  tri1  BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    input  tri0  OUT0,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(Mode), .T2WRITE(T2Write), .IOWAIT(IOWait), .BUS(0)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(CEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n), .nmi_n(NMI_n),
    .busrq_n(BUSRQ_n), .di(DI), .out0(OUT0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0), .i8080(1'b0), .i8085(1'b0),
    .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n), .rd_n(RD_n), .wr_n(WR_n),
    .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(), .sod(), .doe(), .bus_oe(),
    .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T80se #(
    parameter int Mode    = 0,
    parameter int T2Write = 0,
    parameter int IOWait  = 1
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CLKEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(Mode), .T2WRITE(T2Write), .IOWAIT(IOWait), .BUS(0)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(),
    .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T80sed (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CLKEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(0), .T2WRITE(1), .IOWAIT(1), .BUS(1)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(),
    .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T80pa #(
    parameter int Mode = 0
) (
    input  logic         RESET_n,
    input  logic         CLK,
    input  tri1  CEN_p,
    input  tri1  CEN_n,
    input  tri1  WAIT_n,
    input  tri1  INT_n,
    input  tri1  NMI_n,
    input  tri1  BUSRQ_n,
    output logic         M1_n,
    output logic         MREQ_n,
    output logic         IORQ_n,
    output logic         RD_n,
    output logic         WR_n,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    input  tri0  OUT0,
    output logic [15:0]  A,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    input  tri0  R800_mode,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR
);
t80sv #(.MODE(Mode), .BUS(2)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(1'b0), .cen_p(CEN_p), .cen_n(CEN_n), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(OUT0), .r800_mode(R800_mode), .dirset(DIRSet), .dir(DIR),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(REG),
    .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

// T80pa with the Phoenix core additions: I8080 (8080 mode on a Mode 0 build), I8085 RIM / SIM, RIM_D, SOD
module t80sv_T80pa_phx #(
    parameter int Mode = 0
) (
    input  logic         RESET_n,
    input  logic         CLK,
    input  tri1  CEN_p,
    input  tri1  CEN_n,
    input  tri1  WAIT_n,
    input  tri1  INT_n,
    input  tri1  NMI_n,
    input  tri1  BUSRQ_n,
    output logic         M1_n,
    output logic         MREQ_n,
    output logic         IORQ_n,
    output logic         RD_n,
    output logic         WR_n,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    input  tri0  OUT0,
    output logic [15:0]  A,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    input  tri0  R800_mode,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR,
    input  tri0  I8080,
    input  tri0  I8085,
    input  tri0  [7:0] RIM_D,
    output logic         SOD
);
t80sv #(.MODE(Mode), .BUS(2)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(1'b0), .cen_p(CEN_p), .cen_n(CEN_n), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(OUT0), .r800_mode(R800_mode), .dirset(DIRSet), .dir(DIR),
    .i8080(I8080), .i8085(I8085), .rim_d(RIM_D), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(REG),
    .sod(SOD), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T8080se #(
    parameter int Mode    = 2,
    parameter int T2Write = 0
) (
    input  logic        RESET_n,
    input  logic        CLK,
    input  logic        CLKEN,
    input  logic        READY,
    input  logic        HOLD,          // unused, as in T8080se
    input  logic        INT,
    output logic        INTE,
    output logic        DBIN,
    output logic        SYNC,
    output logic        VAIT,
    output logic        HLDA,
    output logic        WR_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(Mode), .T2WRITE(T2Write), .IOWAIT(0), .BUS(3)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(READY), .int_n(~INT),
    .nmi_n(1'b1), .busrq_n(HOLD), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(), .mreq_n(), .iorq_n(), .rd_n(),
    .wr_n(WR_n), .rfsh_n(), .halt_n(), .busak_n(), .inte(INTE), .stop(), .reg_o(), .sod(), .doe(), .bus_oe(),
    .dbin(DBIN), .sync(SYNC), .vait(VAIT), .hlda(HLDA)
);
endmodule

module t80sv_GBse #(
    parameter int T2Write = 1,
    parameter int IOWait  = 1
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CLKEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic        STOP,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(3), .T2WRITE(T2Write), .IOWAIT(IOWait), .BUS(4), .Flag_S(0), .Flag_P(0), .Flag_X(0), .Flag_Y(0),
        .Flag_C(4), .Flag_H(5), .Flag_N(6), .Flag_Z(7)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(STOP),
    .reg_o(), .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

// T80a: tri-state address / control / data bus, released while BUSAK_n is low; uses both clock edges
module t80sv_T80a #(
    parameter int Mode   = 0,
    parameter int IOWait = 1
) (
    input  logic        RESET_n,
    input  logic        R800_mode,
    input  logic        CLK_n,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output tri          MREQ_n,
    output tri          IORQ_n,
    output tri          RD_n,
    output tri          WR_n,
    output tri          RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output tri   [15:0] A,
    inout  tri   [7:0]  D
);
logic        mreq_n_i, iorq_n_i, rd_n_i, wr_n_i, rfsh_n_i, bus_oe, doe;
logic [15:0] a_i;
logic [7:0]  do_i;
t80sv #(.MODE(Mode), .IOWAIT(IOWait), .BUS(5)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(1'b1), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(D), .out0(1'b0), .r800_mode(R800_mode), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(a_i), .dout(do_i), .m1_n(M1_n), .mreq_n(mreq_n_i),
    .iorq_n(iorq_n_i), .rd_n(rd_n_i), .wr_n(wr_n_i), .rfsh_n(rfsh_n_i), .halt_n(HALT_n), .busak_n(BUSAK_n),
    .inte(), .stop(), .reg_o(), .sod(), .doe(doe), .bus_oe(bus_oe), .dbin(), .sync(), .vait(), .hlda()
);
assign MREQ_n = bus_oe ? mreq_n_i : 1'bz;
assign IORQ_n = bus_oe ? iorq_n_i : 1'bz;
assign RD_n   = bus_oe ? rd_n_i : 1'bz;
assign WR_n   = bus_oe ? wr_n_i : 1'bz;
assign RFSH_n = bus_oe ? rfsh_n_i : 1'bz;
assign A      = bus_oe ? a_i : 16'bz;
assign D      = doe ? do_i : 8'bz;
endmodule

module t80sv_T80as #(
    parameter int Mode = 0
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO,
    output logic        DOE
);
t80sv #(.MODE(Mode), .BUS(6)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(1'b1), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(),
    .sod(), .doe(DOE), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

// T80 (the bare CPU entity): DInst = data bus for opcode fetch, DI = latched data for the rest
module t80sv_T80 #(
    parameter int Mode   = 0,
    parameter int IOWait = 0,
    parameter int Flag_C = 0,
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic         RESET_n,
    input  logic         CLK_n,
    input  logic         CEN,
    input  logic         WAIT_n,
    input  logic         INT_n,
    input  logic         NMI_n,
    input  logic         BUSRQ_n,
    output logic         M1_n,
    output logic         IORQ,
    output logic         NoRead,
    output logic         Write,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    output logic [15:0]  A,
    input  logic [7:0]   DInst,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    output logic [2:0]   MC,
    output logic [2:0]   TS,
    output logic         IntCycle_n,
    output logic         IntE,
    output logic         Stop,
    input  tri0  R800_mode,
    input  tri0  out0,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR
);
t80sv_core #(.MODE(Mode), .IOWAIT(IOWait), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X),
             .Flag_H(Flag_H), .Flag_Y(Flag_Y), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) u0 (
    .RESET_n(RESET_n), .CLK_n(CLK_n), .CEN(CEN), .WAIT_n(WAIT_n), .INT_n(INT_n), .NMI_n(NMI_n), .BUSRQ_n(BUSRQ_n),
    .M1_n(M1_n), .IORQ(IORQ), .NoRead(NoRead), .Write(Write), .RFSH_n(RFSH_n), .HALT_n(HALT_n), .BUSAK_n(BUSAK_n),
    .A(A), .DInst(DInst), .DI(DI), .DO(DO), .MC(MC), .TS(TS), .IntCycle_n(IntCycle_n), .IntE(IntE), .Stop(Stop),
    .R800_mode(R800_mode), .out0(out0), .REG(REG), .DIRSet(DIRSet), .DIR(DIR), .I8080(1'b0), .I8085(1'b0),
    .RIM_D(8'h00), .SOD()
);
endmodule

// T80 entity of the Phoenix copy: Mode_g generic, runtime I8080 / I8085 / RIM_D, SOD
module t80sv_T80_phx #(
    parameter int Mode_g = 0,
    parameter int IOWait = 0,
    parameter int Flag_C = 0,
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic         RESET_n,
    input  logic         CLK_n,
    input  logic         CEN,
    input  logic         WAIT_n,
    input  logic         INT_n,
    input  logic         NMI_n,
    input  logic         BUSRQ_n,
    output logic         M1_n,
    output logic         IORQ,
    output logic         NoRead,
    output logic         Write,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    output logic [15:0]  A,
    input  logic [7:0]   DInst,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    output logic [2:0]   MC,
    output logic [2:0]   TS,
    output logic         IntCycle_n,
    output logic         IntE,
    output logic         Stop,
    input  tri0  R800_mode,
    input  tri0  out0,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR,
    input  tri0  I8080,
    input  tri0  I8085,
    input  tri0  [7:0] RIM_D,
    output logic         SOD
);
t80sv_core #(.MODE(Mode_g), .IOWAIT(IOWait), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X),
             .Flag_H(Flag_H), .Flag_Y(Flag_Y), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) u0 (
    .RESET_n(RESET_n), .CLK_n(CLK_n), .CEN(CEN), .WAIT_n(WAIT_n), .INT_n(INT_n), .NMI_n(NMI_n), .BUSRQ_n(BUSRQ_n),
    .M1_n(M1_n), .IORQ(IORQ), .NoRead(NoRead), .Write(Write), .RFSH_n(RFSH_n), .HALT_n(HALT_n), .BUSAK_n(BUSAK_n),
    .A(A), .DInst(DInst), .DI(DI), .DO(DO), .MC(MC), .TS(TS), .IntCycle_n(IntCycle_n), .IntE(IntE), .Stop(Stop),
    .R800_mode(R800_mode), .out0(out0), .REG(REG), .DIRSet(DIRSet), .DIR(DIR), .I8080(I8080), .I8085(I8085),
    .RIM_D(RIM_D), .SOD(SOD)
);
endmodule
