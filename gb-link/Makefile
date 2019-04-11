MODULE=link
VMODULE=V$(MODULE)

VMODULE_OBJ_DIR=obj_dir

run: $(VMODULE_OBJ_DIR)/$(VMODULE)
	$(VMODULE_OBJ_DIR)/$(VMODULE)

vcd: $(MODULE).vcd
	vcd -w=3 $(MODULE).vcd

$(VMODULE_OBJ_DIR)/$(VMODULE): $(MODULE).v $(MODULE)_tb.cpp
	verilator -Wall --cc --trace $(MODULE).v --exe $(MODULE)_tb.cpp
	make -C $(VMODULE_OBJ_DIR) -j -f $(VMODULE).mk $(VMODULE)

clean:
	rm -rf $(VMODULE_OBJ_DIR) 
	rm -f  $(MODULE).vcd
