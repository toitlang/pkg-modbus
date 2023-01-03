// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import log
import monitor
import rs485
import net.tcp

import .exception
import .framer
import .protocol
import .protocol as protocol
import .station
import .transport
import .tcp
import .rs485

/**
The Modbus bus.

Represents the physical line. Use $station to talk to servers on the bus.
*/
class Modbus:
  static DEFAULT_MAX_CONCURRENT_TRANSACTIONS ::= 16
  static READ_TIMEOUT_MS_ ::= 1_500

  transactions_/TransactionManager_ ::= ?
  logger_/log.Logger

  /**
  Creates a Modbus bus.

  The $transport encapsulates the physical layer and the framing.
  The $max_concurrent_transactions specifies how many transactions can be in progress at the same time. For
    transports that don't support concurrent transactions (like RS-485), this parameter is ignored. If none
    is provided, uses $DEFAULT_MAX_CONCURRENT_TRANSACTIONS.

  The $auto_run parameter specifies whether the bus should start its read task automatically. This is the default,
    and there are few reasons why users would want to change this. If the $auto_run is false, users need to call
    $run explicitly.
  */
  constructor transport/Transport
      --auto_run=true
      --max_concurrent_transactions/int?=null
      --logger/log.Logger=(log.default.with_name "modbus"):
    if not transport.supports_parallel_sessions:
      max_concurrent_transactions = 1
    else if not max_concurrent_transactions:
      max_concurrent_transactions = DEFAULT_MAX_CONCURRENT_TRANSACTIONS
    logger_ = logger
    transactions_ = TransactionManager_ transport
        --logger=logger
        --max_concurrent_transactions=max_concurrent_transactions
        --auto_run=auto_run

  /**
  Variant of $Modbus.constructor.
  Convenience constructor for creating a new TCP Modbus Client.
  */
  constructor.tcp socket/tcp.Socket
      --framer/Framer=TcpFramer
      --max_concurrent_transactions/int?=null
      --auto_run=true:
    return Modbus
        TcpTransport socket --framer=framer
        --auto_run=auto_run
        --max_concurrent_transactions=max_concurrent_transactions

  /**
  Variant of $Modbus.constructor.
  Convenience constructor for creating a new RTU Modbus Client.
  */
  constructor.rtu rs485_bus/rs485.Rs485
      --framer/Framer=(RtuFramer --baud_rate=rs485_bus.baud_rate)
      --auto_run=true:
    return Modbus
      Rs485Transport rs485_bus --framer=framer
      --auto_run=auto_run

  /**
  Variant of $Modbus.constructor.
  Convenience constructor for creating a new RTU Modbus Client.

  Deprecated. Use the constructor without `--baud_rate` instead.
  */
  constructor.rtu rs485_bus/rs485.Rs485
      --baud_rate/int
      --framer/Framer=(RtuFramer --baud_rate=baud_rate)
      --auto_run=true:
    return Modbus
      Rs485Transport rs485_bus --framer=framer
      --auto_run=auto_run

  /** Whether this bus is closed. */
  is_closed -> bool:
    return transactions_.is_closed

  /**
  Closes the bus.

  May be called multiple times.
  */
  close:
    transactions_.close

  /**
  Creates a station object representing a device on the bus.

  A station (aka server or slave) is identified by the $unit_id. The "unit id" is also known as "station address" or
    "server address". For Modbus TCP, it should almost always be equal to $Station.IGNORED_UNIT_ID (the default).
    For Modbus RTU or Modbus ASCII, it needs to be set to the id of the server.

  If the id is 0 (the $Station.BROADCAST_UNIT_ID), then the station is assumed to be used for broadcast
    messages. In that case messages don't expect a response and "read" functions will fail. Use the
    $force_non_broadcast flag to use a station with id 0 as a regular station.
  */
  station -> Station
      unit_id/int=Station.IGNORED_UNIT_ID
      --logger/log.Logger=logger_
      --force_non_broadcast/bool=false:
    is_broadcast := unit_id == Station.BROADCAST_UNIT_ID and not force_non_broadcast
    return Station.from_bus_ this unit_id --logger=logger --is_broadcast=is_broadcast

  broadcast_station --logger/log.Logger -> Station:
    return Station.from_bus_ this Station.BROADCAST_UNIT_ID --logger=logger --is_broadcast

  send_ --unit_id/int request/Request [deserialize_response] --is_broadcast/bool -> protocol.Response?:
    if is_closed: throw "BUS_CLOSED"
    id := transactions_.enter
    try:
      frame := Frame --transaction_id=id --unit_id=unit_id --function_code=request.function_code --data=request.to_byte_array
      transactions_.write id frame
      response_frame/Frame? := null
      if is_broadcast: return null
      with_timeout --ms=READ_TIMEOUT_MS_:
        response_frame = transactions_.read id
      return deserialize_response.call response_frame
    finally:
      transactions_.leave id

  /**
  Runs the read loop.

  If the bus was created with the `--auto_run` flag set to true, then it's not necessary to call this function.

  The main reason to run this function would be to keep track of created tasks, or to handle errors better.
  */
  run:
    transactions_.run

