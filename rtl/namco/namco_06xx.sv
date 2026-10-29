//  Based on MAME namco06.cpp (Mike Harris, Aaron Giles, BSD-3-Clause)
`default_nettype none

module namco_06xx #(parameter BASE_DIV = 1024)
(
    input  wire        clk,
    input  wire        reset,
    input  wire        pause,
    input  wire        irq_on_access,

    input  wire  [7:0] cpu_dout,
    input  wire        data_wr, data_rd,
    input  wire        ctrl_wr, ctrl_rd,
    output wire  [7:0] cpu_din,
    output wire        nmi_n,

    output wire  [3:0] chipsel,
    output wire        rw0,
    input  wire  [7:0] chip0_din, chip1_din, chip2_din, chip3_din,
    output wire  [7:0] chip_dout,
    output wire  [3:0] chip_wr
);

    reg [7:0] ctrl_wdata_d;  reg ctrl_apply;
    reg [7:0] data_wdata_d;  reg data_apply;
    always @(posedge clk) begin
        ctrl_apply <= ctrl_wr;
        if (ctrl_wr) ctrl_wdata_d <= cpu_dout;
        data_apply <= data_wr;
        if (data_wr) data_wdata_d <= cpu_dout;
    end

    reg  [7:0] ctrl;
    reg        read_stretch;
    reg [12:0] base_cnt;
    reg  [6:0] div_cnt;
    reg        timer_state;
    reg        first_edge;
    reg  [3:0] chipsel_r;
    reg        rw0_r;
    reg        nmi_n_r;

    wire       wmode     = ~ctrl[4];
    wire       enabled   = |ctrl[7:5];
    wire [6:0] div_limit = (7'd1 << (ctrl[7:5] - 3'd1)) - 7'd1;
    localparam integer BASE_LAST = BASE_DIV - 1;
    wire       base_ce   = (base_cnt == BASE_LAST[12:0]);

    always @(posedge clk) begin
        if (reset)           base_cnt <= 13'd0;
        else if (ctrl_apply) base_cnt <= BASE_LAST[12:0];
        else                 base_cnt <= base_ce ? 13'd0 : base_cnt + 13'd1;
    end

    reg       data_rd_d;
    reg [3:0] chip_wr_r;
    always @(posedge clk) data_rd_d <= data_rd;
    wire      rd_access = irq_on_access & data_rd & ~data_rd_d & ctrl[4];

    always @(posedge clk) begin
        if (reset) begin
            ctrl         <= 8'h00;
            read_stretch <= 1'b0;
            div_cnt      <= 7'd0;
            timer_state  <= 1'b0;
            first_edge   <= 1'b0;
            chipsel_r    <= 4'h0;
            rw0_r        <= 1'b0;
            nmi_n_r      <= 1'b1;
        end else begin
        if (ctrl_apply) begin
            ctrl       <= ctrl_wdata_d;
            first_edge <= 1'b1;
            if (ctrl_wdata_d[7:5] == 3'b000) begin
                timer_state <= 1'b0;
                chipsel_r   <= 4'h0;
                nmi_n_r     <= 1'b1;
            end else if (ctrl_wdata_d[4]) begin
                nmi_n_r      <= 1'b1;
                read_stretch <= 1'b1;
            end else begin
                read_stretch <= 1'b0;
            end
        end else if (enabled && base_ce && !pause) begin
            if (first_edge || div_cnt == div_limit) begin
                first_edge   <= 1'b0;
                div_cnt      <= 7'd0;
                timer_state  <= ~timer_state;
                read_stretch <= 1'b0;
                if (~timer_state) begin
                    rw0_r     <= ctrl[4];
                    if (!irq_on_access || read_stretch) chipsel_r <= ctrl[3:0];
                    nmi_n_r   <= read_stretch ? 1'b1 : 1'b0;
                end else begin
                    chipsel_r <= 4'h0;
                    nmi_n_r   <= 1'b1;
                end
            end else begin
                div_cnt <= div_cnt + 7'd1;
            end
        end
        if (irq_on_access && !ctrl_apply && enabled) begin
            if (rd_access)        chipsel_r <= ctrl[3:0];
            if (chip_wr_r != 4'h0) chipsel_r <= chip_wr_r;
        end
        end
    end

    assign chipsel = chipsel_r;
    assign rw0     = rw0_r;
    assign nmi_n   = nmi_n_r;

    wire [7:0] d0 = ctrl[0] ? chip0_din : 8'hFF;
    wire [7:0] d1 = ctrl[1] ? chip1_din : 8'hFF;
    wire [7:0] d2 = ctrl[2] ? chip2_din : 8'hFF;
    wire [7:0] d3 = ctrl[3] ? chip3_din : 8'hFF;
    wire [7:0] data_r_val = d0 & d1 & d2 & d3;

    assign cpu_din = ctrl_rd ? ctrl : (ctrl[4] ? data_r_val : 8'h00);

    reg [7:0] chip_dout_r;
    always @(posedge clk) begin
        chip_wr_r <= 4'h0;
        if (data_apply && wmode) begin
            chip_dout_r <= data_wdata_d;
            chip_wr_r   <= ctrl[3:0];
        end
    end
    assign chip_dout = chip_dout_r;
    assign chip_wr   = chip_wr_r;

endmodule

`default_nettype wire
