//============================================================================
//
//  DEFLATE decoder (RFC 1951): stored, fixed and dynamic Huffman blocks, 32K window
//  Copyright (C) 2026 Rodimus
//
//  Byte stream in (LSB-first bit order), byte stream out, ready / valid on both sides. Canonical Huffman codes
//  are decoded one bit per clock (count / first / base per code length), so a literal costs about its code length
//  in clocks and a match two clocks per byte. Written for loading MAME artwork PNGs at MRA time.
//
//  Redistribution and use in source and synthesized forms, with or without modification, are permitted
//  provided that the above copyright notice is retained. THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
//
//============================================================================

module inflate
(
    input            clk,
    input            reset,             // start of a new stream

    input            in_valid,
    input      [7:0] in_data,
    output           in_ready,

    output reg       out_valid = 1'b0,
    output reg [7:0] out_data = 8'd0,
    input            out_ready,

    output reg       done = 1'b0        // final block finished
);

// ---------------------------------------------------------------- bit reader

reg  [31:0] bitbuf = 32'd0;
reg   [5:0] bitcnt = 6'd0;
reg   [4:0] take;                       // bits consumed this clock
assign in_ready = (bitcnt <= 6'd24) && !done;

always @(posedge clk) begin
    if (reset) begin bitbuf <= 32'd0; bitcnt <= 6'd0; end
    else begin
        reg [31:0] b;
        reg  [5:0] c;
        b = bitbuf >> take;
        c = bitcnt - {1'b0, take};
        if (in_valid && in_ready) begin b = b | ({24'd0, in_data} << c); c = c + 6'd8; end
        bitbuf <= b;
        bitcnt <= c;
    end
end

// ---------------------------------------------------------------- tables

reg  [3:0] lens[320];                   // litlen 0-287, distance 288-319
reg  [2:0] cl_lens[19];
reg  [8:0] cnt  [3][16];                // t = 0 code-length, 1 litlen, 2 distance
reg [15:0] first[3][16];
reg  [8:0] base [3][16];
reg  [8:0] offs [16];
reg  [4:0] sym_d [32];
reg  [4:0] sym_cl[19];

function automatic [4:0] cl_order(input [4:0] i);
    case (i)
        5'd0: cl_order = 5'd16;  5'd1: cl_order = 5'd17;  5'd2: cl_order = 5'd18;  5'd3: cl_order = 5'd0;
        5'd4: cl_order = 5'd8;   5'd5: cl_order = 5'd7;   5'd6: cl_order = 5'd9;   5'd7: cl_order = 5'd6;
        5'd8: cl_order = 5'd10;  5'd9: cl_order = 5'd5;   5'd10: cl_order = 5'd11; 5'd11: cl_order = 5'd4;
        5'd12: cl_order = 5'd12; 5'd13: cl_order = 5'd3;  5'd14: cl_order = 5'd13; 5'd15: cl_order = 5'd2;
        5'd16: cl_order = 5'd14; 5'd17: cl_order = 5'd1;  default: cl_order = 5'd15;
    endcase
endfunction
function automatic [8:0] len_base(input [4:0] i);        // symbol 257 + i
    case (i)
        5'd0: len_base = 9'd3;    5'd1: len_base = 9'd4;    5'd2: len_base = 9'd5;    5'd3: len_base = 9'd6;
        5'd4: len_base = 9'd7;    5'd5: len_base = 9'd8;    5'd6: len_base = 9'd9;    5'd7: len_base = 9'd10;
        5'd8: len_base = 9'd11;   5'd9: len_base = 9'd13;   5'd10: len_base = 9'd15;  5'd11: len_base = 9'd17;
        5'd12: len_base = 9'd19;  5'd13: len_base = 9'd23;  5'd14: len_base = 9'd27;  5'd15: len_base = 9'd31;
        5'd16: len_base = 9'd35;  5'd17: len_base = 9'd43;  5'd18: len_base = 9'd51;  5'd19: len_base = 9'd59;
        5'd20: len_base = 9'd67;  5'd21: len_base = 9'd83;  5'd22: len_base = 9'd99;  5'd23: len_base = 9'd115;
        5'd24: len_base = 9'd131; 5'd25: len_base = 9'd163; 5'd26: len_base = 9'd195; 5'd27: len_base = 9'd227;
        default: len_base = 9'd258;
    endcase
endfunction
function automatic [4:0] len_extra(input [4:0] i);
    len_extra = (i < 5'd8 || i == 5'd28) ? 5'd0 : 5'((i - 5'd4) >> 2);
endfunction
function automatic [14:0] dist_base(input [4:0] i);
    case (i)
        5'd0: dist_base = 15'd1;      5'd1: dist_base = 15'd2;      5'd2: dist_base = 15'd3;      5'd3: dist_base = 15'd4;
        5'd4: dist_base = 15'd5;      5'd5: dist_base = 15'd7;      5'd6: dist_base = 15'd9;      5'd7: dist_base = 15'd13;
        5'd8: dist_base = 15'd17;     5'd9: dist_base = 15'd25;     5'd10: dist_base = 15'd33;    5'd11: dist_base = 15'd49;
        5'd12: dist_base = 15'd65;    5'd13: dist_base = 15'd97;    5'd14: dist_base = 15'd129;   5'd15: dist_base = 15'd193;
        5'd16: dist_base = 15'd257;   5'd17: dist_base = 15'd385;   5'd18: dist_base = 15'd513;   5'd19: dist_base = 15'd769;
        5'd20: dist_base = 15'd1025;  5'd21: dist_base = 15'd1537;  5'd22: dist_base = 15'd2049;  5'd23: dist_base = 15'd3073;
        5'd24: dist_base = 15'd4097;  5'd25: dist_base = 15'd6145;  5'd26: dist_base = 15'd8193;  5'd27: dist_base = 15'd12289;
        5'd28: dist_base = 15'd16385; default: dist_base = 15'd24577;
    endcase
endfunction
function automatic [4:0] dist_extra(input [4:0] i);
    dist_extra = (i < 5'd4) ? 5'd0 : 5'((i - 5'd2) >> 1);
endfunction

// ---------------------------------------------------------------- state machine

localparam S_HDR = 5'd0, S_ALIGN = 5'd1, S_SLEN = 5'd2, S_SNLEN = 5'd3, S_SCOPY = 5'd4, S_FIXED = 5'd5,
           S_DHDR = 5'd6, S_CLL = 5'd7, S_BUILD = 5'd8, S_LENS = 5'd9, S_REP = 5'd10, S_MOVE = 5'd11,
           S_SYM = 5'd12, S_LEXT = 5'd13, S_DSYM = 5'd14, S_DEXT = 5'd15, S_COPY = 5'd16, S_COPY2 = 5'd17,
           S_DONE = 5'd18, S_SYM2 = 5'd19;

reg   [4:0] st = S_HDR;
reg         bfinal = 1'b0;
reg  [15:0] slen = 16'd0;
reg   [8:0] hlit = 9'd0;
reg   [5:0] hdist = 6'd0;
reg   [4:0] hclen = 5'd0;
reg   [8:0] idx = 9'd0;
reg   [1:0] bt = 2'd0;                  // table being built / decoded
reg   [1:0] bphase = 2'd0;
reg   [3:0] bl = 4'd0;
reg  [15:0] code = 16'd0;
reg   [3:0] clen = 4'd0;
reg   [3:0] prev_len = 4'd0;
reg   [7:0] rep = 8'd0;
reg   [3:0] rep_val = 4'd0;
reg   [4:0] xbits = 5'd0;
reg   [8:0] mlen = 9'd0;
reg  [14:0] mdist = 15'd0;
reg  [14:0] wptr = 15'd0;

// decoder: one bit appended per clock; a hit when the code lands inside this length's range
wire [15:0] code_n = {code[14:0], bitbuf[0]};
wire  [3:0] clen_n = clen + 4'd1;
wire [15:0] rel    = code_n - first[bt][clen_n];
wire        hit    = rel < {7'd0, cnt[bt][clen_n]};
wire  [8:0] hidx   = base[bt][clen_n] + rel[8:0];
wire  [8:0] hsym   = (bt == 2'd0) ? {4'd0, sym_cl[hidx[4:0]]} : {4'd0, sym_d[hidx[4:0]]};   // code-length / distance
// litlen symbols in block RAM (as registers ~2K ALMs): addressed by hidx on the hit clock, used in S_SYM2
wire  [8:0] ll_q;
reg   [8:0] ll_wa, ll_wd;
reg         ll_we = 1'b0;
reg   [8:0] hidx_q;                    // held while S_SYM2 waits
dpram_dc #(.widthad_a(9), .width_a(9)) sym_ll
(
    .clock_a(clk), .address_a(ll_wa), .data_a(ll_wd), .wren_a(ll_we), .q_a(),
    .clock_b(clk), .address_b(st == S_SYM2 ? hidx_q : hidx), .data_b('0), .wren_b(1'b0), .q_b(ll_q)
);

wire  [8:0] nsym   = (bt == 2'd0) ? 9'd19 : (bt == 2'd1) ? hlit : {3'd0, hdist};
wire  [3:0] blen   = (bt == 2'd0) ? {1'b0, cl_lens[idx[4:0]]} : (bt == 2'd1) ? lens[idx] : lens[9'd288 + idx];

wire        out_free = !out_valid || out_ready;
wire  [7:0] win_q;
wire        win_we = (st == S_SCOPY && slen != 16'd0 && bitcnt >= 6'd8 && out_free) ||
                     (st == S_SYM2 && out_free && ll_q < 9'd256) ||
                     (st == S_COPY2);
wire  [7:0] win_d  = (st == S_SCOPY) ? bitbuf[7:0] : (st == S_SYM2) ? ll_q[7:0] : win_q;

dpram_dc #(.widthad_a(15)) window
(
    .clock_a(clk), .address_a(wptr), .data_a(win_d), .wren_a(win_we), .q_a(),
    .clock_b(clk), .address_b(wptr - mdist), .data_b('0), .wren_b(1'b0), .q_b(win_q)
);

always @* begin
    take = 5'd0;
    case (st)
        S_HDR:   if (bitcnt >= 6'd3) take = 5'd3;
        S_ALIGN: take = {2'b00, bitcnt[2:0]};
        S_SLEN, S_SNLEN: if (bitcnt >= 6'd16) take = 5'd16;
        S_SCOPY: if (slen != 16'd0 && bitcnt >= 6'd8 && out_free) take = 5'd8;
        S_DHDR:  if (bitcnt >= 6'd14) take = 5'd14;
        S_CLL:   if (idx[4:0] != hclen && bitcnt >= 6'd3) take = 5'd3;
        S_LENS:  if (bitcnt != 6'd0 && idx != hlit + {3'd0, hdist}) take = 5'd1;
        S_DSYM:  if (bitcnt != 6'd0) take = 5'd1;
        S_SYM:   if (bitcnt != 6'd0 && out_free) take = 5'd1;
        S_REP, S_LEXT, S_DEXT: if (xbits != 5'd0 && bitcnt >= {1'b0, xbits}) take = xbits;
        default: ;
    endcase
end

always @(posedge clk) begin
    ll_we <= 1'b0;
    if (out_valid && out_ready) out_valid <= 1'b0;
    if (win_we) wptr <= wptr + 15'd1;
    if (reset) begin
        st <= S_HDR; done <= 1'b0; out_valid <= 1'b0; wptr <= 15'd0;
    end
    else case (st)
        S_HDR: if (bitcnt >= 6'd3) begin
            bfinal <= bitbuf[0];
            idx    <= 9'd0;
            st     <= (bitbuf[2:1] == 2'd0) ? S_ALIGN : (bitbuf[2:1] == 2'd1) ? S_FIXED : S_DHDR;
        end
        S_ALIGN: st <= S_SLEN;
        S_SLEN:  if (bitcnt >= 6'd16) begin slen <= bitbuf[15:0]; st <= S_SNLEN; end
        S_SNLEN: if (bitcnt >= 6'd16) st <= S_SCOPY;
        S_SCOPY: if (slen == 16'd0) st <= bfinal ? S_DONE : S_HDR;
                 else if (bitcnt >= 6'd8 && out_free) begin
                     out_data <= bitbuf[7:0]; out_valid <= 1'b1; slen <= slen - 16'd1;
                 end
        S_FIXED:                                      // fixed code lengths, then build litlen + distance
            if (idx < 9'd320) begin
                lens[idx] <= (idx < 9'd144) ? 4'd8 : (idx < 9'd256) ? 4'd9 : (idx < 9'd280) ? 4'd7 :
                             (idx < 9'd288) ? 4'd8 : 4'd5;
                idx <= idx + 9'd1;
            end else begin
                hlit <= 9'd288; hdist <= 6'd32; bt <= 2'd1; idx <= 9'd0; bphase <= 2'd0; st <= S_BUILD;
            end
        S_DHDR: if (bitcnt >= 6'd14) begin
            hlit  <= {4'd0, bitbuf[4:0]} + 9'd257;
            hdist <= {1'b0, bitbuf[9:5]} + 6'd1;
            hclen <= {1'b0, bitbuf[13:10]} + 5'd4;
            for (int i = 0; i < 19; i++) cl_lens[i] <= 3'd0;
            idx <= 9'd0; st <= S_CLL;
        end
        S_CLL: if (idx[4:0] == hclen) begin bt <= 2'd0; idx <= 9'd0; bphase <= 2'd0; st <= S_BUILD; end
               else if (bitcnt >= 6'd3) begin cl_lens[cl_order(idx[4:0])] <= bitbuf[2:0]; idx <= idx + 9'd1; end
        S_BUILD:
            case (bphase)
                2'd0: begin                           // count codes per length
                    if (idx == 9'd0) for (int l = 0; l < 16; l++) cnt[bt][l] <= 9'd0;
                    if (idx < nsym) begin
                        if (blen != 4'd0) cnt[bt][blen] <= (idx == 9'd0) ? 9'd1 : cnt[bt][blen] + 9'd1;
                        idx <= idx + 9'd1;
                    end else begin bphase <= 2'd1; bl <= 4'd1; end
                end
                2'd1: begin                           // first code / table base per length
                    first[bt][bl] <= (bl == 4'd1) ? 16'd0 : (first[bt][bl - 4'd1] + {7'd0, cnt[bt][bl - 4'd1]}) << 1;
                    base[bt][bl]  <= (bl == 4'd1) ? 9'd0 : base[bt][bl - 4'd1] + cnt[bt][bl - 4'd1];
                    offs[bl]      <= (bl == 4'd1) ? 9'd0 : base[bt][bl - 4'd1] + cnt[bt][bl - 4'd1];
                    if (bl == 4'd15) begin bphase <= 2'd2; idx <= 9'd0; end
                    bl <= bl + 4'd1;
                end
                default: begin                        // symbols in canonical order
                    if (idx < nsym) begin
                        if (blen != 4'd0) begin
                            if (bt == 2'd0)      sym_cl[offs[blen][4:0]] <= idx[4:0];
                            else if (bt == 2'd1) begin ll_wa <= offs[blen]; ll_wd <= idx; ll_we <= 1'b1; end
                            else                 sym_d[offs[blen][4:0]] <= idx[4:0];
                            offs[blen] <= offs[blen] + 9'd1;
                        end
                        idx <= idx + 9'd1;
                    end
                    else if (bt == 2'd0) begin st <= S_LENS; idx <= 9'd0; prev_len <= 4'd0; code <= 16'd0; clen <= 4'd0; end
                    else if (bt == 2'd1) begin bt <= 2'd2; idx <= 9'd0; bphase <= 2'd0; end
                    else begin bt <= 2'd1; st <= S_SYM; code <= 16'd0; clen <= 4'd0; end
                end
            endcase
        S_LENS:                                       // litlen + distance code lengths through the code-length code
            if (idx == hlit + {3'd0, hdist}) begin idx <= {3'd0, hdist}; st <= S_MOVE; end
            else if (bitcnt != 6'd0) begin
                if (hit) begin
                    code <= 16'd0; clen <= 4'd0;
                    case (hsym[4:0])
                        5'd16: begin xbits <= 5'd2; rep_val <= prev_len; rep <= 8'd3;  st <= S_REP; end
                        5'd17: begin xbits <= 5'd3; rep_val <= 4'd0;     rep <= 8'd3;  st <= S_REP; end
                        5'd18: begin xbits <= 5'd7; rep_val <= 4'd0;     rep <= 8'd11; st <= S_REP; end
                        default: begin lens[idx] <= hsym[3:0]; prev_len <= hsym[3:0]; idx <= idx + 9'd1; end
                    endcase
                end else begin code <= code_n; clen <= clen_n; end
            end
        S_REP:
            if (xbits != 5'd0) begin
                if (bitcnt >= {1'b0, xbits}) begin rep <= rep + (bitbuf[7:0] & ((8'd1 << xbits) - 8'd1)); xbits <= 5'd0; end
            end
            else if (rep != 8'd0) begin lens[idx] <= rep_val; idx <= idx + 9'd1; rep <= rep - 8'd1; end
            else begin prev_len <= rep_val; st <= S_LENS; end
        S_MOVE:                                       // distance lengths from hlit.. up to 288.., top first
            if (idx != 9'd0) begin
                lens[9'd287 + idx] <= lens[hlit + idx - 9'd1];
                idx <= idx - 9'd1;
            end else begin
                bt <= 2'd1; idx <= 9'd0; bphase <= 2'd0; st <= S_BUILD;
            end
        S_SYM: if (bitcnt != 6'd0 && out_free) begin
            if (hit) begin code <= 16'd0; clen <= 4'd0; hidx_q <= hidx; st <= S_SYM2; end   // symbol readable next clock
            else begin code <= code_n; clen <= clen_n; end
        end
        S_SYM2: if (out_free) begin
            if (ll_q < 9'd256) begin out_data <= ll_q[7:0]; out_valid <= 1'b1; st <= S_SYM; end
            else if (ll_q == 9'd256) st <= bfinal ? S_DONE : S_HDR;
            else begin
                mlen  <= len_base(5'(ll_q - 9'd257));
                xbits <= len_extra(5'(ll_q - 9'd257));
                st    <= S_LEXT;
            end
        end
        S_LEXT: if (xbits == 5'd0 || bitcnt >= {1'b0, xbits}) begin
            if (xbits != 5'd0) mlen <= mlen + (9'(bitbuf[4:0]) & ((9'd1 << xbits) - 9'd1));
            xbits <= 5'd0; bt <= 2'd2; code <= 16'd0; clen <= 4'd0; st <= S_DSYM;
        end
        S_DSYM: if (bitcnt != 6'd0) begin
            if (hit) begin
                code <= 16'd0; clen <= 4'd0;
                mdist <= dist_base(hsym[4:0]);
                xbits <= dist_extra(hsym[4:0]);
                st    <= S_DEXT;
            end else begin code <= code_n; clen <= clen_n; end
        end
        S_DEXT: if (xbits == 5'd0 || bitcnt >= {1'b0, xbits}) begin
            if (xbits != 5'd0) mdist <= mdist + (bitbuf[14:0] & ((15'd1 << xbits) - 15'd1));
            xbits <= 5'd0; bt <= 2'd1; st <= S_COPY;
        end
        S_COPY: if (out_free) st <= (mlen == 9'd0) ? S_SYM : S_COPY2;   // window read address settles
        S_COPY2: begin out_data <= win_q; out_valid <= 1'b1; mlen <= mlen - 9'd1; st <= S_COPY; end
        S_DONE: done <= 1'b1;
        default: ;
    endcase
end

`ifdef INFLATE_DEBUG
always @(posedge clk) begin
    if (st == S_CLL && idx[4:0] == hclen) begin
        $write("hlit %0d hdist %0d hclen %0d cl", hlit, hdist, hclen);
        for (int i = 0; i < 19; i++) $write(" %0d", cl_lens[i]);
        $write("\n");
    end
    if (st == S_BUILD && bt == 2'd0 && bphase == 2'd2 && idx == 9'd19) begin
        $write("cnt0"); for (int i = 0; i < 8; i++) $write(" %0d", cnt[0][i]);
        $write(" first0"); for (int i = 0; i < 8; i++) $write(" %0d", first[0][i]);
        $write(" sym_cl"); for (int i = 0; i < 19; i++) $write(" %0d", sym_cl[i]);
        $write("\n");
    end
    if (st == S_LENS && idx == hlit + {3'd0, hdist}) begin
        $write("lens"); for (int i = 60; i < 80; i++) $write(" %0d", lens[i]); $write(" dist"); for (int i = 0; i < 23; i++) $write(" %0d", lens[hlit + i]); $write("\n");
    end
end
`endif
endmodule
