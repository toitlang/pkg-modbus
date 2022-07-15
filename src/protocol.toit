// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary

import .exception
import .framer

abstract class Request:
  function_code/int

  constructor .function_code:

  abstract to_byte_array -> ByteArray

class Response:
  static check_frame_ function_code/int frame/Frame:
    if function_code != frame.function_code: error_response_ frame

  static error_response_ frame/Frame:
    if frame.data.is_empty:
      exception := ModbusException.corrupted --message="Error response is missing reason" --frame=frame
      throw exception

    if frame.data[0] == 1:
      exception := ModbusException.frame_error ModbusException.ILLEGAL_FUNCTION --message="Illegal function" --frame=frame
      throw exception
    if frame.data[0] == 2:
      exception := ModbusException.frame_error ModbusException.ILLEGAL_DATA_ADDRESS
          --message="Illegal data address"
          --frame=frame
      throw exception
    if frame.data[0] == 3:
      exception := ModbusException.frame_error ModbusException.ILLEGAL_DATA_VALUE
          --message="Illegal data value"
          --frame=frame
      throw exception
    if frame.data[0] == 6:
      exception := ModbusException.frame_error ModbusException.SERVER_DEVICE_BUSY
          --message="Server device busy"
          --frame=frame
      throw exception
    exception := ModbusException.frame_error ModbusException.UNKNOWN_MODBUS
        --message="Unknown Modbus error $frame.data[0]"
        --frame=frame
    throw exception

  static check_sized_data_ frame/Frame expected_size/int=-1 --count_must_be_even/bool=false:
    if frame.data.is_empty:
      exception := ModbusException.corrupted
        --message="Empty data; expected a count byte"
        --frame=frame
      throw exception

    if expected_size != -1:
      if frame.data.size != expected_size:
        exception := ModbusException.corrupted
          --message="Data byte size is $frame.data.size; expected $expected_size"
          --frame=frame
        throw exception
    else:
      byte_count := frame.data[0]

      if count_must_be_even and (byte_count & 1) != 0:
        exception := ModbusException.corrupted
          --message="Odd number of data bytes"
          --frame=frame
        throw exception

      if frame.data.size != byte_count + 1:
        exception := ModbusException.corrupted
          --message="Expected $byte_count bytes; got $(frame.data.size - 1)"
          --frame=frame
        throw exception

class ReadBitsRequest extends Request:
  static COILS_ID ::= 1
  static DISCRETE_INPUTS_ID ::= 2
  address/int
  bit_count/int

  constructor --.address --.bit_count --is_coils/bool:
    super (is_coils ? COILS_ID : DISCRETE_INPUTS_ID)

  to_byte_array -> ByteArray:
    data := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 bit_count
    return data

class ReadBitsResponse extends Response:
  static COILS_ID ::= 1
  static DISCRETE_INPUTS_ID ::= 2

  bits/ByteArray

  constructor.deserialize frame/Frame --is_coils/bool:
    Response.check_frame_ (is_coils ? COILS_ID : DISCRETE_INPUTS_ID) frame
    Response.check_sized_data_ frame
    byte_count := binary.BIG_ENDIAN.uint8 frame.data 0
    bits = frame.data[1..].copy

class WriteSingleCoilRequest extends Request:
  static ID ::= 5
  address/int
  value/bool

  constructor --.address --.value:
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 (value ? 0xFF00 : 0)
    return data

class WriteSingleCoilResponse extends Response:
  static ID ::= 5

  address/int
  value/bool

  constructor.deserialize frame/Frame:
    Response.check_frame_ ID frame
    Response.check_sized_data_ frame 4
    address = binary.BIG_ENDIAN.uint16 frame.data 0
    value = (binary.BIG_ENDIAN.uint16 frame.data 2) == 0xFF00

class WriteSingleRegisterRequest extends Request:
  static ID ::= 6
  address/int
  value/int

  constructor --.address --.value:
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 value
    return data

class WriteSingleRegisterResponse extends Response:
  static ID ::= 6

  address/int
  value/int

  constructor.deserialize frame/Frame:
    Response.check_frame_ ID frame
    Response.check_sized_data_ frame 4
    address = binary.BIG_ENDIAN.uint16 frame.data 0
    value = binary.BIG_ENDIAN.uint16 frame.data 2

class WriteMultipleCoilsRequest extends Request:
  static ID ::= 15
  address/int
  values/ByteArray
  count/int

  constructor --.address --.values --.count:
    if (count + 7) / 8 != values.size: throw "INVALID_ARGUMENT"
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray (5 + values.size)
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 count
    data[4] = values.size
    // Copy over all the values.
    data.replace 5 values
    // If necessary, fix the last byte so that the unused bits are zero.
    if count % 8 != 0:
      last_byte := data.last
      last_byte &= (1 << (count % 8)) - 1
      data[data.size - 1] = last_byte
    return data

