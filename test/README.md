# Functional verification

From the repository root, run:

```sh
python3 test/run_functional.py
```

Requires `iverilog`, `vvp`, and Python 3. The runner generates deterministic
vectors in a temporary directory, compiles each bench with the actual RTL,
and fails on an assertion, simulator error, or timeout. It removes temporary
files afterward. The Python reference is checked against all four vectors in
Appendix I of the [original PRESENT paper](https://www.iacr.org/archive/ches2007/47270450/47270450.pdf)
before generating expected results.

| Bench | Checks |
| --- | --- |
| `primitives_tb.v` | All S-box inputs and lanes, every permutation bit, all 65,536 XOR input pairs, 93 key updates, ROM value |
| `bus_tb.v` | Walking bits in all five addresses, split key writes, full address decode, bus release, invalid addresses, write/read enables, side writes, collision priorities, asynchronous reset |
| `serial_tb.v` | 100 duplex transfers, walking bits and random data, MSB first, exactly 64 sample edges, TX input capture, busy start rejection, done pulse, abort and restart |
| `present_core_tb.v` | Four published vectors, 64 plaintext walking bits, 80 key walking bits, 128 random cases, 31-cycle processing, captured inputs, busy start rejection, done pulse, abort and restart |
| `top_flow_tb.v` | 36 full serial transactions per ROM configuration, start packet, programmed master key, received state, ciphertext, idle after completion, unused pins, EN abort during five phases, restart, EN/global-reset storage clearing |

The top bench drives the protocol through external pins and clock counts.
It observes internal registers only to verify clearing and the received state;
it does not use internal busy or controller state to schedule transactions.
The runner repeats the top bench with a nonzero ROM constant in a temporary
simulation copy of `key.v`, checking both bus key writes without modifying the
production all-zero ROM. This gives 72 full top vectors plus ten abort/restarts.

The cocotb test also uses only external pins and runs 16 blocks plus five
abort/restart scenarios. With the pinned dependencies installed:

```sh
python3 -m pip install -r test/requirements.txt
make -C test
python3 -m cocotb_tools.check_results test/results.xml
```

Both suites run in `.github/workflows/test.yaml`. Cocotb generates `test/tb.fst`
for waveform inspection. Gate simulation can be run with `make -C test GATES=yes`
after providing the generated netlist and PDK; RTL tests do not verify placement,
timing closure, or physical implementation.

# External serial timing

EN high clears writable storage and holds the controller in reset. The ROM
is a constant and remains available. EN low starts one transaction. The current
ROM key is all zero; every round XOR uses a 64-bit key derived from that
80-bit master. SDI is `ui_in[0]`, EN is `ui_in[1]`, SDO is `uo_out[0]`; addresses
and status remain internal.

All transfers are raw 8-byte packets, MSB first. The start byte is `A5`, followed
by seven zero bytes. Set SDI on falling edges, and sample SDO at rising edges
before the serializer advances. Count the first rising edge after EN falls as 1:

| Rising edges | Operation |
| --- | --- |
| 1–5 | Load ROM key, write start packet to TX, launch serializer |
| 6–69 | Sample the 64 start-packet bits on SDO |
| 70–73 | Clear TX and launch receive transfer |
| 74–137 | Present the 64 plaintext bits on SDI; SDO is zero |
| 138–174 | Transfer plaintext into state, run PRESENT and whitening, load TX, launch output |
| 175–238 | Sample the 64 ciphertext bits on SDO |
| After 238 | Remain idle until EN rises; EN high clears and allows another transaction |

The packet boundaries depend on these fixed clock counts because there is no
external busy or address pin. Changing controller latency requires updating
this protocol timing and the tests. The same clock drives serial and cipher
logic. EN should fall between clock edges with adequate setup time.
