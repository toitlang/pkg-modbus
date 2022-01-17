// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import log
import monitor
import net.tcp

import .tcp
import .transport
import .framer
import .protocol

CLOSED_ERROR ::= "TRANSPORT_CLOSED"
SESSION_CLOSED_ERROR ::= "SESSION_CLOSED_ERROR"

/**
Modbus client to talk with a Modbus server. The client is initiated with
  the underlying transport, e.g. TcpTransport.
*/
class Client:
  transport_/Transport ::= ?
  sessions_ ::= Sessions_
  logger_/log.Logger
  server_address/int

  closed_ := false
  run_task_ := null
  next_identifier_ := 0

  constructor .transport_
      --auto_run=true
      --.server_address=255
      --logger/log.Logger=(log.default.with_name "modbus"):
    logger_ = logger
    // Run the client task, processing incoming data.
    if auto_run:
      run_task_ = task --background::
        e := catch --trace: run
        if e and e != CLOSED_ERROR:
          logger_.error "error processing transport" --tags={"error": e}
        run_task_ = null

  /**
  Convenience constructor for creating a new TCP Modbus Client.
  */
  constructor.tcp socket/tcp.Socket
      --framer/Framer=TcpFramer
      --auto_run=true
      --server_address/int=255:
    return Client
      TcpTransport socket --framer=framer
      --auto_run=auto_run
      --server_address=server_address

  // Close the client. It's okay to call close multiple times.
  close:
    closed_ = true  // Mark closed before delivering closed error to other clients.
    sessions_.abort CLOSED_ERROR
    transport_.close
    if run_task_: run_task_.cancel

  write_holding_registers address/int registers/List --preset_count/int=0:
    logger_.debug "write_holding_registers" --tags={"address": address, "registers": registers}
    identifier := next_identifier_++
    request := WriteHoldingRegistersRequest
      --address=address
      --registers=registers
      --preset_count=preset_count
    frame := Frame identifier server_address request.function_code request.to_byte_array
    sessions_.enter identifier
    try:
      transport_.write frame
      response_frame := sessions_.get_frame identifier
      response := WriteHoldingRegistersResponse.deserialize response_frame
    finally:
      sessions_.leave identifier

  read_holding_registers address/int count/int -> List:
    logger_.debug "read_holding_registers" --tags={"address": address, "count": count}
    identifier := next_identifier_++
    request := ReadHoldingRegistersRequest
      --address=address
      --count=count
    frame := Frame identifier server_address request.function_code request.to_byte_array
    sessions_.enter identifier
    try:
      transport_.write frame
      response_frame := sessions_.get_frame identifier
      response := ReadHoldingRegistersResponse.deserialize response_frame
      return response.registers
    finally:
      sessions_.leave identifier

  run -> none:
    try:
      while true:
        frame := transport_.read
        // Stop if transport was closed.
        if not frame:
          logger_.debug "underlying transport closed the connection"
          return
        if not sessions_.dispatch_frame frame:
        //  while response.message.payload.read:
          logger_.warn "unpaired response"
    finally:
      close

monitor Sessions_:
  sessions_ ::= {:}

  enter identifier:
    sessions_.update identifier --if_absent=null: throw "invalid identifier"

  leave identifier:
    sessions_.remove identifier

  get_frame identifier -> Frame:
    frame := null
    await: frame = sessions_.get identifier --if_absent=: SESSION_CLOSED_ERROR
    if sessions_.contains identifier: sessions_[identifier] = null
    return frame

  dispatch_frame frame/Frame -> bool:
    // Wait for the current message to be processed.
    await: not sessions_.get frame.identifier
    sessions_.update frame.identifier --if_absent=(:return false): frame
    return true

  abort error:
    // Terminate non-completed sessions with an closed error.
    sessions_.map --in_place: | identifier frame |
      frame ? frame : error
