// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .framer

class ModbusException:
  static CRC_MISMATCH ::= 0
  static ILLEGAL_FUNCTION ::= 1
  static ILLEGAL_DATA_ADDRESS ::= 2
  static ILLEGAL_DATA_VALUE ::= 3
  static SERVER_DEVICE_BUSY ::= 6
  static UNKNOWN_MODBUS ::= 20
  static MISSING_INFORMATION ::= 21
  static CORRUPTED ::= 99

  code/int
  message/string
  transaction_id/int
  data/any

  constructor.crc --.transaction_id --.message --frame_bytes/ByteArray:
    code = CRC_MISMATCH
    data = frame_bytes

  constructor.corrupted --.message --frame/Frame:
    transaction_id = frame.transaction_id
    code = CORRUPTED
    data = frame

  constructor.frame_error .code --.message --frame/Frame:
    transaction_id = frame.transaction_id
    data = frame

  constructor.other .code --.transaction_id --.message --.data:

  stringify -> string:
    return "Invalid frame $message"
