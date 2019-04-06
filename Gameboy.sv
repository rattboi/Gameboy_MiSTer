//============================================================================
//  Gameboy
//  Copyright (c) 2015 Till Harbaum <till@harbaum.org>  
//
//  Port to MiSTer
//  Copyright (C) 2017,2018 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..5 - USR1..USR4
	// Set USER_OUT to 1 to read from USER_IN.
	input   [5:0] USER_IN,
	output  [5:0] USER_OUT,

	input         OSD_STATUS
);

assign USER_OUT = '1;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0; 
assign VGA_F1 = 0;

assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_USER  = ioctl_download; // | sav_pending;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[4:3] == 2'b10 ? 8'd16:
						 status[4:3] == 2'b01 ? 8'd10:
						 8'd4;
						 
assign VIDEO_ARY = status[4:3] == 2'b10 ? 8'd9:
						 status[4:3] == 2'b01 ? 8'd9:
						 8'd3;

assign AUDIO_MIX = status[8:7];

//`include "build_id.v" 
`define BUILD_DATE "asdf"

localparam CONF_STR1 = {
	"GAMEBOY;;",
	"-;",
	"FS,GBCGB ,Load ROM;",
	"OEF,System,Auto,Gameboy,Gameboy Color;",
	"-;",
	"OC,Inverted color,No,Yes;",
	"O1,Palette,Grayscale,Custom;"
};

localparam CONF_STR2 = {
	",GBP,Load Palette;",
	"-;",
	"OD,OSD triggered autosaves,No,Yes;",
};

localparam CONF_STR3 = {
	"9,Load Backup RAM;"
};

localparam CONF_STR4 = {
	"A,Save Backup RAM;",
	"-;",
	"O34,Aspect ratio,4:3,10:9,16:9;",
	"O78,Stereo mix,none,25%,50%,100%;",
	"-;",
	"R0,Reset;",
	"J1,A,B,Select,Start;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire pll_locked;
		
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(SDRAM_CLK),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
reg         ioctl_wait;

wire [15:0] joystick_0, joystick_1;
wire [7:0]  filetype;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire [7:0] sav_char = "+"; //sav_supported ? "R" : "+";

hps_io #(.STRLEN(($size(CONF_STR1)>>3) + ($size(CONF_STR2)>>3) + ($size(CONF_STR3)>>3) + ($size(CONF_STR4)>>3) + 3), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str({CONF_STR1,status[1]?"F":"+",CONF_STR2, sav_char, CONF_STR3, sav_char, CONF_STR4}),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.ioctl_index(filetype),
	
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.buttons(buttons),
	.status(status),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

///////////////////////////////////////////////////

wire cart_download = ioctl_download && (filetype == 8'h01 || filetype == 8'h41 || filetype == 8'h80);
wire palette_download = ioctl_download && (filetype == 8'h05 || filetype == 8'h00);
wire bios_download = ioctl_download && (filetype == 8'h40);

wire [15:0] sdram_do, sdram_do_gb2;
wire [15:0] sdram_di = cart_download ? ioctl_dout : 16'd0;
wire [23:0] sdram_addr = cart_download ? 
				ioctl_addr[24:1] : 
				{2'b00, cart_if1_mbc_bank, cart_addr_gb1[12:1]};
wire [23:0] sdram_addr_gb2 = 
			   {2'b00, cart_if2_mbc_bank, cart_addr_gb2[12:1]};

wire sdram_we = cart_download & dn_write;

assign SDRAM_CKE = 1;

dpram #(16, 16) sdram (
	.clock_a (clk_cpu2x),
	.address_a (sdram_addr),
	.wren_a (sdram_we),
	.data_a (sdram_di),
	.q_a (sdram_do),
	
	.clock_b (clk_cpu2x),
	.address_b (sdram_addr_gb2),
	.wren_b (0),
	.data_b (0),
	.q_b (sdram_do_gb2)
);

reg cart_ready = 0;
reg dn_write;
always @(posedge clk_sys) begin
	if(ioctl_wr) ioctl_wait <= 1;

	if(speed?ce_cpu2x:ce_cpu) begin
		dn_write <= ioctl_wait;
		if(dn_write) {ioctl_wait, dn_write} <= 0;
		if(dn_write) cart_ready <= 1;
	end
end


wire isGBC_game = (cart_cgb_flag == 8'h80 || cart_cgb_flag == 8'hC0);

reg [127:0] palette = 128'h828214517356305A5F1A3B4900000000;

always @(posedge clk_sys) begin
	if(!pll_locked) begin
		cart_mbc_type <= 8'h00;
		cart_rom_size <= 8'h00;
		cart_ram_size <= 8'h00;
	end else begin
		if(cart_download & ioctl_wr) begin
			case(ioctl_addr)
			   'h142: cart_cgb_flag <= ioctl_dout[15:8];
				'h146: cart_mbc_type <= ioctl_dout[15:8];
				'h148: { cart_ram_size, cart_rom_size } <= ioctl_dout;
			endcase
		end 
	end
	if (palette_download & ioctl_wr) begin
			palette[127:0] <= {palette[111:0], ioctl_dout[7:0], ioctl_dout[15:8]};
	end
end

assign AUDIO_S = 0;

wire reset = (RESET | status[0] | buttons[1] | cart_download); //| bk_loading);
wire speed;

reg isGBC = 0;
always @(posedge clk_sys) if(reset) isGBC <= status[15:14] ? status[15] : !filetype[7:4];

// extract header fields extracted from cartridge
// during download
reg [7:0] cart_mbc_type;
reg [7:0] cart_rom_size;
reg [7:0] cart_ram_size;
reg [7:0] cart_cgb_flag;

wire [7:0] cart_if1_do;
wire [15:0] cart_addr_gb1;
wire [7:0] cart_di_gb1;    // data from cpu to cart
wire cart_rd_gb1;
wire cart_wr_gb1;

wire [9:0] cart_if1_mbc_bank;

cart gb_cart_if_1(
   .reset( reset ),
   .clk_sys( clk_sys ),
	.clk_cpu2x( clk_cpu2x ),
	
	.ce_cpu2x( ce_cpu2x ),
	.cart_ready( cart_ready),

	.cart_mbc_type( cart_mbc_type ),
	.cart_rom_size( cart_rom_size ),
	.cart_ram_size( cart_ram_size ),
	
	.sdram_do ( sdram_do ),
	
	.cart_addr( cart_addr_gb1 ),
	.cart_rd( cart_rd_gb1 ),
	.cart_wr( cart_wr_gb1 ),
	.cart_di( cart_di_gb1 ),
	.cart_do( cart_if1_do ),
	
	.mbc_bank ( cart_if1_mbc_bank )
);


wire lcd_clkena;
wire [14:0] lcd_data;
wire [1:0] lcd_mode;
wire lcd_on;

// the gameboy itself
gb gb (
	.reset	    ( reset      ),
	.clk         ( clk_cpu    ),   // the whole gameboy runs on 4mhnz
	.clk2x       ( clk_cpu2x  ),   // ~8MHz in dualspeed mode (GBC)

	.fast_boot   ( 0          ),
	.joystick    ( joystick_0 ),
	.isGBC       ( isGBC      ),
	.isGBC_game  ( isGBC_game ),

	// interface to the "external" game cartridge
	.cart_addr   ( cart_addr_gb1 ),
	.cart_rd     ( cart_rd_gb1 ),
	.cart_wr     ( cart_wr_gb1 ),
	.cart_do     ( cart_if1_do ),
	.cart_di     ( cart_di_gb1 ),
	
	//gbc bios interface
	.gbc_bios_addr   ( bios_addr_gb1  ),
	.gbc_bios_do     ( bios_do_gb1    ),

	// audio
	.audio_l 	 ( AUDIO_L	  ),
	.audio_r 	 ( AUDIO_R	  ),
	
	// interface to the lcd
	.lcd_clkena  ( lcd_clkena ),
	.lcd_data    ( lcd_data   ),
	.lcd_mode    ( lcd_mode   ),
	.lcd_on      ( lcd_on     ),
	.speed       ( speed      )
);

wire [7:0] cart_if2_do;
wire [15:0] cart_addr_gb2;
wire [7:0] cart_di_gb2;    // data from cpu to cart
wire cart_rd_gb2;
wire cart_wr_gb2;

wire [9:0] cart_if2_mbc_bank;

cart gb_cart_if_2(
   .reset( reset ),
   .clk_sys( clk_sys ),
	.clk_cpu2x( clk_cpu2x ),
	
	.ce_cpu2x( ce_cpu2x ),
	.cart_ready( cart_ready ),

	.cart_mbc_type( cart_mbc_type ),
	.cart_rom_size( cart_rom_size ),
	.cart_ram_size( cart_ram_size ),
	
	.sdram_do ( sdram_do ),
	
	.cart_addr( cart_addr_gb2 ),
	.cart_rd( cart_rd_gb2 ),
	.cart_wr( cart_wr_gb2 ),
	.cart_di( cart_di_gb1 ),
	.cart_do( cart_if2_do ),
	
	.mbc_bank ( cart_if2_mbc_bank )
);

// the gameboy itself
gb gb2 (
	.reset	    ( reset      ),
	.clk         ( clk_cpu    ),   // the whole gameboy runs on 4mhnz
	.clk2x       ( clk_cpu2x  ),   // ~8MHz in dualspeed mode (GBC)

	.fast_boot   ( 0          ),
	.joystick    ( joystick_1 ),
	.isGBC       ( isGBC      ),
	.isGBC_game  ( isGBC_game ),

	// interface to the "external" game cartridge
	.cart_addr   ( cart_addr_gb2 ),
	.cart_rd     ( cart_rd_gb2 ),
	.cart_wr     ( cart_wr_gb2 ),
	.cart_do     ( cart_if2_do ),
	.cart_di     ( cart_di_gb2 ),
	
	//gbc bios interface
	.gbc_bios_addr   ( bios_addr_gb2  ),
	.gbc_bios_do     ( bios_do_gb2    ),

	// audio
	.audio_l 	 ( debug_data[63:48] ), //AUDIO_L	  ),
	.audio_r 	 ( debug_data[47:32] ), //AUDIO_R	  ),
	
	// interface to the lcd
	.lcd_clkena  ( debug_data[31] ), //lcd_clkena ),
	.lcd_data    ( debug_data[30:16] ), //lcd_data   ),
	.lcd_mode    ( debug_data[15:14] ), //lcd_mode   ),
	.lcd_on      ( debug_data[13] ), //lcd_on     ),
	.speed       ( debug_data[12] ) //speed      )
);

// the lcd to vga converter
wire [7:0] video_r, video_g, video_b;
wire video_hs, video_vs, video_bl;

lcd lcd (
	 .pclk   ( clk_sys_old),
	 .pce    ( ce_pix     ),
	 .clk    ( clk_cpu    ),
	 .isGBC  ( isGBC      ),

	 .tint   ( status[1]  ),
	 .inv    ( status[12]  ),

	 // Palettes
	 .pal1   (palette[127:104]),
	 .pal2   (palette[103:80]),
	 .pal3   (palette[79:56]),
	 .pal4   (palette[55:32]),

	 // serial interface
	 .clkena ( lcd_clkena ),
	 .data   ( lcd_data   ),
	 .mode   ( lcd_mode   ),  // used to detect begin of new lines and frames
	 .on     ( lcd_on     ),
	 
  	 .hs     ( video_hs   ),
	 .vs     ( video_vs   ),
	 .blank  ( video_bl   ),
	 .r      ( video_r    ),
	 .g      ( video_g    ),
	 .b      ( video_b    )
);

assign VGA_SL = 0;
assign VGA_R  = video_r;
assign VGA_G  = video_g;
assign VGA_B  = video_b;
assign VGA_DE = ~video_bl;
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = ce_pix & !line_cnt;
assign VGA_HS = video_hs;
assign VGA_VS = video_vs;

wire clk_sys_old =  clk_sys & ce_sys;
wire ce_cpu2x = ce_pix;
wire clk_cpu = clk_sys & ce_cpu;
wire clk_cpu2x = clk_sys & ce_pix;

reg ce_pix, ce_cpu,ce_sys;
always @(negedge clk_sys) begin
	reg [3:0] div = 0;

	div <= div + 1'd1;
	ce_sys   <= !div[0];
	ce_pix   <= !div[2:0];
	ce_cpu   <= !div[3:0];
end


///////////////////////////// GBC BIOS /////////////////////////////////

wire [7:0] bios_do_gb1, bios_do_gb2;
wire [11:0] bios_addr_gb1, bios_addr_gb2;

dpram_dif #(12,8,11,16) boot_rom_gbc_1 (
	.clock (clk_sys),
	
	.address_a (bios_addr_gb1),
	.wren_a (),
	.data_a (),
	.q_a (bios_do_gb1),
	
	.address_b (ioctl_addr[11:1]),
	.wren_b (ioctl_wr && bios_download),
	.data_b (ioctl_dout),
	.q_b ()
);

wire [7:0] bios_do;
wire [11:0] bios_addr;

dpram_dif #(12,8,11,16) boot_rom_gbc_2 (
	.clock (clk_sys),
	
	.address_a (bios_addr_gb2),
	.wren_a (),
	.data_a (),
	.q_a (bios_do_gb2),
	
	.address_b (ioctl_addr[11:1]),
	.wren_b (ioctl_wr && bios_download),
	.data_b (ioctl_dout),
	.q_b ()
);




reg [1:0] line_cnt;
always @(posedge clk_sys_old) begin
	reg old_hs;
	reg old_vs;

	old_vs <= video_vs;
	old_hs <= video_hs;

	if(old_hs & ~video_hs) line_cnt <= line_cnt + 1'd1;
	if(old_vs & ~video_vs) line_cnt <= 0;
end

// used to force outputs to live (just debugging)

reg [63:0] debug_data;

spram #(1,64) tempram (
    .clock      ( clk_cpu        ),
    .address    ( 0      ),
    .wren       ( 1      ),
    .data       ( debug_data ),
    .q          (         )
);

endmodule
