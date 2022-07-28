// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import host.pipe
import log
import monitor
import net

SERVER_PYTHON_EXECUTABLE ::= "synchronous_server.py"

start_server mode/string:
  port /string? := null
  if mode == "tcp" or mode == "tcp_rtu":
    port = pipe.backticks "python" "third_party/ephemeral-port-reserve/ephemeral_port_reserve.py"
    port = port.trim
  else:
    throw "UNIMPLEMENTED"
  args := ["python", SERVER_PYTHON_EXECUTABLE, mode]
  if port: args.add port
  fork_data := pipe.fork
      true  // use_path.
      pipe.PIPE_INHERITED  // stdin.
      pipe.PIPE_CREATED  // stdout.
      pipe.PIPE_CREATED  // stderr.
      "python"  // program.
      args
  return [
    int.parse port,
    fork_data
  ]

with_test_server --logger/log.Logger --mode/string [block]:
  server_data := start_server mode
  port := server_data[0]
  logger.info "started modbus server on port $port"

  server_fork_data := server_data[1]

  server_is_running := monitor.Latch
  stdout_bytes := #[]
  stderr_bytes := #[]
  task::
    stdout /pipe.OpenPipe := server_fork_data[1]
    while chunk := stdout.read:
      logger.debug chunk.to_string.trim
      stdout_bytes += chunk
      full_str := stdout_bytes.to_string
      if full_str.contains "About to start server":
        server_is_running.set true
  task::
    stderr /pipe.OpenPipe := server_fork_data[2]
    while chunk := stderr.read:
      logger.debug chunk.to_string.trim
      stderr_bytes += chunk

  // Give the server a second to start.
  // If it didn't start we might be looking for the wrong line in its output.
  // There was a change between 1.6.9 and 2.0.14. Could be that there is
  // going to be another one.
  with_timeout --ms=1_000:
    server_is_running.get

  network := net.open

  // The "About to start server" message means that the server isn't yet fully running.
  // Make sure it is ready to accept connections.
  for i := 0; i < 10; i++:
    socket := null
    exception := catch:
      socket = network.tcp_connect "localhost" port
    if socket:
      socket.close
      break
    sleep --ms=(50 * i)

  try:
    block.call port
  finally: | is_exception _ |
    pid := server_fork_data[3]
    logger.info "killing modbus server"
    pipe.kill_ pid 15
    pipe.wait_for pid
    if is_exception:
      print stdout_bytes.to_string
      print stderr_bytes.to_string
