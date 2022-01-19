import binary

import .client

/**
Sugared modbus client for writing various types across multiple holding registers.

All values are written in big endian, treating each register as two unsigned bytes.
*/
class SugaredClient:
  client/Client

  constructor .client:

  /**
  Reads a $ByteArray at $address.
  */
  read_byte_array address/int bytes_count/int -> ByteArray:
    register_count := bytes_count / 2 + bytes_count % 2
    registers := client.read_holding_registers address register_count
    bytes := ByteArray bytes_count
    (bytes_count / 2).repeat: binary.BIG_ENDIAN.put_uint16 bytes it * 2 registers[it]
    if bytes_count % 2 == 1: bytes[bytes.size - 1] = registers.last
    return bytes

  /**
  Writes $value at $address.
  */
  write_byte_array address/int value/ByteArray:
    registers := List value.size / 2 + value.size % 2
    (value.size / 2).repeat: registers[it] = binary.BIG_ENDIAN.uint16 value it * 2
    if value.size % 2 == 1: registers[registers.size - 1] = value.last
    client.write_holding_registers address registers

  /**
  Reads a $string at $address.
  */
  read_string address/int characters/int -> string:
    bytes := read_byte_array address characters
    return bytes.to_string

  /**
  Writes $value at $address.
  */
  write_string address/int value/string:
    write_byte_array address value.to_byte_array

  /**
  Reads a 32-bit float at $address.
  */
  read_float32 address/int -> float:
    return float.from_bits32
      read_uint32 address

  /**
  Writes $value at $address.
  */
  write_float32 address/int value/float:
    write_uint32 address value.bits32

  /**
  Reads an unsigned 32-bit int at $address.
  */
  read_uint32 address/int -> int:
    registers := client.read_holding_registers address 2
    bytes := ByteArray 4
    binary.BIG_ENDIAN.put_uint16 bytes 0 registers[0]
    binary.BIG_ENDIAN.put_uint16 bytes 2 registers[1]
    return binary.BIG_ENDIAN.uint32 bytes 0

  /**
  Writes $value at $address.
  */
  write_uint32 address/int value/int:
    bytes := ByteArray 4
    binary.BIG_ENDIAN.put_int32 bytes 0 value
    registers := [binary.BIG_ENDIAN.uint16 bytes 0, binary.BIG_ENDIAN.uint16 bytes 2]
    client.write_holding_registers address registers
