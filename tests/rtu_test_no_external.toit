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
import .test-server

main args:
  server-logger := (log.default.with-level log.INFO-LEVEL).with-name "server"
  with-test-server --logger=server-logger --mode="tcp_rtu":
    test it

test port/int:
  net := net.open

  socket := net.tcp-connect "localhost" port

  transport := modbus.TcpTransport socket --framer=(modbus.RtuFramer --baud-rate=9600)
  bus := modbus.Modbus transport

  station := bus.station 1
  common.test station --is-serial

  bad-station := bus.station 3
  expect-throw DEADLINE-EXCEEDED-ERROR:
    bad-station.holding-registers.write-many --address=101 [1]

  bus.close
