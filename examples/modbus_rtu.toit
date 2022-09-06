// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import log
import modbus
import rs485

RX ::= 17
TX ::= 16
RTS ::= 18
BAUD_RATE ::= 9600

main:
  log.set_default (log.default.with_level log.INFO_LEVEL)

  pin_rx := gpio.Pin  RX
  pin_tx := gpio.Pin  TX
  pin_rts := gpio.Pin RTS

  rs485_bus := rs485.Rs485
      --rx=pin_rx
      --tx=pin_tx
      --rts=pin_rts
      --baud_rate=BAUD_RATE

  bus := modbus.Modbus.rtu rs485_bus

  station := bus.station 1

  holding_registers := station.holding_registers

  holding_registers.write_many --address=101 [42]
  holding_registers.write_many --address=102 [2]
  holding_registers.write_many --address=103 [44]

  print
    holding_registers.read_many --address=101 --register_count=3

  // See the TCP example for other modbus operations.

  bus.close
  rs485_bus.close
