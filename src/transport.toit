// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .framer

class Response:
  frame/Frame? ::= null
  error ::= null

  constructor.frame .frame:
  constructor.error .error:


interface Transport:
  supports-parallel-sessions -> bool

  write frame/Frame -> none
  read -> Frame?

  close -> none
