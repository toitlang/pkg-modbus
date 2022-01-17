// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import net

import modbus

main:
  net := net.open
  socket := net.tcp_connect "localhost" 5502

  client := modbus.Client.tcp socket --server_address=1

  client.write_holding_registers 101 [42]
  client.write_holding_registers 102 [2]
  client.write_holding_registers 103 [44]

  print
    client.read_holding_registers 101 3
