"""Integer model; vectors from Appendix I of the original PRESENT paper.

https://www.iacr.org/archive/ches2007/47270450/47270450.pdf
"""
SBOX = (12, 5, 6, 11, 9, 0, 10, 13, 3, 14, 15, 8, 4, 7, 1, 2)
MASK80 = (1 << 80) - 1
KNOWN_VECTORS = (
    (0, 0, 0x5579C1387B228445),
    (0, MASK80, 0xE72C46C0F5945049),
    ((1 << 64) - 1, 0, 0xA112FFC72F68417B),
    ((1 << 64) - 1, MASK80, 0x3333DCD3213210D2),
)


def update_key(key, round_number):
    key = ((key << 61) | (key >> 19)) & MASK80
    key = (key & ((1 << 76) - 1)) | (SBOX[key >> 76] << 76)
    return key ^ (round_number << 15)


def substitute(state):
    return sum(SBOX[(state >> (4 * n)) & 15] << (4 * n) for n in range(16))


def permute(state):
    # Bit permutation expressed as a 4-by-16 matrix transpose.
    return sum(((state >> (4 * column + row)) & 1) << (16 * row + column)
               for row in range(4) for column in range(16))


def encrypt(plaintext, key):
    state = plaintext
    for round_number in range(1, 32):
        state = permute(substitute(state ^ (key >> 16)))
        key = update_key(key, round_number)
    return state ^ (key >> 16)
