#!/usr/bin/env python3

# Copied from https://github.com/riptideio/pymodbus/blob/02a9417316b586ca11caa85ebf81728660c2ca75/examples/common/synchronous_server.py
# The pymodbus library is licensed under the BSD license.

"""Pymodbus Synchronous Server Example.

The synchronous server is implemented in pure python without any third
party libraries (unless you need to use the serial protocols which require
pyserial). This is helpful in constrained or old environments where using
twisted is just not feasible. What follows is an example of its use:
"""
import logging
import sys

# from pymodbus.datastore import ModbusSparseDataBlock
from pymodbus.datastore import (ModbusSequentialDataBlock, ModbusServerContext,
                                ModbusSlaveContext)
from pymodbus.device import ModbusDeviceIdentification
# from pymodbus.server.sync import StartTlsServer
# from pymodbus.server.sync import StartUdpServer
from pymodbus.server.sync import StartSerialServer, StartTcpServer
from pymodbus.transaction import ModbusBinaryFramer, ModbusRtuFramer
# --------------------------------------------------------------------------- #
# import the various server implementations
# --------------------------------------------------------------------------- #
from pymodbus.version import version

# --------------------------------------------------------------------------- #
# configure the service logging
# --------------------------------------------------------------------------- #
FORMAT = (
    "%(asctime)-15s %(threadName)-15s"
    " %(levelname)-8s %(module)-15s:%(lineno)-8s %(message)s"
)
logging.basicConfig(format=FORMAT)
log = logging.getLogger()
log.setLevel(logging.DEBUG)


