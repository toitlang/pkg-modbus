// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .bus
import .exception
import .station

export *

/**
Support for Modbus.

The Modbus protocol allows a client to communicate with different stations (aka "servers").
Typically, the transport layer of the bus is implemented on top of RS-485, or on top of TCP/IP.

Conceptually, when talking to a station, the client sends a request with an address and the object
  type that the client wants to access. The following types are supported:
- Coil (binary read/write).
- Discrete input (binary read-only).
- Input register (16-bit read-only).
- Holding register (16-bit read/write).
It is up to station whether addresses of different types map to the same memory location.

# Usage
Start by creating a bus. See $Modbus.constructor $Modbus.tcp, or $Modbus.rtu.
Then get a handle to a station ($Modbus.station), where you can then select the object type you are interested
  in: $Station.coils, $Station,discrete_inputs, $Station.input_registers, $Station.holding_registers.

# Example
```
import net
import modbus

main:
  net := net.open
  socket := net.tcp_connect "localhost" 5502

  bus := modbus.Modbus.tcp socket
  station := bus.station 1
  registers := station.holding_registers

  registers.write_many --address=101 [42]
```
*/