/**
A signal synchronization primitive.

This class is a partial copy of the 'Signal' class from the 'monitor' library. Older
  versions of Toit don't have that class yet, and for backwards compatilibity we thus
  copied it here.
*/
monitor Signal_:
  /** Waits until the $condition is satisfied. */
  wait [condition] -> none:
    await: condition.call

  /** Raises the signal, making waiters evaluate their condition. */
  raise -> none:


/**
A transaction manager.

Depending on the underlying transport and framing a different number of transactions are allowed to
  the server.
The transpaction manager keeps track of started transactions and assigns received responses to the
  correct transaction.
*/
class TransactionManager_:
  transport_/Transport
  logger_/log.Logger
  max_concurrent_transactions_/int?

  transactions_/Map ::= {:}
  signal_/Signal_ ::= Signal_

  run_task_ := null
  next_id_ := 0
  closed_/bool := false
  read_loop_is_running_ := false

  constructor .transport_/Transport --logger/log.Logger --auto_run/bool --max_concurrent_transactions/int:
    logger_ = logger
    max_concurrent_transactions_ = max_concurrent_transactions

    // Run the read task, processing incoming data.
    if auto_run:
      run_task_ = task --background::
        e := catch: run
        try:
          if not closed_ and e and e != CLOSED_ERROR:
            logger_.error "error processing transport" --tags={"error": e}
        finally:
          run_task_ = null

  /**
  Starts a new transaction.
  */
  enter -> int:
    signal_.wait: transactions_.size < max_concurrent_transactions_
    id := next_id_++
    transactions_.update id --if_absent=null: throw "invalid id"
    return id

  /**
  Ends the transaction with the given $id.

  If the manager later receives a message for this transaction it will be treated as an error.
  */
  leave id:
    transactions_.remove id
    // Allow new transactions to start and error out transactions that are stuck in $get_frame.
    signal_.raise

  /**
  Reads a frame for the transaction with the given $id.
  */
  read id -> Frame:
    response := null
    signal_.wait:
      response = transactions_.get id --if_absent=: throw TRANSACTION_CLOSED_ERROR
      response != null
    if transactions_.contains id: transactions_[id] = null
    if response is not Frame: throw response
    return response

  /**
  Writes a frame for the transaction with the given $id.
  */
  write id/int frame/Frame -> none:
    assert: frame.transaction_id == id
    transport_.write frame

  dispatch_ frame_or_exception -> bool:
    transaction_id := ?
    if frame_or_exception is Frame:
      transaction_id = (frame_or_exception as Frame).transaction_id
    else if frame_or_exception is ModbusException:
      transaction_id = (frame_or_exception as ModbusException).transaction_id
    else:
      unreachable

    if transaction_id == Frame.NO_TRANSACTION_ID:
      // We are using a framer that doesn't support transactions.
      // That also means that there must be at most one transaction at a time.
      if transactions_.size > 1: throw "INVALID_STATE"
      if transactions_.is_empty:
        // Nobody is waiting anymore.
        return false
      transaction_id = transactions_.keys.first

    // There should never be more than one response frame for a given transaction.
    if (transactions_.get transaction_id) != null: return false
    transactions_.update transaction_id --if_absent=(:return false): frame_or_exception
    signal_.raise
    return true

  /** Whether the transaction manager is closed. */
  is_closed -> bool:
    return closed_

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
    if read_loop_is_running_: throw "RUN_ALREADY_RUNNING"
    if closed_: throw "BUS_CLOSED"
    read_loop_is_running_ = true
    try:
      while true:
        frame := null
        exception := catch --unwind=(: it is not ModbusException):
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
      read_loop_is_running_ = false
      close

