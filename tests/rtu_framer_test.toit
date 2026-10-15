// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import io
import modbus.framer as modbus
import modbus.rs485 as modbus

TEST-DATA_ ::= #[0x0a, 0x0b, 0x0c, 0x0d]

main:
  test-frame-bytes
  test-timings
  test-inter-frame-delay

frame -> modbus.Frame:
  return modbus.Frame
      --transaction-id=modbus.Frame.NO-TRANSACTION-ID
      --unit-id=1
      --function-code=2
      --data=TEST-DATA_

test-frame-bytes:
  framer := modbus.RtuFramer --baud-rate=9600
  buffer := io.Buffer
  framer.write frame buffer
  expect-equals #[0x01, 0x02, 0x0a, 0x0b, 0x0c, 0x0d, 0xce, 0xd5] buffer.bytes

  read := framer.read (io.Reader buffer.bytes)
  expect-equals 1 read.unit-id
  expect-equals 2 read.function-code
  expect-equals TEST-DATA_ read.data

/**
An $modbus.RtuFramer on a fake clock.

Records its sleeps instead of sleeping, and advances the clock by them.
*/
class FakeClockFramer extends modbus.RtuFramer:
  now/int := 0
  sleeps/List ::= []

  constructor --baud-rate/int:
    super --baud-rate=baud-rate

  now-us_ -> int:
    return now

  sleep_ --us/int -> none:
    sleeps.add us
    now += us

test-timings:
  // Baud rate, inter-frame delay, inter-character timeout.
  [
    [9600, 4166, 1770],
    [19200, 2083, 885],
    [38400, 1750, 750],
    [115200, 1750, 750],
  ].do: | row/List |
    framer := modbus.RtuFramer --baud-rate=row[0]
    expect-equals row[1] framer.inter-frame-delay-us
    expect-equals row[2] framer.inter-character-timeout-us_

test-inter-frame-delay:
  framer := FakeClockFramer --baud-rate=9600
  expect-equals 4166 framer.inter-frame-delay-us

  // Right after construction, the write waits for the whole delay.
  framer.write frame io.Buffer
  expect-equals [4166] framer.sleeps

  // Back to back, the second write waits for the whole delay too.
  framer.write frame io.Buffer
  expect-equals [4166, 4166] framer.sleeps

  // Partway through the delay, it waits for the rest.
  framer.now += 1000
  framer.write frame io.Buffer
  expect-equals [4166, 4166, 3166] framer.sleeps

  // Exactly at the end of the delay, or after it, the write goes out right away.
  framer.now += 4166
  framer.write frame io.Buffer
  framer.now += 100_000
  framer.write frame io.Buffer
  expect-equals [4166, 4166, 3166] framer.sleeps

  // Reading a frame counts as activity on the line.
  buffer := io.Buffer
  framer.write frame buffer
  expect-equals [4166, 4166, 3166, 4166] framer.sleeps
  framer.now += 100_000
  framer.read (io.Reader buffer.bytes)
  framer.write frame io.Buffer
  expect-equals [4166, 4166, 3166, 4166, 4166] framer.sleeps
