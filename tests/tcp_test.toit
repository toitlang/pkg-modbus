// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import modbus
import net

main args:
  net := net.open
  port := int.parse args[0]

  socket := net.tcp_connect "localhost" port

  client := modbus.Client.tcp socket

  client.write_holding_registers 50 [42]
  client.write_holding_registers 51 [2]
  client.write_holding_registers 52 [44]

  data := client.read_holding_registers --unit_id=1 50 3
  print data
  expect_equals [42, 2, 44] data

  client.close
