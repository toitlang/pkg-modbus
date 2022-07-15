// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import modbus
import modbus.exception as modbus

expect_modbus_exception code/int [block]:
  e := catch block
  expect e is modbus.ModbusException
  expect_equals code (e as modbus.ModbusException).code

/**
Tests that are shared between the modbus tcp and modbus serial tests.
*/
test station/modbus.Station --is_serial/bool=false:
  holding := station.holding_registers
  coils := station.coils
  input := station.input_registers
  discrete := station.discrete_inputs

  holding.write_many --address=50 [42]
  holding.write_many --address=51 [2]
  holding.write_many --address=52 [44]

  data := holding.read_many --address=50 --register_count=3
  expect_equals [42, 2, 44] data

  expect_equals 42 (holding.read_single --address=50)
  expect_equals 2 (holding.read_single --address=51)
  expect_equals 44 (holding.read_single --address=52)

  holding.write_many --address=50 [142, 102, 144]

  data = holding.read_many --address=50 --register_count=3
  expect_equals [142, 102, 144] data

  // The test server maps each holding register to a coil. If the register is 0, then the
  // coil is 0. Otherwise, the coil is 1.
  holding.write_many --address=0 [0, 1, 0, 1, 1, 0, 1, 1]
  bits := coils.read_many --address=0 --bit_count=8
  expect_equals #[0xda] bits
  expect_not (coils.read_single --address=0)
  expect (coils.read_single --address=1)
  expect_not (coils.read_single --address=2)
  expect (coils.read_single --address=3)
  expect (coils.read_single --address=4)
  expect_not (coils.read_single --address=5)
  expect (coils.read_single --address=6)
  expect (coils.read_single --address=7)

  bits = coils.read_many --address=0 --bit_count=5
  expect_equals #[0x1a] bits

  holding.write_many --address=8 [1, 0, 1, 0, 0, 1, 0, 1]
  bits = coils.read_many --address=8 --bit_count=8
  expect_equals #[0xa5] bits

  bits = coils.read_many --address=8 --bit_count=5
  expect_equals #[0x05] bits

  coils.write_single --address=9 true
  bits = coils.read_many --address=8 --bit_count=5
  expect_equals #[0x07] bits

  holding.write_single --address=50 499
  data = holding.read_many --address=50 --register_count=1
  expect_equals [499] data

  coils.write_many --address=0 #[0xA3]
  bits = coils.read_many --address=0 --bit_count=8
  expect_equals #[0xA3] bits

  coils.write_many --address=3 #[0xBA]
  bits = coils.read_many --address=3 --bit_count=8
  expect_equals #[0xBA] bits

  coils.write_many --address=1 #[0xFF]
  bits = coils.read_many --address=1 --bit_count=8
  expect_equals #[0xFF] bits

  coils.write_many --address=3 #[0x00] --count=3
  bits = coils.read_many --address=3 --bit_count=3
  expect_equals #[0x00] bits
  bits = coils.read_many --address=2 --bit_count=1
  expect_equals #[0x01] bits
  bits = coils.read_many --address=6 --bit_count=1
  expect_equals #[0x01] bits

  holding.write_single --address=42 0xFFFF
  holding.write_single --address=42 0x0000 --mask=0xAA55
  data = holding.read_many --address=42 --register_count=1
  expect_equals [0x55AA] data

  holding.write_single --address=42 0xAA55
  holding.write_single --address=42 0xFF00 --mask=0x0F0F
  data = holding.read_many --address=42 --register_count=1
  expect_equals [0xAF50] data

  holding.write_many --address=10 [0x1111, 0x2222, 0x3333, 0x4444]
  data = holding.write_read
      --write_address=11
      --write_values=[0x5555, 0x6666]
      --read_address=10
      --read_register_count=4
  expect_equals [0x1111, 0x5555, 0x6666, 0x4444] data

  holding.write_many --address=20 [0x1234, 0x5678, 0x1234]

  bytes := holding.read_byte_array --address=20 --byte_count=4
  expect_equals #[0x12, 0x34, 0x56, 0x78] bytes

  bytes = holding.read_byte_array --address=20 --byte_count=5
  expect_equals #[0x12, 0x34, 0x56, 0x78, 0x12] bytes

  holding.write_many --address=24 ['t' << 8 | 'o', 'i' << 8 | 't', '!' << 8 | '?']
  str := holding.read_string --address=24 --character_count=4
  expect_equals "toit" str
  holding.write_string --address=25 "toit"
  str = holding.read_string --address=25 --character_count=4
  expect_equals "toit" str

  holding.write_many --address=24 ['t' << 8 | 'o', 'i' << 8 | 't', '!' << 8 | '?']
  str = holding.read_string --address=24 --character_count=5
  expect_equals "toit!" str
  holding.write_string --address=27 "toit!"
  str = holding.read_string --address=27 --character_count=5

  f := 1.234567890123456789
  f_bytes64 := ByteArray 8: f.bits >> ((7 - it) * 8)
  holding.write_byte_array --address=40 f_bytes64
  expect_equals f (holding.read_float --address=40)
  holding.write_float --address=41 f
  expect_equals f (holding.read_float --address=41)

  // Round to 32 bit float.
  f32 := float.from_bits32 f.bits32
  expect (f32 - f).abs < 0.00001

  f_bytes32 := ByteArray 4: f32.bits32 >> ((3 - it) * 8)
  holding.write_byte_array --address=40 f_bytes32
  expect_equals f32 (holding.read_float32 --address=40)
  holding.write_float32 --address=41 f32
  expect_equals f32 (holding.read_float32 --address=41)

  holding.write_single --address=30 -1234
  expect_equals -1234 (holding.read_int16 --address=30)

  holding.write_many --address=20 [0x1234, 0x5678]
  num := holding.read_uint32 --address=20
  expect_equals 0x12345678 num
  holding.write_uint32 --address=21 0x12345678
  expect_equals 0x12345678 (holding.read_uint32 --address=21)

  // The test server separates holding registers and input registers.
  // The lower 80 entries of the input registers are set up for discrete inputs.
  // Starting at 80, they are equal to their index.
  data = input.read_many --address=90 --register_count=3
  expect_equals [ 90, 91, 92 ] data

  // The discrete inputs are set up such that every 8 consecutive bits are counting up
  // from 100.
  bits = discrete.read_many --address=0 --bit_count=8
  expect_equals #[100] bits

  bits = discrete.read_many --address=8 --bit_count=8
  expect_equals #[101] bits

  bits = discrete.read_many --address=(5 * 8) --bit_count=8
  expect_equals #[105] bits

  bits = discrete.read_many --address=(5 * 8) --bit_count=16
  expect_equals #[105, 106] bits

  if is_serial:
    server_id := station.read_server_id
    expect_equals "Toit Test Server" server_id.id_string
    expect server_id.is_on

  // We have configured the test server to only support 100 registers.
  expect_modbus_exception modbus.ModbusException.ILLEGAL_DATA_ADDRESS:
    holding.write_many --address=101 [1]
