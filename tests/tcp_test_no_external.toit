// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import log
import modbus
import net

import .test-server
import .common as common

main args:
  server-logger := (log.default.with-level log.INFO-LEVEL).with-name "server"
  with-test-server --logger=server-logger --mode="tcp":
    test it

test port/int:
  net := net.open
  socket := net.tcp-connect "localhost" port

  bus := modbus.Modbus.tcp socket

  station := bus.station modbus.Station.IGNORED-UNIT-ID
  common.test station

  bus.close
