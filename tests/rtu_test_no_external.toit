// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import log
import modbus
import modbus.rs485 as modbus
import modbus.tcp as modbus
import modbus.exception as modbus
import net

import .common as common
import .test_server

main args:
  server_logger := (log.default.with_level log.INFO_LEVEL).with_name "server"
  with_test_server --logger=server_logger --mode="tcp_rtu":
    test it

test port/int:
  net := net.open

  socket := net.tcp_connect "localhost" port

  transport := modbus.TcpTransport socket --framer=(modbus.RtuFramer --baud_rate=9600)
  bus := modbus.Modbus transport

  station := bus.station 1
  common.test station --is_serial

  bad_station := bus.station 3
  expect_throw DEADLINE_EXCEEDED_ERROR:
    bad_station.holding_registers.write_many --address=101 [1]

  bus.close
