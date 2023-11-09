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

CLOSED-ERROR ::= "TRANSPORT_CLOSED"
TRANSACTION-CLOSED-ERROR ::= "TRANSACTION_CLOSED_ERROR"

/**
The response to $Station.read-server-id.
*/
class ServerIdResponse:
  /** Device specific data, identifying the server. */
  id/ByteArray
  /** Whether the device is on or off. */
  is-on/bool

  constructor .id .is-on:

  /** The $id converted to a string. */
  id-string -> string: return id.to-string-non-throwing

  stringify -> string:
    return "$id-string ($(is-on ? "on" : "off"))"

/**
A Modbus client to talk with a specific station (aka Modbus server).
*/
class Station:
  static BROADCAST-UNIT-ID ::= 0
  static IGNORED-UNIT-ID ::= 255

  bus_/Modbus
  unit-id/int
  logger_/log.Logger

  discrete-inputs_ /DiscreteInputs? := null
  coils_ /Coils? := null
  input-registers_ /InputRegisters? := null
  holding-registers_ /HoldingRegisters? := null

  is-broadcast/bool

  constructor.from-bus_
      .bus_
      .unit-id
      --logger/log.Logger
      --.is-broadcast:
    logger_=logger

  /** Whether the underlying bus is closed. */
  is-bus-closed -> bool:
    return bus_.is-closed

  discrete-inputs -> DiscreteInputs:
    if not discrete-inputs_: discrete-inputs_ = DiscreteInputs.internal_ this
    return discrete-inputs_

  coils -> Coils:
    if not coils_: coils_ = Coils.internal_ this
    return coils_

  input-registers -> InputRegisters:
    if not input-registers_: input-registers_ = InputRegisters.internal_ this
    return input-registers_

  holding-registers -> HoldingRegisters:
    if not holding-registers_: holding-registers_ = HoldingRegisters.internal_ this
    return holding-registers_

  /**
  Reads the server identifaction.

  This function is only available for serial Modbus devices, although it may also work on some Modbus TCP devices.
  */
  read-server-id -> ServerIdResponse:
    if is-broadcast: throw "Can't read from broadcast station"
    logger_.debug "read_server_id" --tags={"unit_id": unit-id}
    request := ReportServerIdRequest
    response := bus_.send_ request --unit-id=unit-id --is-broadcast=false:
      ReportServerIdResponse.deserialize it
    server-response := response as ReportServerIdResponse
    return ServerIdResponse server-response.server-id server-response.on-off

