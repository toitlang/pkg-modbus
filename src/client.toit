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
import .protocol as protocol
import .sugared

CLOSED_ERROR ::= "TRANSPORT_CLOSED"
TRANSACTION_CLOSED_ERROR ::= "TRANSACTION_CLOSED_ERROR"

/**
Modbus client to talk with a Modbus server. The client is initiated with
  the underlying transport, e.g. TcpTransport.
*/
class Client:
  static BROADCAST_UNIT_ID ::= 0
  static IGNORED_UNIT_ID ::= 255

  transactions_/TransactionManager_ ::= ?
  logger_/log.Logger

  closed_ := false
  sugared_/SugaredClient? := null

  constructor transport/Transport
      --auto_run=true
      --max_concurrent_transactions/int?=null
      --logger/log.Logger=(log.default.with_name "modbus"):
    if not max_concurrent_transactions:
      max_concurrent_transactions = transport.supports_parallel_sessions ? 16 : 1
    logger_ = logger
    transactions_ = TransactionManager_ transport
        --logger=logger
        --max_concurrent_transactions=max_concurrent_transactions
        --auto_run=auto_run

  /**
  Convenience constructor for creating a new TCP Modbus Client.
  */
  constructor.tcp socket/tcp.Socket
      --framer/Framer=TcpFramer
      --max_concurrent_transactions/int?=null
      --auto_run=true:
    return Client
      TcpTransport socket --framer=framer
      --auto_run=auto_run
      --max_concurrent_transactions=max_concurrent_transactions

  /**
  Returns a sugared client for working with alternative types on the client.
  */
  sugar -> SugaredClient:
    if closed_: throw "CLIENT_CLOSED"
    if not sugared_: sugared_ = SugaredClient this
    return sugared_

  /**
  Closes the client.

  May be called multiple times.
  */
  close:
    if closed_: return
    closed_ = true  // Mark closed before delivering closed error to other clients.
    transactions_.close

  /**
  Writes the $registers into the holding registers at the given $address.

  The server is identified by the $unit_id. The "unit id" is also known as "station address" or
    "server address". For Modbus TCP, it should almost always be equal to $IGNORED_UNIT_ID (the default).
    For Modbus RTU or Modbus ASCII, it needs to be set to the id of the server. If it is 0, then the
    client broadcasts the write request to all servers.
  */
  write_holding_registers --unit_id/int=IGNORED_UNIT_ID address/int registers/List --preset_count/int=0:
    if closed_: throw "CLIENT_CLOSED"
    logger_.debug "write_holding_registers" --tags={"address": address, "registers": registers}
    request := WriteHoldingRegistersRequest
      --address=address
      --registers=registers
      --preset_count=preset_count
    // In theory we don't need to deserialize the response, but this introduces some error checking.
    send_ request --unit_id=unit_id: WriteHoldingRegistersResponse.deserialize it

  /**
  Reads $count registers from the $address.

  The server is identified by the $unit_id. The "unit id" is also known as "station address" or
    "server address". For Modbus TCP, it should almost always be equal to $IGNORED_UNIT_ID (the default).
    For Modbus RTU or Modbus ASCII, it needs to be set to the id of the server. If it is 0, then the
    client broadcasts the read request to all servers.
  */
  read_holding_registers --unit_id/int=IGNORED_UNIT_ID address/int count/int -> List:
    if closed_: throw "CLIENT_CLOSED"
    logger_.debug "read_holding_registers" --tags={"address": address, "count": count}
    request := ReadHoldingRegistersRequest
      --address=address
      --count=count
    response := send_ request --unit_id=unit_id: ReadHoldingRegistersResponse.deserialize it
    return (response as ReadHoldingRegistersResponse).registers

  send_ --unit_id/int request/Request [deserialize_response] -> protocol.Response?:
    identifier := transactions_.enter
    try:
      frame := Frame identifier unit_id request.function_code request.to_byte_array
      transactions_.write identifier frame
      response_frame := transactions_.read identifier
      if unit_id == BROADCAST_UNIT_ID: return null
      return deserialize_response.call response_frame
    finally:
      transactions_.leave identifier

  run -> none:
    if closed_: throw "CLIENT_CLOSED"
    transactions_.run

