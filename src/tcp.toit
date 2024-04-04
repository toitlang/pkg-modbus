// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import net.tcp
import .transport
import .framer


class TcpTransport implements Transport:
  framer/Framer

  socket_/tcp.Socket
  reader_/io.Reader
  writer_/io.Writer

  constructor .socket_ --.framer=TcpFramer:
    reader_ = socket_.in
    writer_ = socket_.out

  supports-parallel-sessions -> bool: return true

  write frame/Frame:
    socket_.no-delay = false
    framer.write frame writer_
    socket_.no-delay = true

  read -> Frame?:
    return framer.read reader_

  close:
    socket_.close


class TcpFramer implements Framer:
  static HEADER-SIZE_ ::= 8

  read reader/io.Reader -> Frame?:
    if not reader.try-ensure-buffered HEADER-SIZE_: return null
    header := reader.read-bytes HEADER-SIZE_
    transaction-id := io.BIG-ENDIAN.uint16 header 0
    length := io.BIG-ENDIAN.uint16 header 4
    unit-id := io.BIG-ENDIAN.uint8 header 6
    function-code := io.BIG-ENDIAN.uint8 header 7
    data := reader.read-bytes length - 2
    return Frame --transaction-id=transaction-id --unit-id=unit-id --function-code=function-code --data=data

  write frame/Frame writer/io.Writer:
    // It is important to send the data in one go.
    // Modbus TCP should allow fragmented packets, but many devices do not.
    // By sending the data in one go, we minimize the risk of fragmentation.
    bytes := ByteArray HEADER-SIZE_ + frame.data.size
    io.BIG-ENDIAN.put-uint16 bytes 0 frame.transaction-id
    io.BIG-ENDIAN.put-uint16 bytes 4 frame.data.size + 2
    io.BIG-ENDIAN.put-uint8 bytes 6 frame.unit-id
    io.BIG-ENDIAN.put-uint8 bytes 7 frame.function-code
    bytes.replace HEADER-SIZE_ frame.data
    writer.write bytes
