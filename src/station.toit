// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary
import log
import monitor
import net.tcp

import .bus
import .exception
import .tcp
import .transport
import .framer
import .protocol
import .protocol as protocol

CLOSED_ERROR ::= "TRANSPORT_CLOSED"
TRANSACTION_CLOSED_ERROR ::= "TRANSACTION_CLOSED_ERROR"

/**
The response to $Station.read_server_id.
*/
class ServerIdResponse:
  /** Device specific data, identifying the server. */
  id/ByteArray
  /** Whether the device is on or off. */
  is_on/bool

  constructor .id .is_on:

  /** The $id converted to a string. */
  id_string -> string: return id.to_string_non_throwing

  stringify -> string:
    return "$id_string ($(is_on ? "on" : "off"))"

/**
A Modbus client to talk with a specific station (aka Modbus server).
*/
class Station:
  static BROADCAST_UNIT_ID ::= 0
  static IGNORED_UNIT_ID ::= 255

  bus_/Modbus
  unit_id/int
  logger_/log.Logger

  discrete_inputs_ /DiscreteInputs? := null
  coils_ /Coils? := null
  input_registers_ /InputRegisters? := null
  holding_registers_ /HoldingRegisters? := null

  constructor.from_bus_
      .bus_
      .unit_id
      --logger/log.Logger:
    logger_=logger

  /** Whether the underlying bus is closed. */
  is_bus_closed -> bool:
    return bus_.is_closed

  discrete_inputs -> DiscreteInputs:
    if not discrete_inputs_: discrete_inputs_ = DiscreteInputs.internal_ this
    return discrete_inputs_

  coils -> Coils:
    if not coils_: coils_ = Coils.internal_ this
    return coils_

  input_registers -> InputRegisters:
    if not input_registers_: input_registers_ = InputRegisters.internal_ this
    return input_registers_

  holding_registers -> HoldingRegisters:
    if not holding_registers_: holding_registers_ = HoldingRegisters.internal_ this
    return holding_registers_

  /**
  Reads the server identifaction.

  This function is only available for serial Modbus devices, although it may also work on some Modbus TCP devices.
  */
  read_server_id -> ServerIdResponse:
    logger_.debug "read_server_id" --tags={"unit_id": unit_id}
    request := ReportServerIdRequest
    response := bus_.send_ request --unit_id=unit_id: ReportServerIdResponse.deserialize it
    server_response := response as ReportServerIdResponse
    return ServerIdResponse server_response.server_id server_response.on_off

