// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import modbus
import modbus.exception as modbus

expect-modbus-exception code/int [block]:
  e := catch block
  expect e is modbus.ModbusException
  expect-equals code (e as modbus.ModbusException).code

/**
Tests that are shared between the modbus tcp and modbus serial tests.
*/
test station/modbus.Station --is-serial/bool=false:
  holding := station.holding-registers
  coils := station.coils
  input := station.input-registers
  discrete := station.discrete-inputs

  holding.write-many --address=50 [42]
  holding.write-many --address=51 [2]
  holding.write-many --address=52 [44]

  data := holding.read-many --address=50 --register-count=3
  expect-equals [42, 2, 44] data

  expect-equals 42 (holding.read-single --address=50)
  expect-equals 2 (holding.read-single --address=51)
  expect-equals 44 (holding.read-single --address=52)

  holding.write-many --address=50 [142, 102, 144]

  data = holding.read-many --address=50 --register-count=3
  expect-equals [142, 102, 144] data

  // The test server maps each holding register to a coil. If the register is 0, then the
  // coil is 0. Otherwise, the coil is 1.
  holding.write-many --address=0 [0, 1, 0, 1, 1, 0, 1, 1]
  bits := coils.read-many --address=0 --bit-count=8
  expect-equals #[0xda] bits
  expect-not (coils.read-single --address=0)
  expect (coils.read-single --address=1)
  expect-not (coils.read-single --address=2)
  expect (coils.read-single --address=3)
  expect (coils.read-single --address=4)
  expect-not (coils.read-single --address=5)
  expect (coils.read-single --address=6)
  expect (coils.read-single --address=7)

  bits = coils.read-many --address=0 --bit-count=5
  expect-equals #[0x1a] bits

  holding.write-many --address=8 [1, 0, 1, 0, 0, 1, 0, 1]
  bits = coils.read-many --address=8 --bit-count=8
  expect-equals #[0xa5] bits

  bits = coils.read-many --address=8 --bit-count=5
  expect-equals #[0x05] bits

  coils.write-single --address=9 true
  bits = coils.read-many --address=8 --bit-count=5
  expect-equals #[0x07] bits

  holding.write-single --address=50 499
  data = holding.read-many --address=50 --register-count=1
  expect-equals [499] data

  coils.write-many --address=0 #[0xA3]
  bits = coils.read-many --address=0 --bit-count=8
  expect-equals #[0xA3] bits

  coils.write-many --address=3 #[0xBA]
  bits = coils.read-many --address=3 --bit-count=8
  expect-equals #[0xBA] bits

  coils.write-many --address=1 #[0xFF]
  bits = coils.read-many --address=1 --bit-count=8
  expect-equals #[0xFF] bits

  coils.write-many --address=3 #[0x00] --count=3
  bits = coils.read-many --address=3 --bit-count=3
  expect-equals #[0x00] bits
  bits = coils.read-many --address=2 --bit-count=1
  expect-equals #[0x01] bits
  bits = coils.read-many --address=6 --bit-count=1
  expect-equals #[0x01] bits

  holding.write-single --address=42 0xFFFF
  holding.write-single --address=42 0x0000 --mask=0xAA55
  data = holding.read-many --address=42 --register-count=1
  expect-equals [0x55AA] data

  holding.write-single --address=42 0xAA55
  holding.write-single --address=42 0xFF00 --mask=0x0F0F
  data = holding.read-many --address=42 --register-count=1
  expect-equals [0xAF50] data

  holding.write-many --address=10 [0x1111, 0x2222, 0x3333, 0x4444]
  data = holding.write-read
      --write-address=11
      --write-values=[0x5555, 0x6666]
      --read-address=10
      --read-register-count=4
  expect-equals [0x1111, 0x5555, 0x6666, 0x4444] data

  holding.write-many --address=20 [0x1234, 0x5678, 0x1234]

  bytes := holding.read-byte-array --address=20 --byte-count=4
  expect-equals #[0x12, 0x34, 0x56, 0x78] bytes

  bytes = holding.read-byte-array --address=20 --byte-count=5
  expect-equals #[0x12, 0x34, 0x56, 0x78, 0x12] bytes

  holding.write-many --address=24 ['t' << 8 | 'o', 'i' << 8 | 't', '!' << 8 | '?']
  str := holding.read-string --address=24 --character-count=4
  expect-equals "toit" str
  holding.write-string --address=25 "toit"
  str = holding.read-string --address=25 --character-count=4
  expect-equals "toit" str

  holding.write-many --address=24 ['t' << 8 | 'o', 'i' << 8 | 't', '!' << 8 | '?']
  str = holding.read-string --address=24 --character-count=5
  expect-equals "toit!" str
  holding.write-string --address=27 "toit!"
  str = holding.read-string --address=27 --character-count=5

  f := 1.234567890123456789
  f-bytes64 := ByteArray 8: f.bits >> ((7 - it) * 8)
  holding.write-byte-array --address=40 f-bytes64
  expect-equals f (holding.read-float --address=40)
  holding.write-float --address=41 f
  expect-equals f (holding.read-float --address=41)

  // Round to 32 bit float.
  f32 := float.from-bits32 f.bits32
  expect (f32 - f).abs < 0.00001

  f-bytes32 := ByteArray 4: f32.bits32 >> ((3 - it) * 8)
  holding.write-byte-array --address=40 f-bytes32
  expect-equals f32 (holding.read-float32 --address=40)
  holding.write-float32 --address=41 f32
  expect-equals f32 (holding.read-float32 --address=41)

  holding.write-single --address=30 -1234
  expect-equals -1234 (holding.read-int16 --address=30)

  holding.write-many --address=20 [0x1234, 0x5678]
  num := holding.read-uint32 --address=20
  expect-equals 0x12345678 num
  holding.write-uint32 --address=21 0x12345678
  expect-equals 0x12345678 (holding.read-uint32 --address=21)

  // The test server separates holding registers and input registers.
  // The lower 80 entries of the input registers are set up for discrete inputs.
  // Starting at 80, they are equal to their index.
  data = input.read-many --address=90 --register-count=3
  expect-equals [ 90, 91, 92 ] data

  // The discrete inputs are set up such that every 8 consecutive bits are counting up
  // from 100.
  bits = discrete.read-many --address=0 --bit-count=8
  expect-equals #[100] bits

  bits = discrete.read-many --address=8 --bit-count=8
  expect-equals #[101] bits

  bits = discrete.read-many --address=(5 * 8) --bit-count=8
  expect-equals #[105] bits

  bits = discrete.read-many --address=(5 * 8) --bit-count=16
  expect-equals #[105, 106] bits

  if is-serial:
    server-id := station.read-server-id
    expect-equals "Toit Test Server" server-id.id-string
    expect server-id.is-on

  // We have configured the test server to only support 100 registers.
  expect-modbus-exception modbus.ModbusException.ILLEGAL-DATA-ADDRESS:
    holding.write-many --address=101 [1]
