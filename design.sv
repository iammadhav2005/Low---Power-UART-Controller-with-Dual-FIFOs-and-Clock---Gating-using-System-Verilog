// Code your design here
`timescale 1ns/1ps
module uart_tx #(
    parameter CLKS_PER_BIT = 100
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx,
    output logic       tx_busy,
    output logic       tx_done
);
    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;
    state_t state;
    logic [7:0] shift_reg;
    integer baud_count;
    integer bit_index;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            tx         <= 1'b1;
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
            shift_reg  <= 8'b0;
            baud_count <= 0;
            bit_index  <= 0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        shift_reg  <= tx_data;
                        tx         <= 1'b0;  // Start bit
                        tx_busy    <= 1'b1;
                        baud_count <= 0;
                        bit_index  <= 0;
                        state      <= START;
                    end
                end
                START: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 0;
                        tx         <= shift_reg[0];
                        shift_reg  <= shift_reg >> 1;
                        bit_index  <= 1;
                        state      <= DATA;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                DATA: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 0;

                        if (bit_index == 8) begin
                            tx    <= 1'b1;  // Stop bit
                            state <= STOP;
                        end else begin
                            tx        <= shift_reg[0];
                            shift_reg <= shift_reg >> 1;
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                STOP: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 0;
                        tx_busy    <= 1'b0;
                        tx_done    <= 1'b1;
                        state      <= IDLE;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                default: begin
                    state <= IDLE;
                    tx    <= 1'b1;
                end
            endcase
        end
    end

endmodule

// Code your design here

module uart_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter COUNT_WIDTH = $clog2(DEPTH + 1)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic wr_en,
    input  logic rd_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout,
    output logic full,
    output logic empty,
    output logic [COUNT_WIDTH-1:0] count
);
  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1]; //16 memory locations and each stores 8 bits of data
  logic [ADDR_WIDTH-1:0] wr_ptr;//write pointer
  logic [ADDR_WIDTH-1:0] rd_ptr;//read pointer
  wire do_write = wr_en && !full;//condition for writing
  wire do_read  = rd_en && !empty;//condition for reading
  assign full  = (count == DEPTH);
  assign empty = (count == 0);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            dout   <= '0;
            count  <= '0;
        end else begin
            // Write new data
            if (do_write) begin
                mem[wr_ptr] <= din;
                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end
            // Read oldest data
            if (do_read) begin
                dout <= mem[rd_ptr];
                if (rd_ptr == DEPTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end
            // Update occupancy
            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule



module uart_dual_fifo_top #(
    parameter CLKS_PER_BIT = 100,
    parameter DATA_WIDTH   = 8,
    parameter DEPTH        = 16,
    parameter COUNT_WIDTH  = $clog2(DEPTH + 1)
)(
    input logic clk,
    input logic rst_n,

    // TX input interface
    input logic       wr_en,
    input logic [7:0] data_in,

    output logic full,
    output logic empty,
    output logic [COUNT_WIDTH-1:0] count,

    // TX serial output
    output logic tx,
    output logic tx_busy,
    output logic tx_done,

    // RX serial input
    input logic rx,

    // RX FIFO output interface
    input logic rx_rd_en,
    output logic [7:0] rx_dout,
    output logic rx_full,
    output logic rx_empty,
    output logic [COUNT_WIDTH-1:0] rx_count,

    // RX status
    output logic rx_done,
    output logic rx_framing_error
);

    // TX-side internal signals
    logic [7:0] tx_fifo_dout;
    logic tx_fifo_rd_en;
    logic tx_start;

    // RX-side internal signals
    logic [7:0] received_data;
    logic rx_fifo_wr_en;
  
  logic tx_gated_clk;
logic tx_clk_enable;
  
  // Keep the TX clock active when starting or during transmission
assign tx_clk_enable = tx_start || tx_busy;

uart_clock_gate u_tx_clock_gate (
    .clk       (clk),
    .enable    (tx_clk_enable),
    .gated_clk (tx_gated_clk)
);

    // ------------------------------------
    // 1. TX FIFO
    // ------------------------------------
    uart_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) tx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .rd_en(tx_fifo_rd_en),
        .din(data_in),
        .dout(tx_fifo_dout),
        .full(full),
        .empty(empty),
        .count(count)
    );

    // ------------------------------------
    // 2. UART transmitter
    // ------------------------------------
    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) transmitter (
        .clk(tx_gated_clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_fifo_dout),
        .tx(tx),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // ------------------------------------
    // 3. TX controller
    // ------------------------------------
    typedef enum logic [1:0] {
        TX_IDLE,
        TX_POP_FIFO,
        TX_START,
        TX_WAIT_DONE
    } tx_ctrl_state_t;

    tx_ctrl_state_t tx_ctrl_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_ctrl_state <= TX_IDLE;
            tx_fifo_rd_en <= 1'b0;
            tx_start      <= 1'b0;
        end else begin
            tx_fifo_rd_en <= 1'b0;
            tx_start      <= 1'b0;

            case (tx_ctrl_state)

                TX_IDLE: begin
                    if (!empty && !tx_busy) begin
                        tx_fifo_rd_en <= 1'b1;
                        tx_ctrl_state <= TX_POP_FIFO;
                    end
                end

                TX_POP_FIFO: begin
                    tx_ctrl_state <= TX_START;
                end

                TX_START: begin
                    tx_start <= 1'b1;
                    tx_ctrl_state <= TX_WAIT_DONE;
                end

                TX_WAIT_DONE: begin
                    if (tx_done)
                        tx_ctrl_state <= TX_IDLE;
                end

                default: tx_ctrl_state <= TX_IDLE;

            endcase
        end
    end

    // ------------------------------------
    // 4. UART receiver
    // ------------------------------------
    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) receiver (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .rx_data(received_data),
        .rx_done(rx_done),
        .rx_framing_error(rx_framing_error)
    );

    // ------------------------------------
    // 5. RX FIFO
    // ------------------------------------
    // rx_done is registered by uart_rx.
    // The FIFO writes the completed byte on
    // the following clock edge.
    assign rx_fifo_wr_en = rx_done && !rx_full;

    uart_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) rx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(rx_fifo_wr_en),
        .rd_en(rx_rd_en),
        .din(received_data),
        .dout(rx_dout),
        .full(rx_full),
        .empty(rx_empty),
        .count(rx_count)
    );

endmodule

module uart_rx #(
    parameter CLKS_PER_BIT = 100
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,

    output logic [7:0] rx_data,
    output logic       rx_done,
    output logic       rx_framing_error
);

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state;

    logic [7:0] shift_reg;
    integer baud_count;
    integer bit_index;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            shift_reg        <= 8'b0;
            baud_count       <= 0;
            bit_index        <= 0;
            rx_data          <= 8'b0;
            rx_done          <= 1'b0;
            rx_framing_error <= 1'b0;
        end else begin
            rx_done          <= 1'b0;
            rx_framing_error <= 1'b0;

            case (state)

                IDLE: begin
                    baud_count <= 0;
                    bit_index  <= 0;

                    // UART idle is high; low indicates a start bit
                    if (rx == 1'b0)
                        state <= START;
                end

                START: begin
                    // Check the middle of the start bit
                    if (baud_count == (CLKS_PER_BIT/2) - 1) begin
                        baud_count <= 0;

                        if (rx == 1'b0) begin
                            state <= DATA;
                            bit_index <= 0;
                        end else begin
                            // False start
                            state <= IDLE;
                        end
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end

                DATA: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 0;

                        // Sample data least-significant bit first
                        shift_reg[bit_index] <= rx;

                        if (bit_index == 7) begin
                            bit_index <= 0;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end

                STOP: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 0;
                        state <= IDLE;

                        if (rx == 1'b1) begin
                            rx_data <= shift_reg;
                            rx_done <= 1'b1;
                        end else begin
                            rx_framing_error <= 1'b1;
                        end
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end

                default: begin
                    state <= IDLE;
                    baud_count <= 0;
           
                end

            endcase
        end
    end

endmodule

module uart_clock_gate (
    input  logic clk,
    input  logic enable,
    output logic gated_clk
);

    logic enable_latched;

    // Capture enable only while the source clock is LOW.
    // This prevents enable changes from creating clock glitches.
    always_latch begin
        if (!clk)
            enable_latched <= enable;
    end

    assign gated_clk = clk & enable_latched;

endmodule

