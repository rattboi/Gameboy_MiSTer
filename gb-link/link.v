module link #(
  parameter CLK_DIV = 511
)(
  // system signals
  input clk,
  input rst,

  input sel_sc,
  input cpu_wr_n,
  input sc_start_in,
  input sc_int_clock_in,

  input [7:0] sb_in,

  input serial_clk_in,
  input serial_data_in,

  output serial_clk_out,
  output serial_data_out,
  output sb,
  output serial_irq
);

wire [7:0] sb = sb_r;

reg [3:0] serial_counter;
reg sc_start,sc_int_clock;

reg [7:0] sb_r = 0;

reg serial_out_r = 0;
assign serial_data_out = serial_out_r;

reg serial_clk_out_r = 1;
assign serial_clk_out = serial_clk_out_r;

reg serial_irq;
reg [8:0] serial_clk_div; //8192Hz

reg serial_clk_in_last;

// serial master
always @(posedge clk) begin
	serial_irq <= 1'b0;
   if(rst) begin
		  sc_start <= 1'b0;
		  sc_int_clock <= 1'b0;
        sb_r <= sb_in;
        serial_clk_in_last <= serial_clk_in;
	end else if (sel_sc && !cpu_wr_n) begin     //cpu write
		sc_start <= sc_start_in;
		sc_int_clock <= sc_int_clock_in;
		if (sc_start_in) begin                   //enable transfer
			serial_clk_div <= CLK_DIV;
			serial_counter <= 4'd8;
			serial_clk_out_r <= 1'b1;
		end 
	end else if (sc_start) begin // serial transfer
      if (sc_int_clock) begin   // internal clock
         serial_clk_div <= serial_clk_div - 9'd1;

         if (serial_counter != 0) begin
            if (serial_clk_div == (CLK_DIV/2)+1) begin
               serial_clk_out_r <= ~serial_clk_out_r;
               serial_out_r <= sb[7];
               sb_r <= {sb[6:0], serial_data_in};
            end else if (serial_clk_div == 0) begin
               serial_clk_out_r <= ~serial_clk_out;
               serial_counter <= serial_counter - 1;
               serial_clk_div <= CLK_DIV;
            end
         end else begin
            serial_irq <= 1'b1;
            sc_start <= 1'b0;
            serial_clk_div <= CLK_DIV;
            serial_counter <= 4'd8;
         end
      end else begin  // external clock
         serial_clk_in_last <= serial_clk_in;
         if (serial_clk_in_last != serial_clk_in && serial_clk_in == 1) begin
            if (serial_counter != 0) begin
               serial_out_r <= sb[7];
               sb_r <= {sb[6:0], serial_data_in};
               serial_counter <= serial_counter - 1;
            end else begin
               serial_irq <= 1'b1;
               sc_start <= 1'b0;
               serial_counter <= 4'd8;
            end
         end
      end
  end
end

endmodule
// vim:sw=3:ts=3:et:
