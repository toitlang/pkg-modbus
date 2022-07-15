// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import log
import modbus
import net

import .test_server
import .common as common

main args:
  server_logger := (log.default.with_level log.INFO_LEVEL).with_name "server"
  with_test_server --logger=server_logger --mode="tcp":
    test it

test port/int:
  net := net.open
  socket := net.tcp_connect "localhost" port

  bus := modbus.Modbus.tcp socket

  station := bus.station modbus.Station.IGNORED_UNIT_ID
  common.test station

  bus.close
