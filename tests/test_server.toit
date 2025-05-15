// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import host.pipe
import log
import monitor
import net

SERVER-PYTHON-EXECUTABLE ::= "synchronous_server.py"

start-server mode/string:
  port /string? := null
  if mode == "tcp" or mode == "tcp_rtu":
    port = pipe.backticks "python" "third_party/ephemeral-port-reserve/ephemeral_port_reserve.py"
    port = port.trim
  else:
    throw "UNIMPLEMENTED"
  args := ["python", SERVER-PYTHON-EXECUTABLE, mode]
  if port: args.add port
  process := pipe.fork
      --use-path
      --create-stdout
      --create-stderr
      "python"  // program.
      args
  return [
    int.parse port,
    process,
  ]

with-test-server --logger/log.Logger --mode/string [block]:
  server-data := start-server mode
  port := server-data[0]
  logger.info "started modbus server on port $port"

  server-process/pipe.Process := server-data[1]

  server-is-running := monitor.Latch
  stdout-bytes := #[]
  stderr-bytes := #[]
  task::
    stdout /pipe.Stream := server-process.stdout
    reader := stdout.in
    while chunk := reader.read:
      logger.debug chunk.to-string.trim
      stdout-bytes += chunk
      full-str := stdout-bytes.to-string
      if full-str.contains "About to start server":
        server-is-running.set true
  task::
    stderr /pipe.Stream := server-process.stderr
    reader := stderr.in
    while chunk := reader.read:
      logger.debug chunk.to-string.trim
      stderr-bytes += chunk

  // Give the server a second to start.
  // If it didn't start we might be looking for the wrong line in its output.
  // There was a change between 1.6.9 and 2.0.14. Could be that there is
  // going to be another one.
  with-timeout --ms=5_000:
    server-is-running.get

  network := net.open

  // The "About to start server" message means that the server isn't yet fully running.
  // Make sure it is ready to accept connections.
  for i := 0; i < 10; i++:
    socket := null
    exception := catch:
      socket = network.tcp-connect "localhost" port
    if socket:
      socket.close
      break
    sleep --ms=(50 * i)

  is-exception := true
  try:
    block.call port
    is-exception = false
  finally:
    pid := server-process.pid
    logger.info "killing modbus server"
    pipe.kill_ pid 15
    server-process.wait
    if is-exception:
      print stdout-bytes.to-string
      print stderr-bytes.to-string
