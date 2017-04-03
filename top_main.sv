`include "Sysbus.defs"
`include "Opcodes.defs"
`include "process_instruction.sv"
`include "instruction_types.defs"
`include "get_output_string.sv"
`include "decode.sv"

module top
#(
  BUS_DATA_WIDTH = 64,
  BUS_TAG_WIDTH = 13,
  REGISTER_NAME_WIDTH = 4,
  REGISTER_NUMBER_WIDTH = 5,
  REGISTER_WIDTH = 64,
  IMMEDIATE_WIDTH = 32,
  FLAG_WIDTH = 16,
  INSTRUCTION_NAME_WIDTH = 12,
  PTESIZE = 8
)
(
  input  clk,
         reset,

  // 64-bit address of the program entry point
  input  [63:0] entry,
  input  [63:0] stackptr,
  
  // interface to connect to the bus
  output bus_reqcyc,//set when sending a request
  output bus_respack,//set after receiving data rom the dram
  output [BUS_DATA_WIDTH-1:0] bus_req,//pc value
  output [BUS_TAG_WIDTH-1:0] bus_reqtag,//READ OR MEMORY
  input  bus_respcyc,//if tx_queue is not empty respcyc is set
  input  bus_reqack,
  input  [BUS_DATA_WIDTH-1:0] bus_resp,//bus_resp contains data
  input  [BUS_TAG_WIDTH-1:0] bus_resptag
);

  logic [63:0] pc;
  logic [63:0] npc;
  logic [63:0] prev_pc;
  logic [8:0] counter;
  logic [BUS_TAG_WIDTH-1:0] tag;
  logic [8:0] ncounter;
  logic [REGISTER_NAME_WIDTH*8:0] rs1;
  logic [REGISTER_NAME_WIDTH*8:0] rs2;
  logic [REGISTER_NAME_WIDTH*8:0] rd;
  logic signed [IMMEDIATE_WIDTH-1:0] imm;
  logic unsigned [FLAG_WIDTH-1: 0] flag;
  logic [INSTRUCTION_NAME_WIDTH*8:0] instruction_name;
  logic [BUS_DATA_WIDTH/2 -1:0] nstage1_instruction_bits;
  logic alternator;
  logic nalternator;
  logic nbus_respack;
  logic [63:0] nstage1_pc;
  logic [63:0] stage1_pc;
  logic [63:0] nstage2_valA;
  logic [63:0] nstage2_valB;
  logic [63:0] nstage2_immediate;
  logic [63:0] nstage2_pc;
  logic [4:0] nstage2_dest;
  logic [INSTRUCTION_NAME_WIDTH*8:0] nstage2_op;
  logic [REGISTER_WIDTH-1:0] nstage3_alu_result;
  logic [REGISTER_WIDTH-1:0] nstage3_rs2_val;
  logic [REGISTER_NUMBER_WIDTH:0] nstage3_rd;
  logic [INSTRUCTION_NAME_WIDTH*8:0] nstage3_opcode_name;
  logic [BUS_DATA_WIDTH-1:0] nstage3_pc;
  logic wr_en;
  logic display_regs;
