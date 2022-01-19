// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import net
import modbus

main:
  net := net.open
  socket := net.tcp_connect "localhost" 5502
  client := modbus.Client.tcp socket --server_address=1

  str := "1234 Hello æøå"
  client.sugar.write_string 300 str
  print
    client.sugar.read_string 300 str.size

  float32 := 42.125
  client.sugar.write_float32 300 float32
  print
    client.sugar.read_float32 300

  uint32 := 42
  client.sugar.write_uint32 300 uint32
  print
    client.sugar.read_uint32 300


  client.close
