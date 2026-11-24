EXTRA ?= 0
sim:      ; iverilog -g2012 -o sim.out rtl/mac_pipe.v tb/tb_mac_pipe.v && vvp sim.out
sim_sv:   ; iverilog -g2012 -Ptb_mac_pipe.EXTRA=$(EXTRA) -o sim_sv.out sv/mac_pipe.sv tb/tb_mac_pipe_sv.sv && vvp sim_sv.out
synth_y:  ; yosys -s asic/yosys_synth.ys
clean:    ; rm -f sim.out sim_sv.out
