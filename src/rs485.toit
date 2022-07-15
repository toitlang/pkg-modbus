// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary
import log
import reader
import writer
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
  reader_/reader.BufferedReader
  writer_/writer.Writer

  constructor .rs485_
      --.framer=(RtuFramer --baud_rate=rs485_.baud_rate):
    reader_ = reader.BufferedReader rs485_
    writer_ = writer.Writer rs485_

  supports_parallel_sessions -> bool: return false

  write frame/Frame:
    rs485_.do_transmission:
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
  inter_frame_delay_us/int
  last_activity_us_/int := ?
  inter_character_timeout_us_/int := ?

  constructor --baud_rate/int:
    // The inter-frame delay must be at least a delay corresponding to 3.5 characters of transmision.
    // The spec recommends to just use 1.750ms for any baud rate higher than 19200bps.
    if baud_rate > 19_200:
      inter_frame_delay_us = 1750
      inter_character_timeout_us_ = 750
    else:
      // A byte is sent with a start, stop and parity bit.
      // 3.5 * (8 + 3) = 38.5
      // For simplicity we round up to 40.
      inter_frame_delay_us = 40 * 1_000_000 / baud_rate
      // According to the spec the receiver should drop frames that have 1.5 char duration intervals between two
      // characters.
      // In other words we can assume that a packet has been fully received when we have a timeout of 1.5chars on
      // reading the serial port.
      // 1.5 * (8 + 3) = 16.5
      // We round up to 17.
      inter_character_timeout_us_ = 17 * 1_000_000 / baud_rate

    last_activity_us_ = Time.monotonic_us

  read reader/reader.BufferedReader -> Frame?:
    // RTU frames don't have any knowledge of how big they are.
    // Their size is determined by timing...
    //
    // Fortunately, modbus packets are tiny, so they are generally not fragmented.
    data := reader.read
    if data == null: return null
    catch --unwind=(: it != DEADLINE_EXCEEDED_ERROR):
      closed := false
      while not closed:
        with_timeout --us=inter_character_timeout_us_:
          chunk := reader.read
          if chunk == null:
            closed = true
    last_activity_us_ = Time.monotonic_us

    unit_id := data[0]
    function_code := data[1]
    frame_data := data[2..data.size - 2]
    expected_crc := compute_crc_ data --to=(data.size - 2)
    given_crc := data[data.size - 1] << 8 | data[data.size - 2]
    if expected_crc != given_crc:
      exception := ModbusException.crc
          --transaction_id=Frame.NO_TRANSACTION_ID
          --message="CRC error"
          --frame_bytes=data
      throw exception

    transaction_id := Frame.NO_TRANSACTION_ID  // RTU does not have transaction identifiers.
    return Frame --transaction_id=transaction_id --unit_id=unit_id --function_code=function_code --data=frame_data

  compute_crc_ data/ByteArray --to/int -> int:
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
    data[pos++] = frame.unit_id
    data[pos++] = frame.function_code
    data.replace pos frame.data
    pos += frame.data.size
    crc := compute_crc_ data --to=pos
    // Store in big-endian.
    data[pos++] = crc & 0xFF
    data[pos++] = crc >> 8
    assert: pos == data.size

    now := Time.monotonic_us
    if last_activity_us_ + inter_frame_delay_us < now:
      sleep (Duration --us=(now - (last_activity_us_ + inter_frame_delay_us)))
    writer.write data
    last_activity_us_ = Time.monotonic_us
