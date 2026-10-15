// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import monitor
import modbus
import modbus.framer as modbus
import modbus.transport as modbus

/**
A transport that answers read-holding-registers requests itself.

Counts reads that happen outside a transaction, which a synchronous bus must
  never do.
*/
class FakeTransport implements modbus.TransactionTransport:
  registers/List
  responses_ := monitor.Channel 4
  in-transaction/bool := false
  transactions/int := 0
  reads-outside-transaction/int := 0
  drop-next-response/bool := false

  constructor .registers:

  supports-parallel-sessions -> bool: return false

  do-transaction [block] -> none:
    expect-not in-transaction
    transactions++
    in-transaction = true
    try:
      block.call
    finally:
      in-transaction = false

  write frame/modbus.Frame -> none:
    expect in-transaction
    expect-equals 3 frame.function-code
    if drop-next-response:
      drop-next-response = false
      return
    address := (frame.data[0] << 8) | frame.data[1]
    count := (frame.data[2] << 8) | frame.data[3]
    data := ByteArray 1 + count * 2
    data[0] = count * 2
    count.repeat:
      value := registers[address + it]
      data[1 + it * 2] = value >> 8
      data[2 + it * 2] = value & 0xff
    responses_.send (modbus.Frame
        --transaction-id=modbus.Frame.NO-TRANSACTION-ID
        --unit-id=frame.unit-id
        --function-code=frame.function-code
        --data=data)

  read -> modbus.Frame?:
    if not in-transaction: reads-outside-transaction++
    return responses_.receive

  close -> none:

main:
  test-requests
  test-timeout
  test-requires-synchronous

test-requests:
  transport := FakeTransport [0x41c8, 0xd836, 7, 8]
  bus := modbus.SynchronousModbus transport
  holding := (bus.station 1).holding-registers

  expect-equals [7, 8] (holding.read-many --address=2 --register-count=2)
  expect-equals (float.from-bits32 0x41c8_d836) (holding.read-float32 --address=0)
  expect-equals 2 transport.transactions

  // Concurrent requests are serialized.
  done := monitor.Semaphore
  3.repeat:
    task::
      expect-equals [7] (holding.read-many --address=2 --register-count=1)
      done.up
  3.repeat: done.down
  expect-equals 5 transport.transactions

  sleep --ms=10
  expect-equals 0 transport.reads-outside-transaction
  bus.close

test-timeout:
  transport := FakeTransport [1, 2]
  bus := modbus.SynchronousModbus transport --timeout=(Duration --ms=50)
  holding := (bus.station 1).holding-registers

  transport.drop-next-response = true
  start := Time.monotonic-us
  expect-throw DEADLINE-EXCEEDED-ERROR: holding.read-single --address=0
  elapsed-ms := (Time.monotonic-us - start) / 1000
  expect 50 <= elapsed-ms < 500

  // The bus recovers.
  expect-equals 2 (holding.read-single --address=1)
  bus.close

test-requires-synchronous:
  expect-throw "INVALID_ARGUMENT": modbus.Modbus (FakeTransport [])
