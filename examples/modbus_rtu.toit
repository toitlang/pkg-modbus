// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import log
import modbus
import rs485

RX ::= 17
TX ::= 16
RTS ::= 18
BAUD-RATE ::= 9600

main:
  log.set-default (log.default.with-level log.INFO-LEVEL)

  rs485-bus := rs485.Rs485
      --rx=RX
      --tx=TX
      --rts=RTS
      --baud-rate=BAUD-RATE

  bus := modbus.Modbus.rtu rs485-bus

  station := bus.station 1

  holding-registers := station.holding-registers

  holding-registers.write-many --address=101 [42]
  holding-registers.write-many --address=102 [2]
  holding-registers.write-many --address=103 [44]

  print
      holding-registers.read-many --address=101 --register-count=3

  // See the TCP example for other modbus operations.

  bus.close
  rs485-bus.close
