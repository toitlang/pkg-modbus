// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import reader

class Frame:
  identifier/int
  address/int
  function_code/int
  data/ByteArray

  constructor .identifier .address .function_code .data:

interface Framer:
  read reader/reader.BufferedReader -> Frame?
  write frame/Frame writer
