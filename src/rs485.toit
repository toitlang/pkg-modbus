// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary
import io
import log
import rs485
import .exception
import .framer
import .transport

/**
An RS-485 based transport.
*/
class Rs485Transport implements Transport:
  framer/Framer

  rs485_/rs485.Rs485
  reader_/io.Reader
  writer_/io.Writer

  constructor .rs485_
      --.framer=(RtuFramer --baud-rate=rs485_.baud-rate):
    reader_ = rs485_.in
    writer_ = rs485_.out

  supports-parallel-sessions -> bool: return false

  write frame/Frame:
    rs485_.do-transmission:
      framer.write frame writer_

  read -> Frame?:
    return framer.read reader_

  close:
    // TODO(florian): should we close the transceiver even though we didn't create it?
    rs485_.close

/**
A framer for remote-terminal units.
*/
class RtuFramer implements Framer:
  // The interframe delay that should be respected.
  inter-frame-delay-us/int
  last-activity-us_/int := ?
  inter-character-timeout-us_/int := ?

  constructor --baud-rate/int:
    // The inter-frame delay must be at least a delay corresponding to 3.5 characters of transmision.
    // The spec recommends to just use 1.750ms for any baud rate higher than 19200bps.
    if baud-rate > 19_200:
      inter-frame-delay-us = 1750
      inter-character-timeout-us_ = 750
    else:
      // A byte is sent with a start, stop and parity bit.
      // 3.5 * (8 + 3) = 38.5
      // For simplicity we round up to 40.
      inter-frame-delay-us = 40 * 1_000_000 / baud-rate
      // According to the spec the receiver should drop frames that have 1.5 char duration intervals between two
      // characters.
      // In other words we can assume that a packet has been fully received when we have a timeout of 1.5chars on
      // reading the serial port.
      // 1.5 * (8 + 3) = 16.5
      // We round up to 17.
      inter-character-timeout-us_ = 17 * 1_000_000 / baud-rate

    last-activity-us_ = Time.monotonic-us

  read reader/io.Reader -> Frame?:
    // RTU frames don't have any knowledge of how big they are.
    // Their size is determined by timing...
    //
    // Fortunately, modbus packets are tiny, so they are generally not fragmented.
    data := reader.read
    if data == null: return null
    catch --unwind=(: it != DEADLINE-EXCEEDED-ERROR):
      closed := false
      while not closed:
        with-timeout --us=inter-character-timeout-us_:
          chunk := reader.read
          if chunk == null:
            closed = true
    last-activity-us_ = Time.monotonic-us

    if data.size < 4:
      exception := ModbusException.noise
          --message="too short"
          --data=data
      throw exception

    unit-id := data[0]
    function-code := data[1]
    frame-data := data[2..data.size - 2]
    expected-crc := compute-crc_ data --to=(data.size - 2)
    given-crc := data[data.size - 1] << 8 | data[data.size - 2]
    if expected-crc != given-crc:
      exception := ModbusException.crc
          --transaction-id=Frame.NO-TRANSACTION-ID
          --message="CRC error"
          --frame-bytes=data
      throw exception

    transaction-id := Frame.NO-TRANSACTION-ID  // RTU does not have transaction identifiers.
    return Frame --transaction-id=transaction-id --unit-id=unit-id --function-code=function-code --data=frame-data

  compute-crc_ data/ByteArray --to/int -> int:
    // Specification modbus over serial line, v1.02,
    // Appendix B.
    // 6.2.2
    crc := 0xFFFF
    to.repeat:
      crc = crc ^ data[it]
      8.repeat:
        if (crc & 1) != 0:
          crc = (crc >> 1) ^ 0xA001
        else:
          crc >>= 1
    return crc

  write frame/Frame writer:
    // It is important to send all the data at once, since we must not have delays between characters.
    data := ByteArray (4 + frame.data.size)
    pos := 0
    data[pos++] = frame.unit-id
    data[pos++] = frame.function-code
    data.replace pos frame.data
    pos += frame.data.size
    crc := compute-crc_ data --to=pos
    // Store in big-endian.
    data[pos++] = crc & 0xFF
    data[pos++] = crc >> 8
    assert: pos == data.size

    now := Time.monotonic-us
    if last-activity-us_ + inter-frame-delay-us < now:
      sleep (Duration --us=(now - (last-activity-us_ + inter-frame-delay-us)))
    writer.write data
    last-activity-us_ = Time.monotonic-us
