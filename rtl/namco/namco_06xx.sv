//============================================================================
//
//  Namco 06xx: CPU interface to up to four Namco 5xxx MCUs
//
//  Per MAME namco06.cpp. Control register:
//    [3:0] chip select mask, [4] 1 = read / 0 = write, [7:5] timer divider
//    (0 = stopped). While running, the timer toggles every 2^(ctrl[7:5]-1)
//    base ticks, raising each selected chip's select (its IRQ) and the CPU's
//    NMI on alternate edges. A control write restarts the timer, so the first
//    edge follows the write at once (as in Dar's working Galaga / Xevious
//    cores), and the first pulse after entering read mode is suppressed.
//  Data reads AND together the selected chips' outputs; data writes go to
//    every selected chip. Neither waits for the timer.
//  Base tick: clk / BASE_DIV. Control and data writes take effect one
//    clock late, standing in for MAME's deferred (synchronized) writes.
//
//============================================================================
`default_nettype none

module namco_06xx #(parameter BASE_DIV = 1024)   // clk / BASE_DIV = the 06xx clock (MASTER / 6 / 64 = 48 kHz)
(
    input  wire        clk,        // 49.152 MHz
    input  wire        reset,
    input  wire        pause,      // freezes the timer with the CPUs
    input  wire        irq_on_access,  // chip IRQ raised by the CPU's data access, released on the timer's falling edge (Dar's Xevious 06xx)

    // CPU side
    input  wire  [7:0] cpu_dout,
    input  wire        data_wr, data_rd,
    input  wire        ctrl_wr, ctrl_rd,
    output wire  [7:0] cpu_din,
    output wire        nmi_n,

    // chips 0-3
    output wire  [3:0] chipsel,     // select pulse per chip
    output wire        rw0,         // R/W direction to chip 0 (MAME binds rw_callback<0> only)
    input  wire  [7:0] chip0_din, chip1_din, chip2_din, chip3_din,
    output wire  [7:0] chip_dout,   // write data to the selected chips
    output wire  [3:0] chip_wr      // per-chip write strobe
);

    // deferred control / data writes
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
    wire [6:0] div_limit = (7'd1 << (ctrl[7:5] - 3'd1)) - 7'd1;   // base ticks between timer edges, minus 1
    localparam integer BASE_LAST = BASE_DIV - 1;
    wire       base_ce   = (base_cnt == BASE_LAST[12:0]);

    always @(posedge clk) begin
        if (reset)           base_cnt <= 13'd0;
        else if (ctrl_apply) base_cnt <= BASE_LAST[12:0];   // restart: first edge on the next clock
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
            first_edge <= 1'b1;                 // first edge right after the write (timer restarted)
            if (ctrl_wdata_d[7:5] == 3'b000) begin
                timer_state <= 1'b0;            // stopped: selects and NMI released, R/W left as is
                chipsel_r   <= 4'h0;
                nmi_n_r     <= 1'b1;
            end else if (ctrl_wdata_d[4]) begin
                nmi_n_r      <= 1'b1;           // read mode: suppress the first pulse
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
                    if (!irq_on_access || read_stretch) chipsel_r <= ctrl[3:0];   // access mode: only the read-mode first edge
                    nmi_n_r   <= read_stretch ? 1'b1 : 1'b0;
                end else begin
                    chipsel_r <= 4'h0;
                    nmi_n_r   <= 1'b1;
                end
            end else begin
                div_cnt <= div_cnt + 7'd1;
            end
        end
        // access mode: a data read asks the selected chips for the next byte; a data write raises IRQ once the byte is latched
        if (irq_on_access && !ctrl_apply && enabled) begin
            if (rd_access)        chipsel_r <= ctrl[3:0];
            if (chip_wr_r != 4'h0) chipsel_r <= chip_wr_r;
        end
        end
    end

    assign chipsel = chipsel_r;
    assign rw0     = rw0_r;
    assign nmi_n   = nmi_n_r;

    // data read: AND of the selected chips (unselected read FF)
    wire [7:0] d0 = ctrl[0] ? chip0_din : 8'hFF;
    wire [7:0] d1 = ctrl[1] ? chip1_din : 8'hFF;
    wire [7:0] d2 = ctrl[2] ? chip2_din : 8'hFF;
    wire [7:0] d3 = ctrl[3] ? chip3_din : 8'hFF;
    wire [7:0] data_r_val = d0 & d1 & d2 & d3;

    assign cpu_din = ctrl_rd ? ctrl : (ctrl[4] ? data_r_val : 8'h00);

    // data write: one strobe to each selected chip, write mode only
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
