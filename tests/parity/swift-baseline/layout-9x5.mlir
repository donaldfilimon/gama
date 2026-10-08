"gama.module"() ({
  "gama.border"() ({
    "gama.padding"() ({
      "gama.stack"() ({
        "gama.text"() {text = "A<&中", fg = "default", bg = "default", sgr = 1 : i64, x = 2 : i64, y = 2 : i64, w = 5 : i64, h = 1 : i64} : () -> ()
        "gama.stack"() ({
          "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 2 : i64, y = 4 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
          "gama.spacer"() {min = 1 : i64, x = 4 : i64, y = 4 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
          "gama.text"() {text = "end", fg = "default", bg = "default", sgr = 0 : i64, x = 6 : i64, y = 4 : i64, w = 3 : i64, h = 1 : i64} : () -> ()
        }) {axis = "h", spacing = 1 : i64, halign = "leading", valign = "top", x = 2 : i64, y = 4 : i64, w = 7 : i64, h = 1 : i64} : () -> ()
      }) {axis = "v", spacing = 1 : i64, halign = "leading", valign = "top", x = 2 : i64, y = 2 : i64, w = 5 : i64, h = 1 : i64} : () -> ()
    }) {top = 1 : i64, leading = 1 : i64, bottom = 1 : i64, trailing = 1 : i64, x = 1 : i64, y = 1 : i64, w = 7 : i64, h = 3 : i64} : () -> ()
  }) {style = "rounded", fg = dense<[224, 64, 64]> : tensor<3xi8>, title = "T", x = 0 : i64, y = 0 : i64, w = 9 : i64, h = 5 : i64} : () -> ()
}) {sym_name = "parity"} : () -> ()