/**
A register reader for Modbus stations.

This is the base class for $InputRegisters and $HoldingRegisters.
*/
// TODO(florian): should we extend/implement serial.Registers?
//   They are designed for byte-sized registers, but we could probably make it work for 16-bit registers.
abstract class RegisterReader:
  station_/Station

  constructor.internal_ .station_:

  abstract is_holding_ -> bool

  /**
  Reads $register_count registers starting at the given $address.

  Returns a list of 16-bit values.

  Note that Modbus maps address 0 to register 1. This means that, in order to read register N, one must
    provide address (N - 1).

  If the $register_count is equal to 0, does nothing. In that case the server is not contacted.
  */
  read_many --address/int --register_count/int -> List:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if register_count == 0: return []
    if not 1 <= register_count <= 125: throw "OUT_OF_RANGE"
    station_.logger_.debug "$(is_holding_ ? "holding" : "input")_registers.read_many" --tags={"address": address, "register_count": register_count}
    request := ReadRegistersRequest
      --holding=is_holding_
      --address=address
      --register_count=register_count
    response := station_.bus_.send_ request --unit_id=station_.unit_id:
      ReadRegistersResponse.deserialize it --holding=is_holding_
    return (response as ReadRegistersResponse).registers

  /**
  Reads a single register from the given $address.

  Returns the register value.

  Note that Modbus maps address 0 to register 1. This means that, in order to read register N, one must
    provide address (N - 1).

  This is a convenience function using $read_many.
  */
  read_single --address/int -> int:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    station_.logger_.debug "$(is_holding_ ? "holding" : "input")_registers.read_single" --tags={"address": address}
    request := ReadRegistersRequest
      --holding=is_holding_
      --address=address
      --register_count=1
    response := station_.bus_.send_ request --unit_id=station_.unit_id:
      ReadRegistersResponse.deserialize it --holding=is_holding_
    return (response as ReadRegistersResponse).registers[0]

  /**
  Reads $byte_count bytes starting at $address and returns the data as a $ByteArray.

  This is a convenience function using $read_many.
  */
  read_byte_array --address/int --byte_count/int -> ByteArray:
    register_count := (byte_count + 1) / 2
    registers := read_many --address=address --register_count=register_count
    bytes := ByteArray byte_count
    (byte_count / 2).repeat: binary.BIG_ENDIAN.put_uint16 bytes it * 2 registers[it]
    if byte_count % 2 == 1: bytes[bytes.size - 1] = registers.last >> 8
    return bytes

  /**
  Reads a $string of size $character_count bytes from the given $address.

  This is a convenience function using $read_many.
  */
  read_string --address/int --character_count/int -> string:
    bytes := read_byte_array --address=address --byte_count=character_count
    return bytes.to_string

  /**
  Reads a 64-bit float from the given $address.

  This is a convenience function using $read_many. It assumes that the registers are stored in big-endian order.
  */
  read_float --address/int -> float:
    bytes := read_byte_array --address=address --byte_count=8
    return float.from_bits
      binary.BIG_ENDIAN.int64 bytes 0

  /**
  Reads a 32-bit float from the given $address.

  This is a convenience function using $read_many. It assumes that the registers are stored in big-endian order.
  */
  read_float32 --address/int -> float:
    return float.from_bits32
      read_uint32 --address=address

  /**
  Reads a signed 16-bit int from the given $address.

  This is a convenience function using $read_many.
  */
  read_int16 --address/int -> int:
    registers := read_many --address=address --register_count=1
    result := registers[0]
    if 0x8000 & result == 0: return result
    return result - 0x10000

  /**
  Reads an unsigned 32-bit int from the given $address.

  This is a convenience function using $read_many. It assumes that the registers are stored in big-endian order.
  */
  read_uint32 --address/int -> int:
    registers := read_many --address=address --register_count=2
    buffer := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 buffer 0 registers[0]
    binary.BIG_ENDIAN.put_uint16 buffer 2 registers[1]
    return binary.BIG_ENDIAN.uint32 buffer 0

  /**
  Reads a signed 32-bit int from the given $address.

  This is a convenience function using $read_many. It assumes that the registers are stored in big-endian order.
  */
  read_int32 --address/int -> int:
    registers := read_many --address=address --register_count=2
    buffer := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 buffer 0 registers[0]
    binary.BIG_ENDIAN.put_uint16 buffer 2 registers[1]
    return binary.BIG_ENDIAN.int32 buffer 0

class InputRegisters extends RegisterReader:
  constructor.internal_ station/Station:
    super.internal_ station

  is_holding_ -> bool: return false

