// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io

import .exception
import .framer

abstract class Request:
  function-code/int

  constructor .function-code:

  abstract to-byte-array -> ByteArray

class Response:
  static check-frame_ function-code/int frame/Frame:
    if function-code != frame.function-code: error-response_ frame

  static error-response_ frame/Frame:
    if frame.data.is-empty:
      exception := ModbusException.corrupted --message="Error response is missing reason" --frame=frame
      throw exception

    if frame.data[0] == 1:
      exception := ModbusException.frame-error ModbusException.ILLEGAL-FUNCTION --message="Illegal function" --frame=frame
      throw exception
    if frame.data[0] == 2:
      exception := ModbusException.frame-error ModbusException.ILLEGAL-DATA-ADDRESS
          --message="Illegal data address"
          --frame=frame
      throw exception
    if frame.data[0] == 3:
      exception := ModbusException.frame-error ModbusException.ILLEGAL-DATA-VALUE
          --message="Illegal data value"
          --frame=frame
      throw exception
    if frame.data[0] == 6:
      exception := ModbusException.frame-error ModbusException.SERVER-DEVICE-BUSY
          --message="Server device busy"
          --frame=frame
      throw exception
    exception := ModbusException.frame-error ModbusException.UNKNOWN-MODBUS
        --message="Unknown Modbus error $frame.data[0]"
        --frame=frame
    throw exception

  static check-sized-data_ frame/Frame expected-size/int=-1 --count-must-be-even/bool=false:
    if frame.data.is-empty:
      exception := ModbusException.corrupted
        --message="Empty data; expected a count byte"
        --frame=frame
      throw exception

    if expected-size != -1:
      if frame.data.size != expected-size:
        exception := ModbusException.corrupted
          --message="Data byte size is $frame.data.size; expected $expected-size"
          --frame=frame
        throw exception
    else:
      byte-count := frame.data[0]

      if count-must-be-even and (byte-count & 1) != 0:
        exception := ModbusException.corrupted
          --message="Odd number of data bytes"
          --frame=frame
        throw exception

      if frame.data.size != byte-count + 1:
        exception := ModbusException.corrupted
          --message="Expected $byte-count bytes; got $(frame.data.size - 1)"
          --frame=frame
        throw exception

class RawRequest extends Request:
  payload/ByteArray
  constructor function-code/int .payload:
    super function-code
  to-byte-array -> ByteArray:
    return payload

class RawResponse extends Response:
  bits/ByteArray
  constructor.deserialize frame/Frame function-code/int:
    Response.check-frame_ function-code frame
    bits = frame.data

class ReadBitsRequest extends Request:
  static COILS-ID ::= 1
  static DISCRETE-INPUTS-ID ::= 2
  address/int
  bit-count/int

  constructor --.address --.bit-count --is-coils/bool:
    super (is-coils ? COILS-ID : DISCRETE-INPUTS-ID)

  to-byte-array -> ByteArray:
    data := ByteArray 4
    io.BIG-ENDIAN.put-uint16 data 0 address
    io.BIG-ENDIAN.put-uint16 data 2 bit-count
    return data

class ReadBitsResponse extends Response:
  static COILS-ID ::= 1
  static DISCRETE-INPUTS-ID ::= 2

  bits/ByteArray

  constructor.deserialize frame/Frame --is-coils/bool:
    Response.check-frame_ (is-coils ? COILS-ID : DISCRETE-INPUTS-ID) frame
    Response.check-sized-data_ frame
    byte-count := io.BIG-ENDIAN.uint8 frame.data 0
    bits = frame.data[1..].copy

class WriteSingleCoilRequest extends Request:
  static ID ::= 5
  address/int
  value/bool

  constructor --.address --.value:
    super ID

  to-byte-array -> ByteArray:
    data := ByteArray 4
    io.BIG-ENDIAN.put-uint16 data 0 address
    io.BIG-ENDIAN.put-uint16 data 2 (value ? 0xFF00 : 0)
    return data

class WriteSingleCoilResponse extends Response:
  static ID ::= 5

  address/int
  value/bool

  constructor.deserialize frame/Frame:
    Response.check-frame_ ID frame
    Response.check-sized-data_ frame 4
    address = io.BIG-ENDIAN.uint16 frame.data 0
    value = (io.BIG-ENDIAN.uint16 frame.data 2) == 0xFF00

class WriteSingleRegisterRequest extends Request:
  static ID ::= 6
  address/int
  value/int

  constructor --.address --.value:
    super ID

  to-byte-array -> ByteArray:
    data := ByteArray 4
    io.BIG-ENDIAN.put-uint16 data 0 address
    io.BIG-ENDIAN.put-uint16 data 2 value
    return data

class WriteSingleRegisterResponse extends Response:
  static ID ::= 6

  address/int
  value/int

  constructor.deserialize frame/Frame:
    Response.check-frame_ ID frame
    Response.check-sized-data_ frame 4
    address = io.BIG-ENDIAN.uint16 frame.data 0
    value = io.BIG-ENDIAN.uint16 frame.data 2

class WriteMultipleCoilsRequest extends Request:
  static ID ::= 15
  address/int
  values/ByteArray
  count/int

  constructor --.address --.values --.count:
    if (count + 7) / 8 != values.size: throw "INVALID_ARGUMENT"
    super ID

  to-byte-array -> ByteArray:
    data := ByteArray (5 + values.size)
    io.BIG-ENDIAN.put-uint16 data 0 address
    io.BIG-ENDIAN.put-uint16 data 2 count
    data[4] = values.size
    // Copy over all the values.
    data.replace 5 values
    // If necessary, fix the last byte so that the unused bits are zero.
    if count % 8 != 0:
      last-byte := data.last
      last-byte &= (1 << (count % 8)) - 1
      data[data.size - 1] = last-byte
    return data

