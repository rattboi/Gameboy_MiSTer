// Gameboy for the MiST
// (c) 2015 Till Harbaum

// The gameboy lcd runs from a shift register which is filled at 4194304 pixels/sec

module lcd (
	// pixel clock
   input        pclk,
   input        pce,
	input        clk,

	input        clkena1,
	input [14:0] data1,
	input [1:0]  mode1,
	input        on1,

	input        clkena2,
	input [14:0] data2,
	input [1:0]  mode2,
	input        on2,

	input isGBC,
	
	//palette
	input [23:0] pal1,
	input [23:0] pal2,
	input [23:0] pal3,
	input [23:0] pal4,

	input tint,
	input inv,

	
   // VGA output
   output reg	hs,
   output reg 	vs,
   output reg 	blank,
   output [7:0] r,
   output [7:0] g,
   output [7:0] b
);

reg [14:0] vbuffer1_inptr;
reg [14:0] vbuffer2_inptr;

reg [14:0] vbuffer_outptr;
reg [14:0] vbuffer_lineptr;

dpram #(15,15) vbuffer1 (
	.clock_a (clk),
	.address_a (vbuffer1_inptr),
	.wren_a (clkena1),
	.data_a (data1),
	.q_a (),
	
	.clock_b (pclk),
	.address_b (vbuffer_outptr),
	.wren_b (1'b0), //only reads
	.data_b (),
	.q_b (pixel_reg1)
);

