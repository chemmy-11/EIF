module t2;
reg r;
generate if (1) begin : g
  (* mark_debug = "true" *) wire a = r;
  always @* begin end
end endgenerate
endmodule
