// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import log
import modbus
import modbus.rs485 as modbus
import modbus.tcp as modbus
import net

import .test_server

main args:
  server_logger := (log.default.with_level log.INFO_LEVEL).with_name "server"
  with_test_server --logger=server_logger --mode="tcp_rtu":
    test it

test port/int:
  net := net.open

  socket := net.tcp_connect "localhost" port

  transport := modbus.TcpTransport socket --framer=(modbus.RtuFramer --baud_rate=9600)
  client := modbus.Client transport

  client.write_holding_registers --unit_id=1 50 [42]
  client.write_holding_registers --unit_id=1 51 [2]
  client.write_holding_registers --unit_id=1 52 [44]

  data := client.read_holding_registers --unit_id=1 50 3
  expect_equals [42, 2, 44] data

  expect_throw "Illegal Data Address": client.write_holding_registers --unit_id=2 101 [1]
  // TODO(florian): enable this test again.
  //    Requires a timeout on tcp connections when reading a response.
  // expect_throw "Illegal Data Address": client.write_holding_registers --unit_id=3 101 [1]
  client.close