class HoldingRegisters extends RegisterReader:

  constructor.internal_ station/Station:
    super.internal_ station

  is_holding_ -> bool: return true

  /**
  Writes the $registers into the holding registers at the given $address.

  If the $registers list is empty, does nothing. In that case the server is not contacted.
  */
  write_many --address/int registers/List:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if registers.size == 0: return
    if not 1 <= registers.size <= 0x7D: throw "OUT_OF_RANGE"

    station_.logger_.debug "write_holding_registers" --tags={"address": address, "registers": registers}
    request := WriteHoldingRegistersRequest
      --address=address
      --registers=registers
    // In theory we don't need to deserialize the response, but this introduces some error checking.
    station_.bus_.send_ request --unit_id=station_.unit_id:
      WriteHoldingRegistersResponse.deserialize it

  /**
  Writes the given $value to a single holding register at the given $address.

  If $mask is given, then only writes the masked bits of $value, and keeps the current value for the remaining
    bits. Instead of reading and writing the register it uses the more efficient "Mask Write Register" command for
    this operation.

  # Advanced
  The Modbus "Mask Write Register" function (code 22, 0x16) takes an 'and_mask' and an 'or_mask'. Here,
    the $value and $mask parameters provide the same functionality. Given an 'and_mask' and an 'or_mask'
    mask, one can convert to $value and $mask as follows:
  ```
  value := or_mask
  mask := ~and_mask
  ```
  */
  write_single --address/int value/int --mask/int?=null:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"

    if mask:
      station_.logger_.debug "write_single" --tags={"address": address, "value": value, "mask": mask}
      // Our test-server doesn't implement the request correctly.
      // See https://github.com/riptideio/pymodbus/pull/961
      // As a work-around we bit-and the or-mask ourselves. It's cheap enough, so we can just do it all the time.
      request := MaskWriteRegisterRequest
        --address=address
        --and_mask=~mask
        --or_mask=(value & mask)  // The '&' should not be necessary. See above.
      station_.bus_.send_ request --unit_id=station_.unit_id: MaskWriteRegisterResponse.deserialize it
    else:
      station_.logger_.debug "write_single" --tags={"address": address, "value": value}
      request := WriteSingleRegisterRequest
        --address=address
        --value=value
      station_.bus_.send_ request --unit_id=station_.unit_id: WriteSingleRegisterResponse.deserialize it

  /**
  Combines a write operation with a read operation.

  Conceptually this operation is equivalent to doing a $write_many followed by a $read.

  If the $read_register_count is equal to 0, and the $write_values list is empty, does nothing.
    In that case the server is not contacted.
  Otherwise, if the $read_register_count equals 0, a simple write-operations is performed as if $write_many was called.
  Otherwise, if the $write_values is empty, a simple read-operations is performed as if $read was called.
  */
  write_read --read_address/int --read_register_count/int --write_address --write_values/List -> List:
    if not 0 <= read_address <= 0xFFFF: throw "OUT_OF_RANGE"
    if not 0 <= write_address <= 0xFFFF: throw "OUT_OF_RANGE"
    if read_register_count == 0 and write_values == 0: return []
    if read_register_count == 0:
      write_many --address=write_address write_values
      return []
    if write_values.is_empty:
      return read_many --address=read_address --register_count=read_register_count

    if not 1 <= read_register_count <= 0x7D: throw "OUT_OF_RANGE"
    if not 1 <= write_values.size <= 0x79: throw "OUT_OF_RANGE"

    station_.logger_.debug "write_read_holding_registers" --tags={
      "read-address": read_address,
      "read-count": read_register_count,
      "write-address": write_address,
      "write-values": write_values,
    }
    request := WriteReadMultipleRegistersRequest
      --write_address=write_address
      --write_registers=write_values
      --read_address=read_address
      --read_register_count=read_register_count
    response := station_.bus_.send_ request --unit_id=station_.unit_id:
      WriteReadMultipleRegistersResponse.deserialize it
    return (response as WriteReadMultipleRegistersResponse).registers

  /**
  Writes $value at $address.

  This is a convenience function using $write_many.

  Splits the $value byte-array inte 16-bit chunks (registers) and writes them to the station.
  */
  write_byte_array --address/int value/ByteArray -> none:
    registers := List (value.size + 1) / 2
    (value.size / 2).repeat: registers[it] = binary.BIG_ENDIAN.uint16 value it * 2
    if value.size % 2 == 1: registers[registers.size - 1] = value.last
    write_many --address=address registers

  /**
  Writes the given string $str to the given $address.

  This is a convenience function using $write_many.
  */
  write_string --address/int str/string:
    write_byte_array --address=address str.to_byte_array

  /**
  Writes $value to the given $address.

  This is a convenience function using $write_many.
  */
  write_float32 --address/int value/float:
    write_uint32 --address=address value.bits32

  /**
  Writes $value to the given $address.

  This is a convenience function using $write_many.
  */
  write_float --address/int value/float:
    buffer := ByteArray 8
    binary.BIG_ENDIAN.put_float64 buffer 0 value
    write_byte_array --address=address buffer


  /**
  Writes $value to the given $address.

  This is a convenience function using $write_many.
  */
  write_uint32 --address/int value/int:
    buffer := ByteArray 4
    binary.BIG_ENDIAN.put_int32 buffer 0 value
    registers := [binary.BIG_ENDIAN.uint16 buffer 0, binary.BIG_ENDIAN.uint16 buffer 2]
    write_many --address=address registers

