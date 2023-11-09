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

  supports-parallel-sessions -> bool: return true

  write frame/Frame:
    socket_.set-no-delay false
    framer.write frame writer_
    socket_.set-no-delay true

  read -> Frame?:
    return framer.read reader_

  close:
    socket_.close


class TcpFramer implements Framer:
  static HEADER-SIZE_ ::= 8

  read reader/reader.BufferedReader -> Frame?:
    if not reader.can-ensure HEADER-SIZE_: return null
    header := reader.read-bytes HEADER-SIZE_
    transaction-id := binary.BIG-ENDIAN.uint16 header 0
    length := binary.BIG-ENDIAN.uint16 header 4
    unit-id := binary.BIG-ENDIAN.uint8 header 6
    function-code := binary.BIG-ENDIAN.uint8 header 7
    data := reader.read-bytes length - 2
    return Frame --transaction-id=transaction-id --unit-id=unit-id --function-code=function-code --data=data

  write frame/Frame writer:
    // It is important to send the data in one go.
    // Modbus TCP should allow fragmented packets, but many devices do not.
    // By sending the data in one go, we minimize the risk of fragmentation.
    bytes := ByteArray HEADER-SIZE_ + frame.data.size
    binary.BIG-ENDIAN.put-uint16 bytes 0 frame.transaction-id
    binary.BIG-ENDIAN.put-uint16 bytes 4 frame.data.size + 2
    binary.BIG-ENDIAN.put-uint8 bytes 6 frame.unit-id
    binary.BIG-ENDIAN.put-uint8 bytes 7 frame.function-code
    bytes.replace HEADER-SIZE_ frame.data
    writer.write bytes
