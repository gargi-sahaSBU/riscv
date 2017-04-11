
module va_to_pa
#(
    BUS_DATA_WIDTH = 64,
    TYPE_WIDTH = 3,
    REGISTER_WIDTH = 5,
    REGISTER_NAME_WIDTH = 4,
    IMMEDIATE_WIDTH = 32,
    FLAG_WIDTH = 16,
    BUS_TAG_WIDTH = 13,
    INSTRUCTION_NAME_WIDTH = 12
)
(
    input clk,
    input reset,
    input enable,
    input [BUS_DATA_WIDTH-1:0] ptbr,
    input abtr_grant,
    output abtr_reqcyc,
    output bus_busy,
    input main_bus_respcyc,
    input [BUS_DATA_WIDTH-1:0] main_bus_resp,
    output main_bus_respack,
    output main_bus_reqcyc,
    output [BUS_DATA_WIDTH-1:0] main_bus_req,
    output ready,
    input [BUS_DATA_WIDTH-1:0] virt_addr,
    output [BUS_DATA_WIDTH-1:0] phy_addr,
    output [BUS_TAG_WIDTH-1:0] main_bus_reqtag
);
    logic[3:0] counter;
    logic[3:0] ncounter;
    logic[2:0] level;
    logic[2:0] nlevel;
    logic[3:0] request_counter;
    logic[11:0] pt_no;
    logic[BUS_DATA_WIDTH-1:0] request_addr;
    enum {STATERESET=3'b000, STATEBEGIN=3'b001, STATEREQ=3'b010, STATEWAIT=3'b011,
          STATERESP=3'b100, STATEREADY=3'b101} state, next_state;
    always_comb begin
        case(state)
            STATERESET: next_state = enable? STATEBEGIN : STATERESET ;
            STATEBEGIN: next_state = abtr_grant? STATEREQ : STATEBEGIN;
            STATEREQ: next_state = STATEWAIT;
            STATEWAIT: next_state = main_bus_respcyc? STATERESP: STATEWAIT;
            STATERESP:
                if (counter < 8) begin
                    next_state = STATERESP;
                end else begin
                    if (level < 4) begin
                        next_state = STATEREQ;
                    end else begin
                        next_state = STATEREADY;
                    end
                end
            STATEREADY:
                next_state = enable? STATEBEGIN : STATEREADY;
        endcase
    end

    always_ff @ (posedge clk) begin
        if(reset) begin
            state <= STATERESET;
            level <= 0;
            //request_addr[63:0] <= ptbr[63:0] + virt_addr[47:39];
            $display("VP state resetted");
            $display("VP Virt Addr to: %d",virt_addr[47:39]);
        end else begin
            state <= next_state;
            case(next_state)
                STATEBEGIN:
                begin
		    $display("VP Virt Addr to: %d",virt_addr[47:39]);
                    level <= 0;
                    request_addr[63:0] <= ptbr[63:0] + virt_addr[47:39];
                end
                STATEREQ:
                begin
                    //$display("VP State req, going to wait, level: %d", nlevel);
                    //$display("VP Main Bus Req: ", main_bus_req);
                    //$display("VP Main Bus addr: ", request_addr);
                    //$display("VP virt_addr: ", virt_addr);
                    level <= nlevel;
                    request_counter <= request_addr[5:3];
                end
                STATEWAIT:
                begin
                    //$display("State wait, going to resp");
                    level <= level;
                    counter <= 0;
                end
                STATERESP:
                begin
                    $display("VP State resp, going to ready, request_counter: %d", request_counter);
                    level <= level;
                    counter <= ncounter;
                    if(counter == request_counter) begin
                        $display("VP For next, pt_no: %d", pt_no);
                        $display("VP request addr: %d", (main_bus_resp[63:10] << 12) + pt_no[11:0]);
                        $display("VP phy addr: %d", (main_bus_resp[63:10] << 12) + virt_addr[11:0]);
                        request_addr <= (main_bus_resp[63:10] << 12) + pt_no[11:0];
                        //main_bus_req <= ((main_bus_resp[63:10] << 12) + pt_no[11:6]<<6);
                        phy_addr <= (main_bus_resp[63:10] << 12) + virt_addr[11:0];
                    end
                end
                STATEREADY:
                begin
                    //$display("VP State ready");
                    level <= 0;
                    counter <= counter;
                end
            endcase
        end
    end

    always_comb begin
        assign nlevel = level + 1;
        assign ncounter = counter + 1;
        case(level)
            1:
            begin
                assign pt_no = virt_addr[38:30] << 3;
            end
            2:
            begin
                assign pt_no = virt_addr[29:21] << 3;
            end
            3:
            begin
                assign pt_no = virt_addr[20:12] << 3;
            end
        endcase
        case(state)
            STATERESET:
            begin
                assign ready = 0;
                assign abtr_reqcyc = 0;
            end
            STATEBEGIN:
            begin
                assign ready = 0;
                assign abtr_reqcyc = 1;
            end
            STATEREQ:
            begin
                assign bus_busy = 1;
                assign abtr_reqcyc = 1;
                assign main_bus_reqcyc = 1;
                assign main_bus_respack = 0;
                assign main_bus_reqtag = `SYSBUS_READ<<12|`SYSBUS_MEMORY<<8;
                // TODO: Remove. Testing out.
                main_bus_req = request_addr[63:6] << 6;
                // TODO: uncommet the if else block. Testing out.
                /*
                if(level == 1) begin //forwarding path
                    assign main_bus_req = ptbr[63:0] + virt_addr[47:39];
                end else begin
                    assign main_bus_req = request_addr[63:6] << 6;
                end
                */
            end
            STATEWAIT:
            begin
                assign bus_busy = 1;
                assign abtr_reqcyc = 1;
                assign main_bus_reqcyc = 0;
                assign main_bus_respack = 0;
            end
            STATERESP:
            begin
                assign bus_busy = 1;
                assign abtr_reqcyc = 1;
                assign main_bus_reqcyc = 0;
                assign main_bus_respack = 1;
            end
            STATEREADY:
            begin
                assign ready = 1;
                assign bus_busy = 0;
                assign abtr_reqcyc = 0;
            end
        endcase
    end
endmodule