/**
A bits reader for Modbus stations.

This is the base class for $DiscreteInputs and $Coils.
*/
abstract class BitsReader:
  station_/Station

  constructor.internal_ .station_:

  abstract is_coils_ -> bool

  /**
  Reads $bit_count bits starting at the given $address.

  Returns a byte-array of the read values. The least-significant bit corresponds to the coil/discrete-input at
    $address, the next bit to $address + 1, and so on. If $bit_count is not a multiple of 8, then the
    remaining bits in the last byte are padded with zeros.

  Note that Modbus maps address 0 to coil/discrete-input 1. This means that, in order to read
    coil/discrete-input N, one must provide address (N - 1).
  */
  read_many --address/int --bit_count/int -> ByteArray:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if bit_count == 0: return #[]
    if not 1 <= bit_count <= 2000: throw "OUT_OF_RANGE"

    station_.logger_.debug "$(is_coils_ ? "coils" : "discrete inputs").read_many"
        --tags={"address": address, "bit_count": bit_count}
    request := ReadBitsRequest
      --is_coils=is_coils_
      --address=address
      --bit_count=bit_count
    response := station_.bus_.send_ request --unit_id=station_.unit_id:
      ReadBitsResponse.deserialize it --is_coils=is_coils_
    return (response as ReadBitsResponse).bits

  /**
  Reads a single bit from the given $address.

  This is a convenience function using $read_many.

  Note that Modbus maps address 0 to coil/discrete-input 1. This means that, in order to read
    coil/discrete-input N, one must provide address (N - 1).
  */
  read_single --address/int -> bool:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"

    station_.logger_.debug "$(is_coils_ ? "coils" : "discrete inputs").read_single" --tags={"address": address}
    request := ReadBitsRequest
      --is_coils=is_coils_
      --address=address
      --bit_count=1
    response := station_.bus_.send_ request --unit_id=station_.unit_id:
      ReadBitsResponse.deserialize it --is_coils=is_coils_
    return (response as ReadBitsResponse).bits[0] != 0


class DiscreteInputs extends BitsReader:
  constructor.internal_ station/Station:
    super.internal_ station

  is_coils_ -> bool: return false


class Coils extends BitsReader:
  constructor.internal_ station/Station:
    super.internal_ station

  is_coils_ -> bool: return true

  /**
  Writes the given $values to the coils at the given $address.

  By default, all bits of the $values are written. The $count parameter can be used to write only
    a subset of the bits.

  If count is equal to 0, does nothing. In that case the server is not contacted.
  */
  write_many --address/int values/ByteArray --count=(values.size * 8):
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if count == 0: return
    if not 1 <= count <= 0x7B0: throw "OUT_OF_RANGE"
    if (count + 7) / 8 != values.size: throw "OUT_OF_RANGE"

    station_.logger_.debug "coils.write_many" --tags={"address": address, "values": values}
    request := WriteMultipleCoilsRequest
      --address=address
      --values=values
      --count=count
    station_.bus_.send_ request --unit_id=station_.unit_id:
      WriteMultipleCoilsResponse.deserialize it

  /**
  Writes the given boolean $value to a single coil at the given $address.
  */
  write_single --address/int value/bool:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    station_.logger_.debug "coils.write_single" --tags={"address": address, "value": value}
    request := WriteSingleCoilRequest
      --address=address
      --value=value
    station_.bus_.send_ request --unit_id=station_.unit_id:
      WriteSingleCoilResponse.deserialize it