// for virtual to physical translation
  logic paddr_set;
  logic [2:0] level;
  logic [2:0] nlevel;
  logic [8:0] v_to_p_counter;
  logic [8:0] n_v_to_p_counter;
  logic [63:0] temp;
  logic [63:0] ptbr;
  logic [63:0] next_bus_req_v_addr;
  logic [63:0] distance_act_addr;
  logic [63:0] n_distance_act_addr;
  logic [63:0] a;
  logic [63:0] new_a;
  logic [63:0] old_pc;
  logic new_va_to_pa_req;
  logic decode_en;
  logic stop_reading_flag;
  logic [8:0] num_reads_within_block;
  logic [8:0] num_reads;
  logic [8:0] n_num_reads_within_block;

  process_instruction inst_1 (.instruction(nstage1_instruction_bits),
                              .rd(rd),
                              .rs1(rs1),
                              .rs2(rs2),
                              .imm(imm),
                              .flag(flag), 
                              .instruction_name(instruction_name));
  Decode decode_inst(.clk(clk),
		     .reset(reset),
		     .stage1_instruction_bits(nstage1_instruction_bits),
		     .stage1_pc(nstage1_pc),
		     .nstage2_valA(nstage2_valA),
		     .nstage2_valB(nstage2_valB),
		     .nstage2_immediate(nstage2_immediate),
		     .nstage2_pc(nstage2_pc),
		     .nstage2_dest(nstage2_dest),
		     .nstage2_op(nstage2_op),
		     .stage3_dest_reg(nstage3_rd),
		     .stage3_alu_result(nstage3_alu_result),
		     .wr_en(wr_en),
		     .display_regs(display_regs));
  execute_instruction ei(
                      .decode_en(decode_en),
                      .stage2_rd(nstage2_dest),
                      .stage2_rs1_val(nstage2_valA),
                      .stage2_rs2_val(nstage2_valB),
                      .stage2_immediate(nstage2_immediate),
                      .stage2_opcode_name(nstage2_op),
                      .stage2_pc(nstage2_pc),
                      .nstage3_alu_result(nstage3_alu_result),
                      .nstage3_rs2_val(nstage3_rs2_val),
                      .nstage3_rd(nstage3_rd),
                      .nstage3_opcode_name(nstage3_opcode_name),
                      .nstage3_pc(nstage3_pc),
                      .wr_en(wr_en));
  
  always_comb begin
    if(level == 0) begin
	assign temp = ptbr[63:0]+(pc[47:39]*PTESIZE);
	assign next_bus_req_v_addr = temp[63:6] << 6;
	assign n_distance_act_addr = (temp[63:0]- next_bus_req_v_addr[63:0])/PTESIZE;
    end
    else if(level == 1) begin
	assign temp = a[63:0]+(old_pc[38:30]*PTESIZE);
        assign next_bus_req_v_addr = temp[63:6] << 6;
        assign n_distance_act_addr = (temp[63:0]- next_bus_req_v_addr[63:0])/PTESIZE;
    end
    else if (level == 2) begin
	assign temp = a[63:0]+(old_pc[29:21]*PTESIZE);
        assign next_bus_req_v_addr = temp[63:6] << 6;
        assign n_distance_act_addr = (temp[63:0]- next_bus_req_v_addr[63:0])/PTESIZE;
    end
    else begin
	assign temp = a[63:0]+(old_pc[20:12]*PTESIZE);
        assign next_bus_req_v_addr = temp[63:6] << 6;
        assign n_distance_act_addr = (temp[63:0]- next_bus_req_v_addr[63:0])/PTESIZE;
    end
    assign new_a = bus_resp[47:10] << 12;
    assign npc = pc+('d64-pc[5:0]);
    assign num_reads = ('d64-old_pc[5:0])>>2;
    assign nstage1_pc = stage1_pc + 'd4;
    assign bus_reqtag = `SYSBUS_READ<<12|`SYSBUS_MEMORY<<8;
    assign ncounter = counter + 'd1;
    assign nalternator = alternator + 'b1;
    if (alternator == 'b1) begin
      assign nstage1_instruction_bits = bus_resp[31:0];
      assign nbus_respack = 0;
    end else begin
      assign nstage1_instruction_bits = bus_resp[63:32]; 
      assign nbus_respack = 1;
    end
    assign nlevel = level+1;
    assign n_v_to_p_counter = v_to_p_counter + 'd1;
    assign n_num_reads_within_block = num_reads_within_block + 'd1;
  end
  always @ (posedge clk)//note: all statements run in parallel
    if(reset) begin
	ptbr <= 'd4096;
	pc <= entry;
	stage1_pc <= entry;
	counter <= 'd16;
	alternator <= 'b1;
        level <= 0;
	paddr_set <= 1;
	new_va_to_pa_req <= 1;
    end
    else begin
	if(paddr_set)  begin //fetching data here
		if(bus_respcyc) begin
			if(stop_reading_flag == 'd0) begin
				if(!nstage1_instruction_bits) begin
					//$finish;
					$display("it's done!");
					display_regs <= 'd1;
				end
				else begin
					$display("pc: %d", stage1_pc);
					$display(" nstage_instruction_bits:%x ", nstage1_instruction_bits);
					alternator <= nalternator;
					stage1_pc <= nstage1_pc;
					bus_respack <= nbus_respack;
  	     			end
				num_reads_within_block <= n_num_reads_within_block;
				$display("num_reads_within_block value while reading data %d",num_reads_within_block);
				$display("num_reads value rd %d, pc %d",num_reads,stage1_pc);
				if(num_reads_within_block == num_reads) begin
					stop_reading_flag <= 'd1;
				end
			end
			else begin
				$display("num_reads_within_block value while waiting %d",num_reads_within_block);
				$display("num_reads value nrd %d",num_reads);
				bus_respack <= nbus_respack;
				alternator <= nalternator;
			end
		end
		else begin
	     		bus_respack <= 0;
		end

		if(counter == 'd16) begin //if counter is 16 get ready to send request for data
			if(new_va_to_pa_req) begin
				pc <= npc;
				old_pc <= pc;
				bus_req <= next_bus_req_v_addr;
				bus_reqcyc <= 1;
				paddr_set <= 0;
				counter <= counter;
				level <= level;
				v_to_p_counter <= 0;
				distance_act_addr <= n_distance_act_addr;
				decode_en <= 0;
				$display("in counter=16, new_va_to  bus_req: %d", next_bus_req_v_addr);
			end
			else begin
				pc <= pc;
				bus_req <= bus_req;
				bus_reqcyc <= 1;
				paddr_set <= paddr_set;
				counter <= 0;
				level <= level;
				v_to_p_counter <= v_to_p_counter;
				stop_reading_flag <= 'd0;
                                num_reads_within_block <= 'd1;
				//$display("in counter=16, NO new_va_to  bus_req: %d", bus_req);
			end
			new_va_to_pa_req <= 0;
		end else if (counter != 'd16 && bus_respcyc) begin
	     		pc <= pc;
             		bus_req <= bus_req;
	     		bus_reqcyc <= bus_reqcyc;
	     		counter <= ncounter;//implement as assign new_counter=counter+'d1 and counter <= new_counter
			paddr_set <= paddr_set;
			new_va_to_pa_req <= 1;
			level <= 0;
		end else begin
	     		pc <= pc;
             		bus_req <= bus_req;
	     		bus_reqcyc<=0;
	     		counter <= counter;
			paddr_set <= paddr_set;
		end
    	end
	else begin //process for va to pa
		
		if  (bus_respcyc) begin //we have a response..we can go ahead and process it
			if(v_to_p_counter == distance_act_addr) begin
				//put it in phy addr and increment level and send ack
				a <= new_a;
				level <= nlevel;	
				//$display("in paddr_set, setting a: %d", new_a);
				//$display("in paddr_set, setting a level: %d", nlevel);
				//$display("in paddr_set, setting a, distance_act_addr: %d", distance_act_addr);
			end
			else begin
				//send ack, let level stay the same
				level <= level;
			end
			bus_respack <= 1;
			bus_req <= bus_req;
			bus_reqcyc <= bus_reqcyc;
			v_to_p_counter <= n_v_to_p_counter;
			//$display("in paddr_set, bus_resp=y bus_req: %d", bus_req);
			//$display("in paddr_set, setting a: %d", a);
			//$display("in paddr_set, bus_resp=y bus_resp: %d", bus_resp);
			//$display("in paddr_set, bus_resp=y v_to_p_counter: %d", v_to_p_counter);
			//$display();
		end
		else if(level < 4) begin //finished processing one block
			level <= level;
			bus_respack <= 0;
			if(v_to_p_counter == 'd8) begin //send request and change counter to 0
				bus_req <= next_bus_req_v_addr;
				bus_reqcyc <= 1;
				v_to_p_counter <= 0;
				distance_act_addr <= n_distance_act_addr;
				$display("in level <4 , v_to_p_counter=8  bus_req: %d level: %d", next_bus_req_v_addr, level);
			end
			else begin //wait
				//$display("in level <4 , wait  bus_req: %d", bus_req);
				bus_req <= bus_req;
				bus_reqcyc <= 0;
				v_to_p_counter <= v_to_p_counter;
			end
		end
		else begin
			decode_en <=1;
			new_va_to_pa_req <= 0;
			paddr_set <= 1;
			bus_req <= a |old_pc[11:0];
			$display("Phy bus_req: %d", a|old_pc[11:0]);
		end
	end
    end
  initial begin
    $display("Initializing top, entry point = 0x%x", entry);
  end
endmodule