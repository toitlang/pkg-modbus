// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import io
import log
import modbus
import modbus.rs485 as modbus
import modbus.tcp as modbus
import modbus.exception as modbus
import modbus.framer as modbus
import net

import .common as common
import .test-server

class BadFramer implements modbus.Framer:
  wrapped_/modbus.Framer
  bad-next-read-bytes_/ByteArray? := null
  bad-next-read-frame_/modbus.Frame? := null
  eat-frame/bool := false
  last-response/modbus.Frame? := null

  constructor .wrapped_:

  read reader/io.Reader -> modbus.Frame:
    if bad-next-read-bytes_:
      data := bad-next-read-bytes_
      bad-next-read-bytes_ = null
      return wrapped_.read (io.Reader data)
    if bad-next-read-frame_:
      frame := bad-next-read-frame_
      bad-next-read-frame_ = null
      return frame
    if eat-frame:
      intercepted := wrapped_.read reader
      print_ intercepted
      sleep --ms=100000
    result := wrapped_.read reader
    // We check for the "eat-frame" after the 'read' as the
    // bus is reading the frames asynchronously before a request was sent.
    // That means that we enter the wrapped reader's read method before
    // the test has set the 'eat-frame' variable.
    if eat-frame:
      eat-frame = false
      return read reader
    last-response = result
    return result

  write frame/modbus.Frame writer/io.Writer:
    wrapped_.write frame writer

main args:
  server-logger := (log.default.with-level log.INFO-LEVEL).with-name "server"
  with-test-server --logger=server-logger --mode="tcp_rtu":
    test it

test port/int:
  net := net.open

  socket := net.tcp-connect "localhost" port

  original-framer := modbus.RtuFramer --baud-rate=9600
  framer := BadFramer original-framer
  transport := modbus.TcpTransport socket --framer=framer
  bus := modbus.Modbus transport

  station := bus.station 1
  holding := station.holding-registers
  holding.write-single --address=50 42
  holding.write-single --address=51 43

  // Check that a spurious read does not cause an error.
  // Note that the bus already started reading. So one frame will
  // make it through without errors, but the next one will have the
  // garbage.
  // The output of the test should show a
  //    "WARN: exception: Invalid frame: too short"
  // We simply do two reads.
  framer.bad-next-read-bytes_ = #[0x00, 0x01]
  data := holding.read-single --address=50
  expect-equals 42 data
  data = holding.read-single --address=51
  expect-equals 43 data

  // Check that the bus recovers when frames are lost.
  framer.eat-frame = true
  expect-throw DEADLINE-EXCEEDED-ERROR:
    holding.read-single --address=50
  framer.eat-frame = false

  // Check that the bus recovers when frames are lost.
  data = holding.read-single --address=50
  expect-equals 42 data

  // Send a valid response when no one is expecting it.
  framer.bad-next-read-frame_ = framer.last-response

  // When the next frame is set, the framer is already reading from the
  // uart. So we need to do one normal read which consumes the actual UART
  // data before the bad frame is used.
  // The output of the test should show a
  //   "WARN: unpaired response or multiple responses"
  data = holding.read-single --address=51
  expect-equals 43 data

  bus.close
