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
  static DEFAULT-MAX-CONCURRENT-TRANSACTIONS ::= 16
  static READ-TIMEOUT-MS_ ::= 1_500

  transactions_/TransactionManager_ ::= ?
  logger_/log.Logger

  /**
  Creates a Modbus bus.

  The $transport encapsulates the physical layer and the framing.
  The $max-concurrent-transactions specifies how many transactions can be in progress at the same time. For
    transports that don't support concurrent transactions (like RS-485), this parameter is ignored. If none
    is provided, uses $DEFAULT-MAX-CONCURRENT-TRANSACTIONS.

  The $auto-run parameter specifies whether the bus should start its read task automatically. This is the default,
    and there are few reasons why users would want to change this. If the $auto-run is false, users need to call
    $run explicitly.
  */
  constructor transport/Transport
      --auto-run=true
      --max-concurrent-transactions/int?=null
      --logger/log.Logger=(log.default.with-name "modbus"):
    if not transport.supports-parallel-sessions:
      max-concurrent-transactions = 1
    else if not max-concurrent-transactions:
      max-concurrent-transactions = DEFAULT-MAX-CONCURRENT-TRANSACTIONS
    logger_ = logger
    transactions_ = TransactionManager_ transport
        --logger=logger
        --max-concurrent-transactions=max-concurrent-transactions
        --auto-run=auto-run

  /**
  Variant of $Modbus.constructor.
  Convenience constructor for creating a new TCP Modbus Client.
  */
  constructor.tcp socket/tcp.Socket
      --framer/Framer=TcpFramer
      --max-concurrent-transactions/int?=null
      --auto-run=true:
    return Modbus
        TcpTransport socket --framer=framer
        --auto-run=auto-run
        --max-concurrent-transactions=max-concurrent-transactions

  /**
  Variant of $Modbus.constructor.
  Convenience constructor for creating a new RTU Modbus Client.
  */
  constructor.rtu rs485-bus/rs485.Rs485
      --framer/Framer=(RtuFramer --baud-rate=rs485-bus.baud-rate)
      --auto-run=true:
    return Modbus
      Rs485Transport rs485-bus --framer=framer
      --auto-run=auto-run

  /**
  Variant of $Modbus.constructor.
  Convenience constructor for creating a new RTU Modbus Client.

  Deprecated. Use the constructor without `--baud_rate` instead.
  */
  constructor.rtu rs485-bus/rs485.Rs485
      --baud-rate/int
      --framer/Framer=(RtuFramer --baud-rate=baud-rate)
      --auto-run=true:
    return Modbus
      Rs485Transport rs485-bus --framer=framer
      --auto-run=auto-run

  /** Whether this bus is closed. */
  is-closed -> bool:
    return transactions_.is-closed

  /**
  Closes the bus.

  May be called multiple times.
  */
  close:
    transactions_.close

  /**
  Creates a station object representing a device on the bus.

  A station (aka server or slave) is identified by the $unit-id. The "unit id" is also known as "station address" or
    "server address". For Modbus TCP, it should almost always be equal to $Station.IGNORED-UNIT-ID (the default).
    For Modbus RTU or Modbus ASCII, it needs to be set to the id of the server.

  If the id is 0 (the $Station.BROADCAST-UNIT-ID), then the station is assumed to be used for broadcast
    messages. In that case messages don't expect a response and "read" functions will fail. Use the
    $force-non-broadcast flag to use a station with id 0 as a regular station.
  */
  station -> Station
      unit-id/int=Station.IGNORED-UNIT-ID
      --logger/log.Logger=logger_
      --force-non-broadcast/bool=false:
    is-broadcast := unit-id == Station.BROADCAST-UNIT-ID and not force-non-broadcast
    return Station.from-bus_ this unit-id --logger=logger --is-broadcast=is-broadcast

  broadcast-station --logger/log.Logger -> Station:
    return Station.from-bus_ this Station.BROADCAST-UNIT-ID --logger=logger --is-broadcast

  send_ --unit-id/int request/Request [deserialize-response] --is-broadcast/bool -> protocol.Response?:
    if is-closed: throw "BUS_CLOSED"
    id := transactions_.enter
    try:
      frame := Frame --transaction-id=id --unit-id=unit-id --function-code=request.function-code --data=request.to-byte-array
      transactions_.write id frame
      response-frame/Frame? := null
      if is-broadcast: return null
      with-timeout --ms=READ-TIMEOUT-MS_:
        response-frame = transactions_.read id
      return deserialize-response.call response-frame
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
  max-concurrent-transactions_/int?

  transactions_/Map ::= {:}
  signal_/Signal_ ::= Signal_

  run-task_ := null
  next-id_ := 0
  closed_/bool := false
  read-loop-is-running_ := false

  constructor .transport_/Transport --logger/log.Logger --auto-run/bool --max-concurrent-transactions/int:
    logger_ = logger
    max-concurrent-transactions_ = max-concurrent-transactions

    // Run the read task, processing incoming data.
    if auto-run:
      run-task_ = task --background::
        e := catch: run
        try:
          if not closed_ and e and e != CLOSED-ERROR:
            logger_.error "error processing transport" --tags={"error": e}
        finally:
          run-task_ = null

  /**
  Starts a new transaction.
  */
  enter -> int:
    signal_.wait: transactions_.size < max-concurrent-transactions_
    id := next-id_++
    transactions_.update id --if-absent=null: throw "invalid id"
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
      response = transactions_.get id --if-absent=: throw TRANSACTION-CLOSED-ERROR
      response != null
    if transactions_.contains id: transactions_[id] = null
    if response is not Frame: throw response
    return response

  /**
  Writes a frame for the transaction with the given $id.
  */
  write id/int frame/Frame -> none:
    assert: frame.transaction-id == id
    transport_.write frame

  dispatch_ frame-or-exception -> bool:
    transaction-id := ?
    if frame-or-exception is Frame:
      transaction-id = (frame-or-exception as Frame).transaction-id
    else if frame-or-exception is ModbusException:
      transaction-id = (frame-or-exception as ModbusException).transaction-id
    else:
      unreachable

    if transaction-id == Frame.NO-TRANSACTION-ID:
      // We are using a framer that doesn't support transactions.
      // That also means that there must be at most one transaction at a time.
      if transactions_.size > 1: throw "INVALID_STATE"
      if transactions_.is-empty:
        // Nobody is waiting anymore.
        return false
      transaction-id = transactions_.keys.first

    // There should never be more than one response frame for a given transaction.
    if (transactions_.get transaction-id) != null: return false
    transactions_.update transaction-id --if-absent=(:return false): frame-or-exception
    signal_.raise
    return true

  /** Whether the transaction manager is closed. */
  is-closed -> bool:
    return closed_

  /**
  Closes the transaction manager.

  If there are existing transactions pending they are aborted with a $CLOSED-ERROR.
  */
  close:
    if closed_: return
    closed_ = true
    critical-do:
      // TODO(florian): should we close the transport even if we didn't create it?
      transport_.close
      // Terminate non-completed sessions with an closed error.
      transactions_.map --in-place: | _ frame |
        frame ? frame : CLOSED-ERROR
      signal_.raise
      if run-task_: run-task_.cancel

  run:
    if read-loop-is-running_: throw "RUN_ALREADY_RUNNING"
    if closed_: throw "BUS_CLOSED"
    read-loop-is-running_ = true
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
      read-loop-is-running_ = false
      close

