// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary

import .framer

class Request:
  function_code/int

  constructor .function_code:

class Response:
  static check_frame function_code/int frame/Frame:
    if function_code != frame.function_code: error_response_ frame

  static error_response_ frame/Frame:
    if frame.data[0] == 1: throw "Illegal Function"
    if frame.data[0] == 2: throw "Illegal Data Address"
    if frame.data[0] == 3: throw "Illegal Data Value"
    if frame.data[0] == 6: throw "Server Device Busy"
    throw "Unknown Error $frame.data[0]"

class WriteHoldingRegistersRequest extends Request:
  static ID ::= 16
  address/int
  registers/List
  preset_count/int

  constructor --.address --.registers --.preset_count:
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray 5 + registers.size * 2
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 registers.size + preset_count
    binary.BIG_ENDIAN.put_uint8 data 4 registers.size * 2
    registers.size.repeat:
      binary.BIG_ENDIAN.put_uint16 data 5 + it * 2 registers[it]
    return data

class WriteHoldingRegistersResponse extends Response:
  static ID ::= 16

  first_address/int
  changes/int

  constructor.deserialize frame/Frame:
    Response.check_frame ID frame
    first_address = binary.BIG_ENDIAN.uint16 frame.data 0
    changes = binary.BIG_ENDIAN.uint16 frame.data 2

class ReadHoldingRegistersRequest extends Request:
  static ID ::= 3
  address/int
  count/int

  constructor --.address --.count:
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 count
    return data

class ReadHoldingRegistersResponse extends Response:
  static ID ::= 3

  registers/List

  constructor.deserialize frame/Frame:
    Response.check_frame ID frame
    byte_count := binary.BIG_ENDIAN.uint8 frame.data 0
    registers = List byte_count / 2
    registers.size.repeat:
      registers[it] = binary.BIG_ENDIAN.uint16 frame.data 1 + 2 * it