class WriteMultipleCoilsResponse extends Response:
  static ID ::= 15

  address/int
  count/int

  constructor.deserialize frame/Frame:
    Response.check-frame_ ID frame
    Response.check-sized-data_ frame 4
    address = io.BIG-ENDIAN.uint16 frame.data 0
    count = io.BIG-ENDIAN.uint16 frame.data 2

class WriteHoldingRegistersRequest extends Request:
  static ID ::= 16
  address/int
  registers/List

  constructor --.address --.registers:
    super ID

  to-byte-array -> ByteArray:
    data := ByteArray 5 + registers.size * 2
    io.BIG-ENDIAN.put-uint16 data 0 address
    io.BIG-ENDIAN.put-uint16 data 2 registers.size
    io.BIG-ENDIAN.put-uint8 data 4 registers.size * 2
    registers.size.repeat:
      io.BIG-ENDIAN.put-uint16 data (5 + it * 2) registers[it]
    return data

class WriteHoldingRegistersResponse extends Response:
  static ID ::= 16

  first-address/int
  changes/int

  constructor.deserialize frame/Frame:
    Response.check-frame_ ID frame
    Response.check-sized-data_ frame 4

    first-address = io.BIG-ENDIAN.uint16 frame.data 0
    changes = io.BIG-ENDIAN.uint16 frame.data 2

class ReadRegistersRequest extends Request:
  static HOLDING-ID ::= 3
  static INPUT-ID ::= 4
  address/int
  register-count/int

  constructor --.address --.register-count --holding/bool:
    super (holding ? HOLDING-ID : INPUT-ID)

  to-byte-array -> ByteArray:
    data := ByteArray 4
    io.BIG-ENDIAN.put-uint16 data 0 address
    io.BIG-ENDIAN.put-uint16 data 2 register-count
    return data

class ReadRegistersResponse extends Response:
  static HOLDING-ID ::= 3
  static INPUT-ID ::= 4

  registers/List

  constructor.deserialize frame/Frame --holding/bool:
    Response.check-frame_ (holding ? HOLDING-ID : INPUT-ID) frame
    Response.check-sized-data_ frame --count-must-be-even
    byte-count := io.BIG-ENDIAN.uint8 frame.data 0
    registers = List (byte-count / 2):
      io.BIG-ENDIAN.uint16 frame.data (1 + 2 * it)

class ReportServerIdRequest extends Request:
  static ID ::= 17

  constructor:
    super ID

  to-byte-array -> ByteArray:
    return #[]

class ReportServerIdResponse extends Response:
  static ID ::= 17

  server-id/ByteArray
  on-off/bool

  constructor.deserialize frame/Frame:
    Response.check-frame_ ID frame
    Response.check-sized-data_ frame
    byte-count := io.BIG-ENDIAN.uint8 frame.data 0
    if byte-count == 0:
        exception := ModbusException.other
          ModbusException.MISSING-INFORMATION
          --transaction-id=frame.transaction-id
          --message="Missing on/off information in server-id response"
          --data=frame.data
        throw exception
    server-id = frame.data[1..frame.data.size - 1]
    on-off = frame.data.last != 0x00

class MaskWriteRegisterRequest extends Request:
  static ID ::= 22
  address/int
  and-mask/int
  or-mask/int

  constructor --.address --.and-mask --.or-mask:
    super ID

  to-byte-array -> ByteArray:
    data := ByteArray 6
    io.BIG-ENDIAN.put-uint16 data 0 address
    io.BIG-ENDIAN.put-uint16 data 2 and-mask
    io.BIG-ENDIAN.put-uint16 data 4 or-mask
    return data

class MaskWriteRegisterResponse extends Response:
  static ID ::= 22

  address/int
  and-mask/int
  or-mask/int

  constructor.deserialize frame/Frame:
    Response.check-frame_ ID frame
    Response.check-sized-data_ frame 6
    address = io.BIG-ENDIAN.uint16 frame.data 0
    and-mask = io.BIG-ENDIAN.uint16 frame.data 2
    or-mask = io.BIG-ENDIAN.uint16 frame.data 4

class WriteReadMultipleRegistersRequest extends Request:
  static ID ::= 23
  write-address/int
  write-registers/List
  read-address/int
  read-register-count/int

  constructor --.write-address --.write-registers --.read-address --.read-register-count:
    super ID

  to-byte-array -> ByteArray:
    data := ByteArray (9 + write-registers.size * 2)
    io.BIG-ENDIAN.put-uint16 data 0 read-address
    io.BIG-ENDIAN.put-uint16 data 2 read-register-count
    io.BIG-ENDIAN.put-uint16 data 4 write-address
    io.BIG-ENDIAN.put-uint16 data 6 write-registers.size
    io.BIG-ENDIAN.put-uint8 data 8 write-registers.size * 2
    write-registers.size.repeat:
      io.BIG-ENDIAN.put-uint16 data (9 + it * 2) write-registers[it]
    return data

class WriteReadMultipleRegistersResponse extends Response:
  static ID ::= 23

  registers/List

  constructor.deserialize frame/Frame:
    Response.check-frame_ ID frame
    Response.check-sized-data_ frame --count-must-be-even
    byte-count := io.BIG-ENDIAN.uint8 frame.data 0
    registers = List (byte-count / 2):
      io.BIG-ENDIAN.uint16 frame.data (1 + 2 * it)
