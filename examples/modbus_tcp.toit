// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import log
import net
import modbus

main:
  log.set_default (log.default.with_level log.INFO_LEVEL)

  net := net.open
  socket := net.tcp_connect "localhost" 5502

  bus := modbus.Modbus.tcp socket

  station := bus.station 1

  holding_registers := station.holding_registers

  holding_registers.write_many --address=101 [42]
  holding_registers.write_many --address=102 [2]
  holding_registers.write_many --address=103 [44]

  print
      holding_registers.read_many --address=101 --register_count=3


  // Some convenience functions:
  str := "1234 Hello æøå"
  holding_registers.write_string --address=300 str
  print
      holding_registers.read_string --address=300 --character_count=str.size


  float32 := 42.125
  holding_registers.write_float32 --address=300 float32
  print
      holding_registers.read_float32 --address=300

  uint32 := 42
  holding_registers.write_uint32 --address=300 uint32
  print
      holding_registers.read_uint32 --address=300


  input_registers := station.input_registers
  print
      input_registers.read_many --address=101 --register_count=3

  coils := station.coils
  bits := coils.read_many --address=100 --bit_count=15
  print bits

  discrete_inputs := station.discrete_inputs
  bits = discrete_inputs.read_many --address=100 --bit_count=15
  print bits

  bus.close