/**
A register reader for Modbus stations.

This is the base class for $InputRegisters and $HoldingRegisters.
*/
// TODO(florian): should we extend/implement serial.Registers?
//   They are designed for byte-sized registers, but we could probably make it work for 16-bit registers.
abstract class RegisterReader:
  station_/Station

  constructor.internal_ .station_:

  abstract is-holding_ -> bool

  /**
  Reads $register-count registers starting at the given $address.

  Returns a list of 16-bit values.

  Note that Modbus maps address 0 to register 1. This means that, in order to read register N, one must
    provide address (N - 1).

  If the $register-count is equal to 0, does nothing. In that case the server is not contacted.
  */
  read-many --address/int --register-count/int -> List:
    if station_.is-broadcast: throw "Can't read from broadcast station"
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if register-count == 0: return []
    if not 1 <= register-count <= 125: throw "OUT_OF_RANGE"
    station_.logger_.debug "$(is-holding_ ? "holding" : "input")_registers.read_many" --tags={"address": address, "register_count": register-count}
    request := ReadRegistersRequest
      --holding=is-holding_
      --address=address
      --register-count=register-count
    response := station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=false:
      ReadRegistersResponse.deserialize it --holding=is-holding_
    return (response as ReadRegistersResponse).registers

  /**
  Reads a single register from the given $address.

  Returns the register value.

  Note that Modbus maps address 0 to register 1. This means that, in order to read register N, one must
    provide address (N - 1).

  This is a convenience function using $read-many.
  */
  read-single --address/int -> int:
    if station_.is-broadcast: throw "Can't read from broadcast station"
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    station_.logger_.debug "$(is-holding_ ? "holding" : "input")_registers.read_single" --tags={"address": address}
    request := ReadRegistersRequest
      --holding=is-holding_
      --address=address
      --register-count=1
    response := station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=false:
      ReadRegistersResponse.deserialize it --holding=is-holding_
    return (response as ReadRegistersResponse).registers[0]

  /**
  Reads $byte-count bytes starting at $address and returns the data as a $ByteArray.

  This is a convenience function using $read-many.
  */
  read-byte-array --address/int --byte-count/int -> ByteArray:
    register-count := (byte-count + 1) / 2
    registers := read-many --address=address --register-count=register-count
    bytes := ByteArray byte-count
    (byte-count / 2).repeat: binary.BIG-ENDIAN.put-uint16 bytes it * 2 registers[it]
    if byte-count % 2 == 1: bytes[bytes.size - 1] = registers.last >> 8
    return bytes

  /**
  Reads a $string of size $character-count bytes from the given $address.

  This is a convenience function using $read-many.
  */
  read-string --address/int --character-count/int -> string:
    bytes := read-byte-array --address=address --byte-count=character-count
    return bytes.to-string

  /**
  Reads a 64-bit float from the given $address.

  This is a convenience function using $read-many. It assumes that the registers are stored in big-endian order.
  */
  read-float --address/int -> float:
    bytes := read-byte-array --address=address --byte-count=8
    return float.from-bits
      binary.BIG-ENDIAN.int64 bytes 0

  /**
  Reads a 32-bit float from the given $address.

  This is a convenience function using $read-many. It assumes that the registers are stored in big-endian order.
  */
  read-float32 --address/int -> float:
    return float.from-bits32
      read-uint32 --address=address

  /**
  Reads a signed 16-bit int from the given $address.

  This is a convenience function using $read-many.
  */
  read-int16 --address/int -> int:
    registers := read-many --address=address --register-count=1
    result := registers[0]
    if 0x8000 & result == 0: return result
    return result - 0x10000

  /**
  Reads an unsigned 32-bit int from the given $address.

  This is a convenience function using $read-many. It assumes that the registers are stored in big-endian order.
  */
  read-uint32 --address/int -> int:
    registers := read-many --address=address --register-count=2
    buffer := ByteArray 4
    binary.BIG-ENDIAN.put-uint16 buffer 0 registers[0]
    binary.BIG-ENDIAN.put-uint16 buffer 2 registers[1]
    return binary.BIG-ENDIAN.uint32 buffer 0

  /**
  Reads a signed 32-bit int from the given $address.

  This is a convenience function using $read-many. It assumes that the registers are stored in big-endian order.
  */
  read-int32 --address/int -> int:
    registers := read-many --address=address --register-count=2
    buffer := ByteArray 4
    binary.BIG-ENDIAN.put-uint16 buffer 0 registers[0]
    binary.BIG-ENDIAN.put-uint16 buffer 2 registers[1]
    return binary.BIG-ENDIAN.int32 buffer 0

class InputRegisters extends RegisterReader:
  constructor.internal_ station/Station:
    super.internal_ station

  is-holding_ -> bool: return false

