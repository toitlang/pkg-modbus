// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import reader

class Frame:
  static NO_TRANSACTION_ID ::= -1

  /**
  The transaction identifier of the frame.

  This identifier is not strictly part of the specification and only used in some transports.
  However, it is convenient to store it together with the frame.

  In cases where no transaction ID is used, the value is ignored.
  */
  identifier/int

  /**
  The server address.
  Can be 0 for broadcast, and 255 if it should be ignored (typically for Modbus TCP).
  */
  address/int

  /**
  The function code of the transaction.

  See Modbus Application Protocol V1.1b3, Section 6.
  */
  function_code/int

  /** The data. */
  data/ByteArray

  constructor .identifier .address .function_code .data:

interface Framer:
  read reader/reader.BufferedReader -> Frame?
  write frame/Frame writer

class InvalidFrameException:
  transaction_identifier/int
  message/string
  frame_bytes/ByteArray

  constructor --.transaction_identifier --.message --.frame_bytes:

  stringify -> string:
    return "Invalid frame: $message"
