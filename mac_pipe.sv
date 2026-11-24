// -----------------------------------------------------------------------------
// mac_pipe.sv : pipelined fixed-point MAC, ASIC-oriented (technology neutral)
//
//   Format : signed Q(DW-FRAC).FRAC, default Q1.15
//   Acc    : 2*DW+GUARD bits  (safe for 2^GUARD worst-case MACs)
//   Output : round-to-nearest, saturate to DW bits
//
//   S1 operand regs (enable-gated by in_valid -> less toggling)
//   S2 product reg   (+ optional 2nd reg, EXTRA_MUL_STAGE=1, for retiming)
//   S3 accumulate
//   S4 round + saturate
//
//   Latency   : 4 cycles (5 with EXTRA_MUL_STAGE=1)
//   Throughput: 1 MAC / cycle
//   Reset     : async assert, active-low, control flags only (datapath is
//               flag-qualified -> smaller/faster flops, no reset fan-out).
//               Deassert must be synchronized outside this block.
// -----------------------------------------------------------------------------
module mac_pipe #(
    parameter int DW               = 16,
    parameter int FRAC             = 15,
    parameter int GUARD            = 8,
    parameter bit EXTRA_MUL_STAGE  = 1'b0
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          in_valid,
    input  logic                          in_first,
    input  logic                          in_last,
    input  logic signed [DW-1:0]          in_a,
    input  logic signed [DW-1:0]          in_b,

    output logic                          out_valid,
    output logic signed [DW-1:0]          out_data,
    output logic signed [2*DW+GUARD-1:0]  out_acc
);
    localparam int PW = 2*DW;
    localparam int AW = 2*DW + GUARD;

    // ---------------- S1 : operand registers ----------------
    logic signed [DW-1:0] a_r, b_r;
    logic                 v1, f1, l1;

    always_ff @(posedge clk) begin
        if (in_valid) begin
            a_r <= in_a;
            b_r <= in_b;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) {v1, f1, l1} <= '0;
        else        {v1, f1, l1} <= {in_valid, in_first, in_last};
    end

    // ---------------- S2 : multiplier (+ optional retiming stage) ----------
    logic signed [PW-1:0] prod_c;
    assign prod_c = a_r * b_r;          // synth maps to Booth/Wallace + CPA

    logic signed [PW-1:0] p_r;
    logic                 v2, f2, l2;

    if (!EXTRA_MUL_STAGE) begin : g_mul1
        always_ff @(posedge clk) p_r <= prod_c;
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) {v2, f2, l2} <= '0;
            else        {v2, f2, l2} <= {v1, f1, l1};
    end else begin : g_mul2
        // two back-to-back regs: tool retimes (compile_ultra -retime /
        // optimize_registers) to split the multiplier at the CSA/CPA boundary
        logic signed [PW-1:0] p_m;
        logic                 vm, fm, lm;
        always_ff @(posedge clk) begin
            p_m <= prod_c;
            p_r <= p_m;
        end
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) {vm, fm, lm, v2, f2, l2} <= '0;
            else        {vm, fm, lm, v2, f2, l2} <= {v1, f1, l1, vm, fm, lm};
    end

    // ---------------- S3 : accumulate ----------------
    logic signed [AW-1:0] p_ext, acc_q;
    logic                 done3;
    assign p_ext = AW'(p_r);            // sign-extending cast

    always_ff @(posedge clk)
        if (v2) acc_q <= (f2 ? '0 : acc_q) + p_ext;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) done3 <= 1'b0;
        else        done3 <= v2 & l2;

    // ---------------- S4 : round + saturate ----------------
    localparam logic signed [AW-1:0] HALF = AW'(1) <<< (FRAC-1);
    localparam logic signed [AW-1:0] SMAX =  (AW'(1) <<< (DW-1)) - 1;
    localparam logic signed [AW-1:0] SMIN = -(AW'(1) <<< (DW-1));

    logic signed [AW-1:0] rnd;
    assign rnd = (acc_q + HALF) >>> FRAC;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) out_valid <= 1'b0;
        else        out_valid <= done3;

    always_ff @(posedge clk)
        if (done3) begin
            out_acc  <= acc_q;
            out_data <= (rnd > SMAX) ? SMAX[DW-1:0] :
                        (rnd < SMIN) ? SMIN[DW-1:0] : rnd[DW-1:0];
        end
endmodule