def run_server(kind):
    """Run server."""
    # ----------------------------------------------------------------------- #
    # initialize your data store
    # ----------------------------------------------------------------------- #
    # The datastores only respond to the addresses that they are initialized to
    # Therefore, if you initialize a DataBlock to addresses of 0x00 to 0xFF, a
    # request to 0x100 will respond with an invalid address exception. This is
    # because many devices exhibit this kind of behavior (but not all)::
    #
    #     block = ModbusSequentialDataBlock(0x00, [0]*0xff)
    #
    # Continuing, you can choose to use a sequential or a sparse DataBlock in
    # your data context.  The difference is that the sequential has no gaps in
    # the data while the sparse can. Once again, there are devices that exhibit
    # both forms of behavior::
    #
    #     block = ModbusSparseDataBlock({0x00: 0, 0x05: 1})
    #     block = ModbusSequentialDataBlock(0x00, [0]*5)
    #
    # Alternately, you can use the factory methods to initialize the DataBlocks
    # or simply do not pass them to have them initialized to 0x00 on the full
    # address range::
    #
    #     store = ModbusSlaveContext(di = ModbusSequentialDataBlock.create())
    #     store = ModbusSlaveContext()
    #
    # Finally, you are allowed to use the same DataBlock reference for every
    # table or you may use a separate DataBlock for each table.
    # This depends if you would like functions to be able to access and modify
    # the same data or not::
    #
    #     block = ModbusSequentialDataBlock(0x00, [0]*0xff)
    #     store = ModbusSlaveContext(di=block, co=block, hr=block, ir=block)
    #
    # The server then makes use of a server context that allows the server to
    # respond with different slave contexts for different unit ids. By default
    # it will return the same context for every unit id supplied (broadcast
    # mode).
    # However, this can be overloaded by setting the single flag to False and
    # then supplying a dictionary of unit id to context mapping::
    #
    #     slaves  = {
    #         0x01: ModbusSlaveContext(...),
    #         0x02: ModbusSlaveContext(...),
    #         0x03: ModbusSlaveContext(...),
    #     }
    #     context = ModbusServerContext(slaves=slaves, single=False)
    #
    # The slave context can also be initialized in zero_mode which means that a
    # request to address(0-7) will map to the address (0-7). The default is
    # False which is based on section 4.4 of the specification, so address(0-7)
    # will map to (1-8)::
    #
    #     store = ModbusSlaveContext(..., zero_mode=True)
    # ----------------------------------------------------------------------- #

    block1 = ModbusSequentialDataBlock(0, list(range(100)))
    block2_data = list(range(100))
    pos = 0
    for x in range(0, 10):
        val = 100 + x
        for y in range(0, 8):
            block2_data[pos] = (val & 1)
            pos += 1
            val >>= 1
    block2 = ModbusSequentialDataBlock(0, block2_data)

    store = ModbusSlaveContext(
        di=block2,
        co=block1,
        hr=block1,
        ir=block2,
        zero_mode=True
    )
    if kind == "tcp":
        context = ModbusServerContext(slaves=store, single=True)
    else:
        store2 = ModbusSlaveContext(
            di=ModbusSequentialDataBlock(0, list(range(100))),
            co=ModbusSequentialDataBlock(0, list(range(100))),
            hr=ModbusSequentialDataBlock(0, list(range(100))),
            ir=ModbusSequentialDataBlock(0, list(range(100))),
            zero_mode=True,
        )
        servers = {
            0x01: store,
            0x02: store2,
        }

        context = ModbusServerContext(slaves=servers, single=False)

    # ----------------------------------------------------------------------- #
    # initialize the server information
    # ----------------------------------------------------------------------- #
    # If you don"t set this or any fields, they are defaulted to empty strings.
    # ----------------------------------------------------------------------- #
    identity = ModbusDeviceIdentification(
        info_name={
            "VendorName": "Toit Test Server",
            #"ProductCode": "PM",
            #"VendorUrl": "http://github.com/riptideio/pymodbus/",
            #"ProductName": "Pymodbus Server",
            #"ModelName": "Pymodbus Server",
            #"MajorMinorRevision": version.short(),
        }
    )

    print("About to start server")
    sys.stdout.flush()
    # ----------------------------------------------------------------------- #
    # run the server you want
    # ----------------------------------------------------------------------- #
    # Tcp:
    if kind == "tcp":
        # Hack. Just fetch the port from the args.
        port = int(sys.argv[2])
        StartTcpServer(context, identity=identity, address=("127.0.0.1", port), allow_reuse_address=True)

    #
    # TCP with different framer

    elif kind == "tcp_rtu":
        port = int(sys.argv[2])
        StartTcpServer(context, identity=identity,
                    framer=ModbusRtuFramer,
                    address=("127.0.0.1", port), allow_reuse_address=True)

    # TLS
    # StartTlsServer(context, identity=identity,
    #                certfile="server.crt", keyfile="server.key", password="pwd",
    #                address=("0.0.0.0", 8020))

    # Tls and force require client"s certificate for TLS full handshake:
    # StartTlsServer(context, identity=identity,
    #                certfile="server.crt", keyfile="server.key", password="pwd", reqclicert=True,
    #                address=("0.0.0.0", 8020))

    # Udp:
    # StartUdpServer(context, identity=identity, address=("0.0.0.0", 5020))

    # socat -d -d PTY,link=/tmp/ptyp0,raw,echo=0,ispeed=9600 PTY,
    #             link=/tmp/ttyp0,raw,echo=0,ospeed=9600
    # Ascii:
    # StartSerialServer(context, identity=identity,
    #                    port="/dev/ttyp0", timeout=1)

    # RTU:
    elif kind == "rtu":
        # Hack. Just fetch the port from the args.
        port = sys.argv[2]
        StartSerialServer(context, framer=ModbusRtuFramer, identity=identity,
                        port=port, timeout=.005, baudrate=9600)

    # Binary
    # StartSerialServer(context,
    #                   identity=identity,
    #                   framer=ModbusBinaryFramer,
    #                   port="/dev/ttyp0",
    #                   timeout=1)

    else:
        raise "Unknown server kind"


if __name__ == "__main__":
    if len(sys.argv) < 2: raise "Missing argument"
    run_server(sys.argv[1])