class HoldingRegisters extends RegisterReader:

  constructor.internal_ station/Station:
    super.internal_ station

  is-holding_ -> bool: return true

  /**
  Writes the $registers into the holding registers at the given $address.

  If the $registers list is empty, does nothing. In that case the server is not contacted.
  */
  write-many --address/int registers/List:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if registers.size == 0: return
    if not 1 <= registers.size <= 0x7D: throw "OUT_OF_RANGE"

    station_.logger_.debug "write_holding_registers" --tags={"address": address, "registers": registers}
    request := WriteHoldingRegistersRequest
      --address=address
      --registers=registers
    // In theory we don't need to deserialize the response, but this introduces some error checking.
    station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=station_.is-broadcast:
      it and WriteHoldingRegistersResponse.deserialize it

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
  write-single --address/int value/int --mask/int?=null:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"

    if mask:
      station_.logger_.debug "write_single" --tags={"address": address, "value": value, "mask": mask}
      // Our test-server doesn't implement the request correctly.
      // See https://github.com/riptideio/pymodbus/pull/961
      // As a work-around we bit-and the or-mask ourselves. It's cheap enough, so we can just do it all the time.
      request := MaskWriteRegisterRequest
        --address=address
        --and-mask=~mask
        --or-mask=(value & mask)  // The '&' should not be necessary. See above.
      station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=station_.is-broadcast:
        it and MaskWriteRegisterResponse.deserialize it
    else:
      station_.logger_.debug "write_single" --tags={"address": address, "value": value}
      request := WriteSingleRegisterRequest
        --address=address
        --value=value
      station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=station_.is-broadcast:
        it and WriteSingleRegisterResponse.deserialize it

  /**
  Combines a write operation with a read operation.

  Conceptually this operation is equivalent to doing a $write-many followed by a $read-many.

  If the $read-register-count is equal to 0, and the $write-values list is empty, does nothing.
    In that case the server is not contacted.
  Otherwise, if the $read-register-count equals 0, a simple write-operations is performed as if $write-many was called.
  Otherwise, if the $write-values is empty, a simple read-operations is performed as if $read-many was called.
  */
  write-read --read-address/int --read-register-count/int --write-address --write-values/List -> List:
    if station_.is-broadcast: throw "Can't read from broadcast station"
    if not 0 <= read-address <= 0xFFFF: throw "OUT_OF_RANGE"
    if not 0 <= write-address <= 0xFFFF: throw "OUT_OF_RANGE"
    if read-register-count == 0 and write-values == 0: return []
    if read-register-count == 0:
      write-many --address=write-address write-values
      return []
    if write-values.is-empty:
      return read-many --address=read-address --register-count=read-register-count

    if not 1 <= read-register-count <= 0x7D: throw "OUT_OF_RANGE"
    if not 1 <= write-values.size <= 0x79: throw "OUT_OF_RANGE"

    station_.logger_.debug "write_read_holding_registers" --tags={
      "read-address": read-address,
      "read-count": read-register-count,
      "write-address": write-address,
      "write-values": write-values,
    }
    request := WriteReadMultipleRegistersRequest
      --write-address=write-address
      --write-registers=write-values
      --read-address=read-address
      --read-register-count=read-register-count
    response := station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=false:
      WriteReadMultipleRegistersResponse.deserialize it
    return (response as WriteReadMultipleRegistersResponse).registers

  /**
  Writes $value at $address.

  This is a convenience function using $write-many.

  Splits the $value byte-array inte 16-bit chunks (registers) and writes them to the station.
  */
  write-byte-array --address/int value/ByteArray -> none:
    registers := List (value.size + 1) / 2
    (value.size / 2).repeat: registers[it] = binary.BIG-ENDIAN.uint16 value it * 2
    if value.size % 2 == 1: registers[registers.size - 1] = value.last
    write-many --address=address registers

  /**
  Writes the given string $str to the given $address.

  This is a convenience function using $write-many.
  */
  write-string --address/int str/string:
    write-byte-array --address=address str.to-byte-array

  /**
  Writes $value to the given $address.

  This is a convenience function using $write-many.
  */
  write-float32 --address/int value/float:
    write-uint32 --address=address value.bits32

  /**
  Writes $value to the given $address.

  This is a convenience function using $write-many.
  */
  write-float --address/int value/float:
    buffer := ByteArray 8
    binary.BIG-ENDIAN.put-float64 buffer 0 value
    write-byte-array --address=address buffer


  /**
  Writes $value to the given $address.

  This is a convenience function using $write-many.
  */
  write-uint32 --address/int value/int:
    buffer := ByteArray 4
    binary.BIG-ENDIAN.put-int32 buffer 0 value
    registers := [binary.BIG-ENDIAN.uint16 buffer 0, binary.BIG-ENDIAN.uint16 buffer 2]
    write-many --address=address registers

