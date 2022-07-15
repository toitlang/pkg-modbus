// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import net
import modbus

main:
  net := net.open
  socket := net.tcp_connect "localhost" 5502

  client := modbus.Client.tcp socket

  client.write_holding_registers --unit_id=1 101 [42]
  client.write_holding_registers --unit_id=1 102 [2]
  client.write_holding_registers --unit_id=1 103 [44]

  print
    client.read_holding_registers --unit_id=1 101 3

  client.close
