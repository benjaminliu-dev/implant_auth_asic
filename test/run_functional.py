#!/usr/bin/env python3
"""Run all functional RTL benches with Icarus and Python's standard library."""
import random
import subprocess
import tempfile
from pathlib import Path

from reference import KNOWN_VECTORS, encrypt, update_key

ROOT = Path(__file__).resolve().parents[1]


def main():
    for plaintext, key, ciphertext in KNOWN_VECTORS:
        assert encrypt(plaintext, key) == ciphertext, "reference fails published vector"
    rng = random.Random(0x50524553454E54)
    vectors = list(KNOWN_VECTORS)
    vectors += [(1 << bit, 0, encrypt(1 << bit, 0)) for bit in range(64)]
    vectors += [(0, 1 << bit, encrypt(0, 1 << bit)) for bit in range(80)]
    for _ in range(128):
        plaintext, key = rng.getrandbits(64), rng.getrandbits(80)
        vectors.append((plaintext, key, encrypt(plaintext, key)))
    blocks = [0, (1 << 64) - 1, 0x0123456789ABCDEF, 0x8000000000000001]
    blocks += [rng.getrandbits(64) for _ in range(32)]
    top_vectors = [(p, encrypt(p, 0)) for p in blocks]
    with tempfile.TemporaryDirectory(prefix="present-functional-") as directory:
        build = Path(directory)
        (build / "core_vectors.txt").write_text("".join(
            f"{p:016x} {k:020x} {c:016x}\n" for p, k, c in vectors))
        (build / "top_vectors.txt").write_text("".join(
            f"{p:016x} {c:016x}\n" for p, c in top_vectors))
        (build / "key_vectors.txt").write_text("".join(
            f"{k:020x} {r:02x} {update_key(k, r):020x}\n"
            for k in [0, (1 << 80) - 1, rng.getrandbits(80)] for r in range(1, 32)))
        sources = sorted(str(path) for path in (ROOT / "src").glob("*.v"))
        for bench in ("primitives_tb", "bus_tb", "serial_tb", "present_core_tb", "top_flow_tb"):
            executable = build / f"{bench}.vvp"
            subprocess.run(["iverilog", "-g2012", "-s", bench, "-o", str(executable),
                            str(ROOT / "test" / f"{bench}.v"), *sources], check=True)
            subprocess.run(["vvp", str(executable)], cwd=build, check=True, timeout=30)
        # A separate simulation copy of the hardwired ROM catches swapped/omitted
        # key chunks which the production all-zero ROM cannot expose.
        alternate_key = 0x0123456789ABCDEFFEDCB
        key_source = (ROOT / "src" / "key.v").read_text()
        literal = "80'h0000_0000_0000_0000_0000"
        assert key_source.count(literal) == 1, "update alternate-ROM fixture for new ROM"
        alternate_rom = build / "key_nonzero.v"
        alternate_rom.write_text(key_source.replace(literal, f"80'h{alternate_key:020x}"))
        (build / "top_vectors.txt").write_text("".join(
            f"{p:016x} {encrypt(p, alternate_key):016x}\n" for p in blocks))
        executable = build / "top_nonzero.vvp"
        subprocess.run(["iverilog", "-g2012", "-s", "top_flow_tb",
                        f"-Ptop_flow_tb.EXPECTED_MASTER_KEY=80'h{alternate_key:020x}",
                        f"-Ptop_flow_tb.RESTART_CIPHER=64'h{encrypt(0, alternate_key):016x}",
                        "-o", str(executable), str(ROOT / "test" / "top_flow_tb.v"),
                        *[s for s in sources if Path(s).name != "key.v"], str(alternate_rom)], check=True)
        subprocess.run(["vvp", str(executable)], cwd=build, check=True, timeout=30)
    print(f"PASS all five benches plus nonzero ROM fixture; {len(vectors)} core and "
          f"{2 * len(top_vectors)} top vectors", flush=True)


if __name__ == "__main__":
    main()
