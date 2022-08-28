module rom_loader (
    input wire clk_74a,
    input wire reset_n,

    input wire bridge_wr,
    input wire bridge_endian_little,
    input wire [31:0] bridge_addr,
    input wire [31:0] bridge_wr_data,

    output reg write_en,
    output reg [14:0] write_addr,
    output reg [7:0] write_data,

    output wire [31:0] byte_count
  );

  wire apf_write_en;
  wire [14:0] apf_write_addr;
  wire [7:0] apf_write_data;

  data_loader_8 #(.ADDRESS_MASK_UPPER_4(4'h0)) data_loader_8 (
                  .clk_74a(clk_74a),
                  .bridge_wr(bridge_wr),
                  .bridge_endian_little(bridge_endian_little),
                  .bridge_addr(bridge_addr),
                  .bridge_wr_data(bridge_wr_data),

                  .write_en(apf_write_en),
                  .write_addr(apf_write_addr),
                  .write_data(apf_write_data)
                );

  reg [31:0] byte_count_reg = 0;

  assign byte_count = byte_count_reg;

  // 45 bytes in each row
  reg [5:0] hex_nibble_index = 0;
  reg [15:0] addr;

  reg [7:0] line_byte_count;

  // Hex values are ASCII characters. If > 0x40, it's a letter A-F, so subtract so it becomes 0xA-F
  // Otherwise, it's a number, which is in the range 0x30-39, so we can just subtract 0x30
  wire [3:0] digit = apf_write_data > 8'h40 ? apf_write_data - 8'h37 : apf_write_data - 8'h30;
  reg has_digit_high = 0;
  reg [3:0] cached_digit_high;

  always @(posedge clk_74a or negedge reset_n)
  begin
    if(~reset_n)
    begin
      hex_nibble_index <= 0;
      byte_count_reg <= 0;
      has_digit_high <= 0;
    end
    else
    begin
      write_en <= 0;

      if(apf_write_en)
      begin
        hex_nibble_index <= hex_nibble_index + 1;

        case (hex_nibble_index)
          // 0: // Line marker ":", ignore
          1: // Number of bytes in the line, should be 0x10
            line_byte_count[7:4] <= digit;
          2:
            line_byte_count[3:0] <= digit;
          3: // Address
            addr[15:12] <= digit;
          4:
            addr[11:8] <= digit;
          5:
            addr[7:4] <= digit;
          6:
            addr[3:0] <= digit;
          // 7, 8: // Data type. Will either be data or end of line
          9:
          begin
            // Data
            if(line_byte_count > 0)
            begin
              // Within the data segment
              if(has_digit_high)
              begin
                // Write combined digits
                write_en <= 1;

                write_addr <= addr[14:0];
                write_data <= {cached_digit_high, digit};
                byte_count_reg <= addr[14:0];

                addr <= addr + 1;
                line_byte_count <= line_byte_count - 1;
              end
              else
              begin
                cached_digit_high <= digit;
              end

              has_digit_high <= ~has_digit_high;
              // Keep processing data
              hex_nibble_index <= 9;
            end
            else
            begin
              // Out of data segment, this is the first nibble of the checksum,
              // skip to second half of checksum at 11
              hex_nibble_index <= 11;
            end
          end
          // 10, 11: // Checksum
          // 12: // Carriage return
          13:
            // Newline
            // Ready for a new hex line
            hex_nibble_index <= 0;
        endcase
      end
    end
  end

endmodule