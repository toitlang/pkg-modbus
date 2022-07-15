// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import modbus
import modbus.rs485 as modbus
import modbus.tcp as modbus
import net

main args:
  net := net.open
  port := int.parse args[0]

  socket := net.tcp_connect "localhost" port

  transport := modbus.TcpTransport socket --framer=(modbus.RtuFramer --baud_rate=9600)
  client := modbus.Client transport

  client.write_holding_registers --unit_id=1 50 [42]
  client.write_holding_registers --unit_id=1 51 [2]
  client.write_holding_registers --unit_id=1 52 [44]

  data := client.read_holding_registers --unit_id=1 50 3
  expect_equals [42, 2, 44] data

  expect_throw "Illegal Data Address": client.write_holding_registers --unit_id=2 101 [1]
  client.close