/**
A transaction manager.

Depending on the underlying transport and framing a different number of transactions are allowed to
  the server.
The transaction manager keeps track of started transactions and assigns received responses to the
  correct transaction.
*/
class TransactionManager_:
  transport_/Transport
  logger_/log.Logger
  max_concurrent_transactions_/int?

  transactions_/Map ::= {:}
  signal_/monitor.Signal ::= monitor.Signal

  run_task_ := null
  next_identifier_ := 0
  closed_/bool := false

  constructor .transport_/Transport --logger/log.Logger --auto_run/bool --max_concurrent_transactions/int:
    logger_ = logger
    max_concurrent_transactions_ = max_concurrent_transactions

    // Run the read task, processing incoming data.
    if auto_run:
      run_task_ = task --background::
        e := catch: run
        if not closed_ and e and e != CLOSED_ERROR:
          logger_.error "error processing transport" --tags={"error": e}
        run_task_ = null

  /**
  Starts a new transaction.
  */
  enter -> int:
    signal_.wait: transactions_.size < max_concurrent_transactions_
    identifier := next_identifier_++
    transactions_.update identifier --if_absent=null: throw "invalid identifier"
    return identifier

  /**
  Ends the transaction with the given $identifier.

  If the manager later receives a message for this transaction it will be treated as an error.
  */
  leave identifier:
    transactions_.remove identifier
    // Allow new transactions to start and error out transactions that are stuck in $get_frame.
    signal_.raise

  /**
  Reads a frame for the transaction with the given $identifier.
  */
  read identifier -> Frame:
    response := null
    signal_.wait:
      response = transactions_.get identifier --if_absent=: throw TRANSACTION_CLOSED_ERROR
      response != null
    if transactions_.contains identifier: transactions_[identifier] = null
    if response is not Frame: throw response
    return response

  /**
  Writes a frame for the transaction with the given $identifier.
  */
  write identifier/int frame/Frame -> none:
    assert: frame.identifier == identifier
    transport_.write frame

  dispatch_ frame_or_exception -> bool:
    transaction_identifier := ?
    if frame_or_exception is Frame:
      transaction_identifier = frame_or_exception.identifier
    else if frame_or_exception is InvalidFrameException:
      transaction_identifier = frame_or_exception.transaction_identifier
    else:
      unreachable

    if transaction_identifier == Frame.NO_TRANSACTION_ID:
      // We are using a framer that doesn't support transactions.
      // That also means that there must be at most one transaction at a time.
      if transactions_.size > 1: throw "INVALID_STATE"
      if transactions_.is_empty:
        // Nobody is waiting anymore.
        return false
      transaction_identifier = transactions_.keys.first

    // There should never be more than one response frame for a given transaction.
    if (transactions_.get transaction_identifier) != null: return false
    transactions_.update transaction_identifier --if_absent=(:return false): frame_or_exception
    signal_.raise
    return true

  /**
  Closes the transaction manager.

  If there are existing transactions pending they are aborted with a $CLOSED_ERROR.
  */
  close:
    if closed_: return
    closed_ = true
    critical_do:
      // TODO(florian): should we close the transport even if we didn't create it?
      transport_.close
      // Terminate non-completed sessions with an closed error.
      transactions_.map --in_place: | _ frame |
        frame ? frame : CLOSED_ERROR
      signal_.raise
      if run_task_: run_task_.cancel

  run:
    try:
      while true:
        frame := null
        exception := catch --unwind=(: it is not InvalidFrameException):
          frame = transport_.read
        if exception:
          if not dispatch_ exception:
            logger_.warn "exception: $exception"
        else if not frame:
          // Stop if transport was closed.
          logger_.debug "underlying transport closed the connection"
          return
        else if not dispatch_ frame:
          logger_.warn "unpaired response or multiple responses"
    finally:
      close

