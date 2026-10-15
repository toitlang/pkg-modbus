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

/**
A transport that needs to prepare the line for each request and its response.

For example, a transport on a multiplexed serial line can select its channel, or switch the UART settings,
  and keep other users off the line until the response arrived.

Only works with a `SynchronousModbus` bus.
*/
interface TransactionTransport extends Transport:
  /**
  Calls the given $block, which writes a request and reads its response.
  */
  do-transaction [block] -> none