/**
A bits reader for Modbus stations.

This is the base class for $DiscreteInputs and $Coils.
*/
abstract class BitsReader:
  station_/Station

  constructor.internal_ .station_:

  abstract is-coils_ -> bool

  /**
  Reads $bit-count bits starting at the given $address.

  Returns a byte-array of the read values. The least-significant bit corresponds to the coil/discrete-input at
    $address, the next bit to $address + 1, and so on. If $bit-count is not a multiple of 8, then the
    remaining bits in the last byte are padded with zeros.

  Note that Modbus maps address 0 to coil/discrete-input 1. This means that, in order to read
    coil/discrete-input N, one must provide address (N - 1).
  */
  read-many --address/int --bit-count/int -> ByteArray:
    if station_.is-broadcast: throw "Can't read from broadcast station"
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if bit-count == 0: return #[]
    if not 1 <= bit-count <= 2000: throw "OUT_OF_RANGE"

    station_.logger_.debug "$(is-coils_ ? "coils" : "discrete inputs").read_many"
        --tags={"address": address, "bit_count": bit-count}
    request := ReadBitsRequest
      --is-coils=is-coils_
      --address=address
      --bit-count=bit-count
    response := station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=false:
      ReadBitsResponse.deserialize it --is-coils=is-coils_
    return (response as ReadBitsResponse).bits

  /**
  Reads a single bit from the given $address.

  This is a convenience function using $read-many.

  Note that Modbus maps address 0 to coil/discrete-input 1. This means that, in order to read
    coil/discrete-input N, one must provide address (N - 1).
  */
  read-single --address/int -> bool:
    if station_.is-broadcast: throw "Can't read from broadcast station"
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"

    station_.logger_.debug "$(is-coils_ ? "coils" : "discrete inputs").read_single" --tags={"address": address}
    request := ReadBitsRequest
      --is-coils=is-coils_
      --address=address
      --bit-count=1
    response := station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=false:
      ReadBitsResponse.deserialize it --is-coils=is-coils_
    return (response as ReadBitsResponse).bits[0] != 0


class DiscreteInputs extends BitsReader:
  constructor.internal_ station/Station:
    super.internal_ station

  is-coils_ -> bool: return false


class Coils extends BitsReader:
  constructor.internal_ station/Station:
    super.internal_ station

  is-coils_ -> bool: return true

  /**
  Writes the given $values to the coils at the given $address.

  By default, all bits of the $values are written. The $count parameter can be used to write only
    a subset of the bits.

  If count is equal to 0, does nothing. In that case the server is not contacted.
  */
  write-many --address/int values/ByteArray --count=(values.size * 8):
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    if count == 0: return
    if not 1 <= count <= 0x7B0: throw "OUT_OF_RANGE"
    if (count + 7) / 8 != values.size: throw "OUT_OF_RANGE"

    station_.logger_.debug "coils.write_many" --tags={"address": address, "values": values}
    request := WriteMultipleCoilsRequest
      --address=address
      --values=values
      --count=count
    station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=station_.is-broadcast:
      it and WriteMultipleCoilsResponse.deserialize it

  /**
  Writes the given boolean $value to a single coil at the given $address.
  */
  write-single --address/int value/bool:
    if not 0 <= address <= 0xFFFF: throw "OUT_OF_RANGE"
    station_.logger_.debug "coils.write_single" --tags={"address": address, "value": value}
    request := WriteSingleCoilRequest
      --address=address
      --value=value
    station_.bus_.send_ request --unit-id=station_.unit-id --is-broadcast=station_.is-broadcast:
      it and WriteSingleCoilResponse.deserialize it
