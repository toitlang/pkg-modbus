// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io

class Frame:
  static NO-TRANSACTION-ID ::= -1

  /**
  The transaction id of the frame.

  This id is not strictly part of the specification and only used in some transports.
  However, it is convenient to store it together with the frame.

  In cases where no transaction ID is used, the value is ignored.
  */
  transaction-id/int

  /**
  The unit id (aka "station address" or "server address").
  Can be 0 for broadcast, and 255 if it should be ignored (typically for Modbus TCP).
  */
  unit-id/int

  /**
  The function code of the transaction.

  See Modbus Application Protocol V1.1b3, Section 6.
  */
  function-code/int

  /** The data. */
  data/ByteArray

  constructor --.transaction-id --.unit-id --.function-code --.data:

interface Framer:
  read reader/io.Reader -> Frame?
  write frame/Frame writer