always @(posedge clk) begin
	if(!on1 || (mode1==2'd01)) begin  //lcd disabled or vsync restart pointer
	   vbuffer1_inptr <= 15'h0;
	end else begin
		// end of vsync
		if(clkena1) begin
			vbuffer1_inptr <= vbuffer1_inptr + 15'd1;
		end
	end
end

dpram #(15,15) vbuffer2 (
	.clock_a (clk),
	.address_a (vbuffer2_inptr),
	.wren_a (clkena2),
	.data_a (data2),
	.q_a (),
	
	.clock_b (pclk),
	.address_b (vbuffer_outptr),
	.wren_b (1'b0), //only reads
	.data_b (),
	.q_b (pixel_reg2)
);

always @(posedge clk) begin
	if(!on2 || (mode2==2'd01)) begin  //lcd disabled or vsync restart pointer
	   vbuffer2_inptr <= 15'h0;
	end else begin
		// end of vsync
		if(clkena2) begin
			vbuffer2_inptr <= vbuffer2_inptr + 15'd1;
		end
	end
end

// Mode 00:  h-blank
// Mode 01:  v-blank
// Mode 10:  oam
// Mode 11:  oam and vram	

// 
parameter H   = 320;    // width of visible area
parameter HFP = 32; //16;     // unused time before hsync
parameter HS  = 40; //20;     // width of hsync
parameter HBP = 64; //32;     // unused time after hsync
// total = 228

parameter V   = 576;    // height of visible area
parameter VFP = 2;      // unused time before vsync
parameter VS  = 2;      // width of vsync
parameter VBP = 36;     // unused time after vsync
// total = 616

reg[8:0] h_cnt;         // horizontal pixel counter
reg[9:0] v_cnt;         // vertical pixel counter

// horizontal pixel counter
always@(posedge pclk) begin
	if(pce) begin
		
		if(h_cnt==H+HFP+HS+HBP-1)   h_cnt <= 0;
		else                        h_cnt <= h_cnt + 1'd1;

		// generate positive hsync signal
		if(h_cnt == H+HFP)    hs <= 1'b1;
		if(h_cnt == H+HFP+HS) hs <= 1'b0;

	end
end

// vertical pixel counter
always@(posedge pclk) begin
	if(pce) begin
		// the vertical counter is processed at the begin of each hsync
		if(h_cnt == H+HFP+HS+HBP-1) begin
			if(v_cnt==VS+VFP+V+VBP-1)  v_cnt <= 0; 
			else							   v_cnt <= v_cnt + 1'd1;

			// generate positive vsync signal
			if(v_cnt == V+VFP)    vs <= 1'b1;
			if(v_cnt == V+VFP+VS) vs <= 1'b0;
		end
	end
end

// -------------------------------------------------------------------------------
// ------------------------------- pixel generator -------------------------------
// -------------------------------------------------------------------------------
reg [14:0] pixel_reg1;
reg [14:0] pixel_reg2;

always@(posedge pclk) begin
	if(pce) begin
		// visible area?
		if((v_cnt < V) && (h_cnt < H)) begin
			blank <= 1'b0;
		end else begin
			blank <= 1'b1;
		end
	end
end

reg [7:0] currentpixel;
reg [1:0] linecnt;

always@(posedge pclk) begin
	if(pce) begin
		if(h_cnt == H+HFP+HS+HBP-1) begin
			//reset output at vsync
			if(v_cnt == V+VFP) begin
				vbuffer_outptr 	<= 15'd0; 
				vbuffer_lineptr	<= 15'd0;
				currentpixel		<=	8'd0;
				linecnt <= 2'd3;
			end
		end else
			// visible area?
			if((v_cnt < V) && (h_cnt < H)) begin
				vbuffer_outptr <= vbuffer_lineptr + currentpixel; 
				if (currentpixel + 8'd1 == 160) begin
					currentpixel <= 8'd0;
					linecnt <= linecnt - 2'd1;
					
					//increment vbuffer_lineptr after 4 lines
					if (!linecnt)
						vbuffer_lineptr <= vbuffer_lineptr + 15'd160;
				end else
					currentpixel <= currentpixel + 8'd1;
			end
	end
end

wire [14:0] pixel = (h_cnt < 160) ? 
              (on1 ? {13'd0,(pixel_reg1[1:0] ^ {inv,inv})} : 15'd0) :
              (on2 ? {13'd0,(pixel_reg2[1:0] ^ {inv,inv})} : 15'd0);
							  
wire [4:0] r5 = (h_cnt < 160) ? 
                  pixel_reg1[4:0] :
                  pixel_reg2[4:0];
wire [4:0] g5 = (h_cnt < 160) ? 
                  pixel_reg1[9:5] :
                  pixel_reg2[9:5];
wire [4:0] b5 = (h_cnt < 160) ? 
                  pixel_reg1[14:10] :
                  pixel_reg2[14:10];

wire [31:0] r10 = (r5 * 13) + (g5 * 2) +b5;
wire [31:0] g10 = (g5 * 3) + b5;
wire [31:0] b10 = (r5 * 3) + (g5 * 2) + (b5 * 11);

// gameboy "color" palette
wire [7:0] pal_r = isGBC?r10[8:1]:
                   (pixel==0)?pal1[23:16]:
						 (pixel==1)?pal2[23:16]:
						 (pixel==2)?pal3[23:16]:
						 pal4[23:16];

wire [7:0] pal_g = isGBC?{g10[6:0],1'b0}:
                   (pixel==0)?pal1[15:8]:
                   (pixel==1)?pal2[15:8]:
						 (pixel==2)?pal3[15:8]:
						 pal4[15:8];
						 
wire [7:0] pal_b = isGBC?b10[8:1]:
						 (pixel==0)?pal1[7:0]:
                   (pixel==1)?pal2[7:0]:
						 (pixel==2)?pal3[7:0]:
						 pal4[7:0];

// greyscale
wire [7:0] grey = (pixel==0)?8'd252:(pixel==1)?8'd168:(pixel==2)?8'd96:8'd0;
assign r = blank?8'd0:tint||isGBC?pal_r:grey;
assign g = blank?8'd0:tint||isGBC?pal_g:grey;
assign b = blank?8'd0:tint||isGBC?pal_b:grey;

endmodule
