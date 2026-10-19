module t1;
reg r;
generate if (1) begin : g
  wire a = r;
  always @* begin end
end endgenerate
endmodule
