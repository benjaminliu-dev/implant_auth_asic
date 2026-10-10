"""Pin-only protocol tests, usable with RTL or a gate-level top module."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from reference import encrypt


async def rising(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")


async def falling(dut):
    await FallingEdge(dut.clk)
    await Timer(1, unit="ns")


async def read_packet(dut):
    # Enter on the falling edge immediately before the first sample edge.
    packet = 0
    for index in range(64):
        packet = (packet << 1) | (int(dut.uo_out.value) & 1)
        await rising(dut)
        if index != 63:
            await falling(dut)
    return packet


async def start_session(dut):
    await falling(dut)
    dut.ui_in.value = 0
    for _ in range(12):
        await falling(dut)
        if int(dut.uo_out.value) & 1:
            break
    else:
        assert False, "start packet missing"
    assert await read_packet(dut) == 0xA500000000000000


async def send_block(dut, plaintext):
    await rising(dut, 4)
    for bit in range(63, -1, -1):
        await falling(dut)
        dut.ui_in.value = (plaintext >> bit) & 1
        assert int(dut.uo_out.value) == 0, "receive phase must transmit zero"
        await rising(dut)


async def clear(dut):
    await falling(dut)
    dut.ui_in.value = 2
    await Timer(10, unit="ns")
    assert int(dut.uo_out.value) == 0
    assert int(dut.uio_out.value) == 0
    assert int(dut.uio_oe.value) == 0
    await rising(dut, 3)


async def transaction(dut, plaintext):
    await start_session(dut)
    await send_block(dut, plaintext)
    await rising(dut, 37)
    await falling(dut)
    assert await read_packet(dut) == encrypt(plaintext, 0)
    await rising(dut, 10)
    assert int(dut.uo_out.value) == 0, "must remain idle until EN cycles"
    await clear(dut)


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def test_project(dut):
    dut.clk.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 1
    await Timer(1, unit="ns")
    dut.rst_n.value = 0
    dut.ui_in.value = 2
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await rising(dut, 3)
    await falling(dut)
    dut.rst_n.value = 1
    await clear(dut)
    rng = random.Random(80)
    for plaintext in [0, (1 << 64) - 1, 0x0123456789ABCDEF,
                      0x8000000000000001, *[rng.getrandbits(64) for _ in range(12)]]:
        await transaction(dut, plaintext)
    # Abort boot, start TX, RX, cipher rounds, and ciphertext TX, then restart.
    for cycles in (2, 20, 100, 145, 190):
        await falling(dut)
        dut.ui_in.value = 1
        await rising(dut, cycles)
        await clear(dut)
        await transaction(dut, 0)
