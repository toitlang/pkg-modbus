// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary
import net.tcp
import reader
import writer
import .transport
import .framer


class TcpTransport implements Transport:
  framer/Framer

  socket_/tcp.Socket
  reader_/reader.BufferedReader
  writer_/writer.Writer

  constructor .socket_ --.framer=TcpFramer:
    reader_ = reader.BufferedReader socket_
    writer_ = writer.Writer socket_

  write frame/Frame:
    socket_.set_no_delay false
    framer.write frame writer_
    socket_.set_no_delay true

  read -> Frame?:
    return framer.read reader_

  close:
    socket_.close

class TcpFramer implements Framer:
  read reader/reader.BufferedReader -> Frame?:
    if not reader.can_ensure 8: return null
    header := reader.read_bytes 8
    identifier := binary.BIG_ENDIAN.uint16 header 0
    length := binary.BIG_ENDIAN.uint16 header 4
    address := binary.BIG_ENDIAN.uint8 header 6
    function_code := binary.BIG_ENDIAN.uint8 header 7
    data := reader.read_bytes length - 2
    return Frame identifier address function_code data

  write frame/Frame writer:
    header := ByteArray 8
    binary.BIG_ENDIAN.put_uint16 header 0 frame.identifier
    binary.BIG_ENDIAN.put_uint16 header 4 frame.data.size + 2
    binary.BIG_ENDIAN.put_uint8 header 6 frame.address
    binary.BIG_ENDIAN.put_uint8 header 7 frame.function_code
    writer.write header
    writer.write frame.data
