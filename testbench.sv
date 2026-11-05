
`timescale 1ns/1ps

module tb_uart_dual_fifo_top;

    // Test configuration
    localparam CLKS_PER_BIT = 8;
    localparam DEPTH        = 4;
    localparam COUNT_WIDTH  = $clog2(DEPTH + 1);

    // Clock and reset
    logic clk   = 0;
    logic rst_n = 0;

    // TX FIFO inputs
    logic        wr_en = 0;
    logic [7:0]  data_in = 0;

    // TX status
    logic full, empty;
    logic [COUNT_WIDTH-1:0] count;

    // UART TX signals
    logic tx, tx_busy, tx_done;

    // RX FIFO inputs and outputs
    logic rx_rd_en = 0;
    logic [7:0] rx_dout;
    logic rx_full, rx_empty;
    logic [COUNT_WIDTH-1:0] rx_count;

    // UART RX status
    logic rx_done, rx_framing_error;

    // Loopback connection
    wire rx_line = tx;

    // Low-power measurement counters
    integer total_clock_edges = 0;
    integer gated_clock_edges = 0;
    integer errors = 0;
    integer timeout;

    // Device under test
    uart_dual_fifo_top #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .wr_en(wr_en),
        .data_in(data_in),
        .full(full),
        .empty(empty),
        .count(count),

        .tx(tx),
        .tx_busy(tx_busy),
        .tx_done(tx_done),

        .rx(rx_line),
        .rx_rd_en(rx_rd_en),
        .rx_dout(rx_dout),
        .rx_full(rx_full),
        .rx_empty(rx_empty),
        .rx_count(rx_count),

        .rx_done(rx_done),
        .rx_framing_error(rx_framing_error)
    );

    // 10 ns clock period
    always #5 clk = ~clk;

    // Count rising edges of the source clock
    always @(posedge clk)
        total_clock_edges = total_clock_edges + 1;

    // Count rising edges reaching the gated TX clock
    // Requires dut.tx_gated_clk to exist in the design
    always @(posedge dut.tx_gated_clk)
        gated_clock_edges = gated_clock_edges + 1;

    // Push one byte into the TX FIFO
    task automatic send_byte(input logic [7:0] data);
        @(negedge clk);
        data_in = data;
        wr_en   = 1;

        @(negedge clk);
        wr_en   = 0;
    endtask

    // Read one byte from the RX FIFO
    task automatic read_rx_byte(output logic [7:0] data);
        @(negedge clk);
        rx_rd_en = 1;

        @(posedge clk);
        #1;
        data = rx_dout;

        @(negedge clk);
        rx_rd_en = 0;
    endtask

    logic [7:0] received;

    initial begin
        $dumpfile("uart_dual_fifo.vcd");
        $dumpvars(0, tb_uart_dual_fifo_top);

        $display("----------------------------------------");
        $display(" UART TX + RX DUAL FIFO TEST");
        $display(" CLOCK-GATING ACTIVITY MEASUREMENT");
        $display("----------------------------------------");

        errors = 0;

        // Apply reset
        repeat (5) @(negedge clk);
        rst_n = 1;

        repeat (3) @(negedge clk);

        // Check initial FIFO status
        if (!empty || !rx_empty) begin
            $display("FAIL: FIFO should initially be empty");
            errors = errors + 1;
        end else begin
            $display("PASS: Both FIFOs are initially empty");
        end

        // Queue three bytes
        send_byte(8'hA5);
        send_byte(8'h3C);
        send_byte(8'h7F);

        $display("INFO: Three bytes queued for transmission");

        // Wait for all three bytes to reach RX FIFO
        timeout = 0;

        while ((rx_count != 3) && (timeout < 5000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (rx_count != 3) begin
            $display("FAIL: Timeout waiting for received bytes");
            $display("      RX FIFO count = %0d", rx_count);
            errors = errors + 1;
        end else begin
            $display("PASS: All three bytes reached the RX FIFO");

            // Verify byte 1
            read_rx_byte(received);
            if (received !== 8'hA5) begin
                $display("FAIL: Expected A5, received %02h", received);
                errors = errors + 1;
            end else begin
                $display("PASS: Received A5 correctly");
            end

            // Verify byte 2
            read_rx_byte(received);
            if (received !== 8'h3C) begin
                $display("FAIL: Expected 3C, received %02h", received);
                errors = errors + 1;
            end else begin
                $display("PASS: Received 3C correctly");
            end

            // Verify byte 3
            read_rx_byte(received);
            if (received !== 8'h7F) begin
                $display("FAIL: Expected 7F, received %02h", received);
                errors = errors + 1;
            end else begin
                $display("PASS: Received 7F correctly");
            end
        end

        // Allow final status signals to settle
        repeat (5) @(negedge clk);

        if (rx_framing_error) begin
            $display("FAIL: UART framing error detected");
            errors = errors + 1;
        end

        if (!rx_empty) begin
            $display("FAIL: RX FIFO should be empty after reading");
            errors = errors + 1;
        end else begin
            $display("PASS: RX FIFO drained successfully");
        end

        // Allow counters to settle
        repeat (2) @(negedge clk);

        // Report clock activity
        $display("");
        $display("========= LOW-POWER RESULTS =========");
        $display("Source clock rising edges    = %0d",
                 total_clock_edges);
        $display("Gated TX clock rising edges  = %0d",
                 gated_clock_edges);

        if (total_clock_edges > 0) begin
            $display("TX clock edge reduction      = %0.2f%%",
                100.0 * (1.0 -
                (1.0 * gated_clock_edges / total_clock_edges)));
        end

        $display("=====================================");
        $display("NOTE: Edge reduction is not a direct");
        $display("measurement of total power in watts.");
        $display("=====================================");

        if (errors == 0) begin
            $display("");
            $display("ALL UART + FIFO TESTS PASSED!");
        end else begin
            $display("");
            $display("TEST FAILED: %0d error(s)", errors);
            $fatal(1, "UART dual FIFO test failed");
        end

        $finish;
    end

endmodule
