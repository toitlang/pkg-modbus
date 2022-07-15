# Tests

The python server has been copied from
https://github.com/riptideio/pymodbus/blob/02a9417316b586ca11caa85ebf81728660c2ca75/examples/common/synchronous_server.py

The pymodbus library is licensed under the BSD license.

## Installation

Install with

``` shell
pip install -U 'pymodbus>=3.0.0.dev4' serial
```

To test the serial rtu client, create a pipe as follows:
``` shell
sudo socat -d -d pty,raw,echo=0,user-late=$USER,mode=600,link=/dev/ttyTest0 pty,raw,echo=0,user-late=$USER,mode=600,link=/dev/ttyTest1
# connect the master to /dev/ttyTest0
# connect the client to /dev/ttyTest1
```
