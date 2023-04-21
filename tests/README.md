# Tests

The test server has been copied from the examples of the pymodbus library:
https://github.com/riptideio/pymodbus/blob/02a9417316b586ca11caa85ebf81728660c2ca75/examples/common/synchronous_server.py

The pymodbus library must be installed (see below), and is licensed under the BSD license.

It's not clear if the examples follow the same licensing or if they can be copied freely (like Toit's examples).
The safe choice is to consider them BSD as well.

## Installation

Install with

``` shell
pip install -U 'pymodbus==3.0.0.dev4' serial
```

Note: we can't currently open the serial port in Toit-desktop. The following instructions are thus not yet relevant.

To test the serial rtu client, create a pipe as follows:
``` shell
sudo socat -d -d pty,raw,echo=0,user-late=$USER,mode=600,link=/dev/ttyTest0 pty,raw,echo=0,user-late=$USER,mode=600,link=/dev/ttyTest1
# connect the master to /dev/ttyTest0
# connect the client to /dev/ttyTest1
```
