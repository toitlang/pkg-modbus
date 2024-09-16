// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .framer

class ModbusException:
  static CRC-MISMATCH ::= 0
  static ILLEGAL-FUNCTION ::= 1
  static ILLEGAL-DATA-ADDRESS ::= 2
  static ILLEGAL-DATA-VALUE ::= 3
  static SERVER-DEVICE-BUSY ::= 6
  static UNKNOWN-MODBUS ::= 20
  static MISSING-INFORMATION ::= 21
  static CORRUPTED ::= 99

  code/int
  message/string
  transaction-id/int
  data/any

  constructor.crc --.transaction-id --.message --frame-bytes/ByteArray:
    code = CRC-MISMATCH
    data = frame-bytes

  constructor.corrupted --.message --frame/Frame:
    transaction-id = frame.transaction-id
    code = CORRUPTED
    data = frame

  constructor.frame-error .code --.message --frame/Frame:
    transaction-id = frame.transaction-id
    data = frame

  constructor.noise --.message --.data:
    code = CORRUPTED
    transaction-id = Frame.NO-TRANSACTION-ID

  constructor.other .code --.transaction-id --.message --.data:

  stringify -> string:
    return "Invalid frame: $message"
