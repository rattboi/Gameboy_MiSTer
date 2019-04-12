#include "Vlink.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char **argv, char **env) {
  int i;
  int clk;

  Verilated::commandArgs(argc, argv);

  // init top verilog instance
  Vlink* top = new Vlink;

  // init trace dump
  Verilated::traceEverOn(true);
  VerilatedVcdC* tfp = new VerilatedVcdC;
  top->trace (tfp, 5000);
  tfp->open ("link.vcd");

  // initialize simulation inputs
  top->clk = 1;
  top->rst = 1;
  top->sb_in = 0xCC;

  top->sel_sc           = 0;
  top->cpu_wr_n         = 1;
  top->sc_start_in      = 0;
  top->sc_int_clock_in = 0;

  top->serial_clk_in    = 0;
  top->serial_data_in   = 0;

  // run simulation for 100 clock periods
  for (i=0; i<5000; i++) {
    top->rst = (i < 2);
    // dump variables into VCD file and toggle clock
    for (clk=0; clk<2; clk++) {
      tfp->dump (2*i+clk);
      top->clk = !top->clk;
      top->eval ();
    }
    top->sel_sc = (i == 2);
    top->cpu_wr_n = !(i == 2);

    top->sc_int_clock_in = (i >= 2);
    top->sc_start_in = (i >= 2);
    top->serial_clk_in = !top->serial_clk_in;

    if (Verilated::gotFinish())  exit(0);
  }
  tfp->close();
  exit(0);
}
