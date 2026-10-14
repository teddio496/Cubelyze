"""Generate a tiny uncompressed QuickTime fixture without codec services."""
import struct
import sys
from pathlib import Path


def u32(*values):
    return struct.pack('>' + 'I' * len(values), *values)


def atom(kind, data):
    return u32(len(data) + 8) + kind.encode('ascii') + data


matrix = u32(65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824)
frames = [bytes([40 + i, 80, 120]) * (64 * 64) for i in range(60)]
mdat = atom('mdat', b''.join(frames))
mvhd = atom('mvhd', u32(0, 0, 0, 30, 60, 65536) + struct.pack('>H', 256) + b'\0' * 10 + matrix + b'\0' * 24 + u32(2))
tkhd = atom('tkhd', u32(7, 0, 0, 1, 0, 60) + b'\0' * 16 + matrix + u32(64 * 65536, 64 * 65536))
mdhd = atom('mdhd', u32(0, 0, 0, 30, 60) + b'\0' * 4)
hdlr = atom('hdlr', u32(0) + b'mhlrvide' + b'\0' * 12 + b'Video\0')
vmhd = atom('vmhd', u32(1) + b'\0' * 8)
dref = atom('dref', u32(0, 1) + atom('url ', u32(1)))
entry = (b'\0' * 6 + struct.pack('>H', 1) + b'\0' * 16 + struct.pack('>HH', 64, 64)
         + u32(72 * 65536, 72 * 65536, 0) + struct.pack('>H', 1)
         + b'\0' * 32 + struct.pack('>HH', 24, 65535))
stsd = atom('stsd', u32(0, 1) + atom('raw ', entry))
stts = atom('stts', u32(0, 1, 60, 1))
stsc = atom('stsc', u32(0, 1, 1, 60, 1))
stsz = atom('stsz', u32(0, len(frames[0]), 60))
stco = atom('stco', u32(0, 1, 8))
stbl = atom('stbl', stsd + stts + stsc + stsz + stco)
minf = atom('minf', vmhd + atom('dinf', dref) + stbl)
mdia = atom('mdia', mdhd + hdlr + minf)
moov = atom('moov', mvhd + atom('trak', tkhd + mdia))
Path(sys.argv[1]).write_bytes(mdat + moov)
