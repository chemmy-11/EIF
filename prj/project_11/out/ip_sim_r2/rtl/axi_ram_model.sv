// =============================================================================
// axi_ram_model.sv -- minimal AXI4 slave RAM for the prj11 R2 AXI DMA IP sim
//
// 512-bit data, 32-bit address, INCR bursts, byte write strobes.  Holds 2 MiB
// so that the 0x0010_0000 slot base used by the board firmware is mapped.
// Memory is initialised to 0xEE so "not written" bytes are distinguishable.
//
// A combinational debug port (dbg_addr/dbg_data) lets the testbench read any
// byte without hierarchical references.
// =============================================================================
`timescale 1ns/1ps

module axi_ram_model #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 512,
    parameter int MEM_BYTES  = 2 * 1024 * 1024
) (
    input  logic                    aclk,
    input  logic                    aresetn,

    // AXI4 write address channel
    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic [7:0]              awlen,
    input  logic [2:0]              awsize,
    input  logic [1:0]              awburst,
    input  logic                    awvalid,
    output logic                    awready,

    // AXI4 write data channel
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [DATA_WIDTH/8-1:0] wstrb,
    input  logic                    wlast,
    input  logic                    wvalid,
    output logic                    wready,

    // AXI4 write response channel
    output logic [1:0]              bresp,
    output logic                    bvalid,
    input  logic                    bready,

    // AXI4 read address channel
    input  logic [ADDR_WIDTH-1:0]   araddr,
    input  logic [7:0]              arlen,
    input  logic [2:0]              arsize,
    input  logic [1:0]              arburst,
    input  logic                    arvalid,
    output logic                    arready,

    // AXI4 read data channel
    output logic [DATA_WIDTH-1:0]   rdata,
    output logic [1:0]              rresp,
    output logic                    rlast,
    output logic                    rvalid,
    input  logic                    rready,

    // debug read port (combinational, simulation only)
    input  logic [31:0]             dbg_addr,
    output logic [7:0]              dbg_data
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int WORDS          = MEM_BYTES / BYTES_PER_BEAT;

    // Byte-addressable in effect: each 512-bit word holds 64 bytes.
    logic [DATA_WIDTH-1:0] mem [0:WORDS-1];

    initial begin
        for (int i = 0; i < WORDS; i++) begin
            mem[i] = {BYTES_PER_BEAT{8'hEE}};
        end
    end

    assign dbg_data = mem[dbg_addr[ADDR_WIDTH-1:6]][(dbg_addr[5:0]*8) +: 8];

    // ------------------------------------------------------------------ write
    logic                  w_active;
    logic                  b_pending;
    logic [ADDR_WIDTH-1:0] w_addr;
    logic [7:0]            w_len;
    logic [7:0]            w_cnt;

    assign awready = !w_active && !b_pending;
    assign wready  = w_active;
    assign bvalid  = b_pending;
    assign bresp   = 2'b00;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            w_active  <= 1'b0;
            b_pending <= 1'b0;
            w_addr    <= '0;
            w_len     <= '0;
            w_cnt     <= '0;
        end else begin
            if (awready && awvalid) begin
                w_addr   <= awaddr;
                w_len    <= awlen;
                w_cnt    <= 8'd0;
                w_active <= 1'b1;
                $display("RAM_AW  t=%0t addr=0x%08h len=%0d size=%0d burst=%0d",
                         $time, awaddr, awlen, awsize, awburst);
            end

            if (w_active && wvalid) begin
                for (int i = 0; i < BYTES_PER_BEAT; i++) begin
                    if (wstrb[i]) begin
                        mem[w_addr[ADDR_WIDTH-1:6]][i*8 +: 8] <= wdata[i*8 +: 8];
                    end
                end
                $display("RAM_W   t=%0t addr=0x%08h beat=%0d strb=0x%016h last=%0d data[63:0]=0x%016h data[191:128]=0x%016h",
                         $time, w_addr, w_cnt, wstrb, wlast, wdata[63:0], wdata[191:128]);

                if (wlast) begin
                    w_active  <= 1'b0;
                    b_pending <= 1'b1;
                end else begin
                    w_cnt  <= w_cnt + 8'd1;
                    w_addr <= w_addr + BYTES_PER_BEAT;
                end
            end

            if (b_pending && bready) begin
                b_pending <= 1'b0;
                $display("RAM_B   t=%0t", $time);
            end
        end
    end

    // ------------------------------------------------------------------- read
    logic                  r_active;
    logic                  r_valid_q;
    logic [ADDR_WIDTH-1:0] r_addr;
    logic [7:0]            r_len;
    logic [7:0]            r_cnt;

    assign arready = !r_active && !r_valid_q;
    assign rvalid  = r_valid_q;
    assign rresp   = 2'b00;
    assign rlast   = r_valid_q && (r_cnt == r_len);

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            r_active  <= 1'b0;
            r_valid_q <= 1'b0;
            r_addr    <= '0;
            r_len     <= '0;
            r_cnt     <= '0;
            rdata     <= '0;
        end else begin
            if (arready && arvalid) begin
                r_addr   <= araddr;
                r_len    <= arlen;
                r_cnt    <= 8'd0;
                r_active <= 1'b1;
                $display("RAM_AR  t=%0t addr=0x%08h len=%0d size=%0d burst=%0d",
                         $time, araddr, arlen, arsize, arburst);
            end

            if (r_active && !r_valid_q) begin
                rdata     <= mem[r_addr[ADDR_WIDTH-1:6]];
                r_valid_q <= 1'b1;
            end

            if (r_valid_q && rready) begin
                $display("RAM_R   t=%0t addr=0x%08h beat=%0d last=%0d data[63:0]=0x%016h",
                         $time, r_addr, r_cnt, (r_cnt == r_len), rdata[63:0]);
                if (r_cnt == r_len) begin
                    r_active  <= 1'b0;
                    r_valid_q <= 1'b0;
                end else begin
                    r_cnt     <= r_cnt + 8'd1;
                    r_addr    <= r_addr + BYTES_PER_BEAT;
                    r_valid_q <= 1'b0;
                end
            end
        end
    end

endmodule
