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
  fork-data := pipe.fork
      true  // use_path.
      pipe.PIPE-INHERITED  // stdin.
      pipe.PIPE-CREATED  // stdout.
      pipe.PIPE-CREATED  // stderr.
      "python"  // program.
      args
  return [
    int.parse port,
    fork-data
  ]

with-test-server --logger/log.Logger --mode/string [block]:
  server-data := start-server mode
  port := server-data[0]
  logger.info "started modbus server on port $port"

  server-fork-data := server-data[1]

  server-is-running := monitor.Latch
  stdout-bytes := #[]
  stderr-bytes := #[]
  task::
    stdout /pipe.OpenPipe := server-fork-data[1]
    reader := stdout.in
    while chunk := reader.read:
      logger.debug chunk.to-string.trim
      stdout-bytes += chunk
      full-str := stdout-bytes.to-string
      if full-str.contains "About to start server":
        server-is-running.set true
  task::
    stderr /pipe.OpenPipe := server-fork-data[2]
    reader := stderr.in
    while chunk := reader.read:
      logger.debug chunk.to-string.trim
      stderr-bytes += chunk

  // Give the server a second to start.
  // If it didn't start we might be looking for the wrong line in its output.
  // There was a change between 1.6.9 and 2.0.14. Could be that there is
  // going to be another one.
  with-timeout --ms=1_000:
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

  try:
    block.call port
  finally: | is-exception _ |
    pid := server-fork-data[3]
    logger.info "killing modbus server"
    pipe.kill_ pid 15
    pipe.wait-for pid
    if is-exception:
      print stdout-bytes.to-string
      print stderr-bytes.to-string
