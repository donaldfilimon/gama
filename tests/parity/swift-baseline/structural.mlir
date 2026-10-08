"gama.module"() ({
  "gama.border"() ({
    "gama.padding"() ({
      "gama.stack"() ({
        "gama.text"() {text = "A<&中", fg = "default", bg = "default", sgr = 1 : i64} : () -> ()
        "gama.stack"() ({
          "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
          "gama.spacer"() {min = 1 : i64} : () -> ()
          "gama.text"() {text = "end", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
        }) {axis = "h", spacing = 1 : i64, halign = "leading", valign = "top"} : () -> ()
      }) {axis = "v", spacing = 1 : i64, halign = "leading", valign = "top"} : () -> ()
    }) {top = 1 : i64, leading = 1 : i64, bottom = 1 : i64, trailing = 1 : i64} : () -> ()
  }) {style = "rounded", fg = dense<[224, 64, 64]> : tensor<3xi8>, title = "T"} : () -> ()
}) {sym_name = "parity"} : () -> ()
