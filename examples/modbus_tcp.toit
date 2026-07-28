// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import log
import net
import modbus

main:
  log.set-default (log.default.with-level log.INFO-LEVEL)

  net := net.open
  socket := net.tcp-connect "localhost" 5502

  bus := modbus.Modbus.tcp socket

  station := bus.station 1

  holding-registers := station.holding-registers

  holding-registers.write-many --address=101 [42]
  holding-registers.write-many --address=102 [2]
  holding-registers.write-many --address=103 [44]

  print
      holding-registers.read-many --address=101 --register-count=3


  // Some convenience functions:
  str := "1234 Hello æøå"
  holding-registers.write-string --address=300 str
  print
      holding-registers.read-string --address=300 --character-count=str.size


  float32 := 42.125
  holding-registers.write-float32 --address=300 float32
  print
      holding-registers.read-float32 --address=300

  uint32 := 42
  holding-registers.write-uint32 --address=300 uint32
  print
      holding-registers.read-uint32 --address=300


  input-registers := station.input-registers
  print
      input-registers.read-many --address=101 --register-count=3

  coils := station.coils
  bits := coils.read-many --address=100 --bit-count=15
  print bits

  discrete-inputs := station.discrete-inputs
  bits = discrete-inputs.read-many --address=100 --bit-count=15
  print bits

  bus.close