class WriteMultipleCoilsResponse extends Response:
  static ID ::= 15

  address/int
  count/int

  constructor.deserialize frame/Frame:
    Response.check_frame_ ID frame
    Response.check_sized_data_ frame 4
    address = binary.BIG_ENDIAN.uint16 frame.data 0
    count = binary.BIG_ENDIAN.uint16 frame.data 2

class WriteHoldingRegistersRequest extends Request:
  static ID ::= 16
  address/int
  registers/List

  constructor --.address --.registers:
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray 5 + registers.size * 2
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 registers.size
    binary.BIG_ENDIAN.put_uint8 data 4 registers.size * 2
    registers.size.repeat:
      binary.BIG_ENDIAN.put_uint16 data (5 + it * 2) registers[it]
    return data

class WriteHoldingRegistersResponse extends Response:
  static ID ::= 16

  first_address/int
  changes/int

  constructor.deserialize frame/Frame:
    Response.check_frame_ ID frame
    Response.check_sized_data_ frame 4

    first_address = binary.BIG_ENDIAN.uint16 frame.data 0
    changes = binary.BIG_ENDIAN.uint16 frame.data 2

class ReadRegistersRequest extends Request:
  static HOLDING_ID ::= 3
  static INPUT_ID ::= 4
  address/int
  register_count/int

  constructor --.address --.register_count --holding/bool:
    super (holding ? HOLDING_ID : INPUT_ID)

  to_byte_array -> ByteArray:
    data := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 register_count
    return data

class ReadRegistersResponse extends Response:
  static HOLDING_ID ::= 3
  static INPUT_ID ::= 4

  registers/List

  constructor.deserialize frame/Frame --holding/bool:
    Response.check_frame_ (holding ? HOLDING_ID : INPUT_ID) frame
    Response.check_sized_data_ frame --count_must_be_even
    byte_count := binary.BIG_ENDIAN.uint8 frame.data 0
    registers = List (byte_count / 2):
      binary.BIG_ENDIAN.uint16 frame.data (1 + 2 * it)

class ReportServerIdRequest extends Request:
  static ID ::= 17

  constructor:
    super ID

  to_byte_array -> ByteArray:
    return #[]

class ReportServerIdResponse extends Response:
  static ID ::= 17

  server_id/ByteArray
  on_off/bool

  constructor.deserialize frame/Frame:
    Response.check_frame_ ID frame
    Response.check_sized_data_ frame
    byte_count := binary.BIG_ENDIAN.uint8 frame.data 0
    if byte_count == 0:
        exception := ModbusException.other
          ModbusException.MISSING_INFORMATION
          --transaction_id=frame.transaction_id
          --message="Missing on/off information in server-id response"
          --data=frame.data
        throw exception
    server_id = frame.data[1..frame.data.size - 1]
    on_off = frame.data.last != 0x00

class MaskWriteRegisterRequest extends Request:
  static ID ::= 22
  address/int
  and_mask/int
  or_mask/int

  constructor --.address --.and_mask --.or_mask:
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray 6
    binary.BIG_ENDIAN.put_uint16 data 0 address
    binary.BIG_ENDIAN.put_uint16 data 2 and_mask
    binary.BIG_ENDIAN.put_uint16 data 4 or_mask
    return data

class MaskWriteRegisterResponse extends Response:
  static ID ::= 22

  address/int
  and_mask/int
  or_mask/int

  constructor.deserialize frame/Frame:
    Response.check_frame_ ID frame
    Response.check_sized_data_ frame 6
    address = binary.BIG_ENDIAN.uint16 frame.data 0
    and_mask = binary.BIG_ENDIAN.uint16 frame.data 2
    or_mask = binary.BIG_ENDIAN.uint16 frame.data 4

class WriteReadMultipleRegistersRequest extends Request:
  static ID ::= 23
  write_address/int
  write_registers/List
  read_address/int
  read_register_count/int

  constructor --.write_address --.write_registers --.read_address --.read_register_count:
    super ID

  to_byte_array -> ByteArray:
    data := ByteArray (9 + write_registers.size * 2)
    binary.BIG_ENDIAN.put_uint16 data 0 read_address
    binary.BIG_ENDIAN.put_uint16 data 2 read_register_count
    binary.BIG_ENDIAN.put_uint16 data 4 write_address
    binary.BIG_ENDIAN.put_uint16 data 6 write_registers.size
    binary.BIG_ENDIAN.put_uint8 data 8 write_registers.size * 2
    write_registers.size.repeat:
      binary.BIG_ENDIAN.put_uint16 data (9 + it * 2) write_registers[it]
    return data

class WriteReadMultipleRegistersResponse extends Response:
  static ID ::= 23

  registers/List

  constructor.deserialize frame/Frame:
    Response.check_frame_ ID frame
    Response.check_sized_data_ frame --count_must_be_even
    byte_count := binary.BIG_ENDIAN.uint8 frame.data 0
    registers = List (byte_count / 2):
      binary.BIG_ENDIAN.uint16 frame.data (1 + 2 * it)
