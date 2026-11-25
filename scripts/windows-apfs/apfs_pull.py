# Read-only APFS pull from the raw macOS partition (never writes to the disk).
import os, sys, io, time, datetime
from dissect.apfs import APFS

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'apfs_out')
os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, 'pull2.log'), 'w', encoding='utf-8', buffering=1)
def P(*a):
    print(*a, file=log)

class Aligned(io.RawIOBase):
    """Sector-aligned reader over a raw Windows device, opened read-only."""
    SEC = 512
    def __init__(self, path, size):
        self.f = open(path, 'rb', buffering=0)
        self.pos = 0; self.size = size
    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos
    def read(self, n=-1):
        if n is None or n < 0: n = self.size - self.pos
        n = max(0, min(n, self.size - self.pos))
        if n == 0: return b''
        a = self.pos - self.pos % self.SEC
        e = self.pos + n; e = e + (-e) % self.SEC
        self.f.seek(a)
        buf = b''
        while len(buf) < e - a:
            chunk = self.f.read(min(e - a - len(buf), 1 << 20))
            if not chunk: break
            buf += chunk
        out = buf[self.pos - a:self.pos - a + n]
        self.pos += len(out)
        return out

DEV = r'\\.\Harddisk0Partition3'
SIZE = 393305067520
fs = APFS(Aligned(DEV, SIZE))
P('container', fs.uuid, 'block', fs.block_size)
data = None
for v in fs.volumes:
    P('volume', v.index, repr(v.name), v.role, 'enc=%s' % v.is_encrypted, 'sealed=%s' % v.is_sealed)
    if 'DATA' in str(v.role).upper() and data is None:
        data = v
if data is None:
    P('no data volume'); sys.exit(1)
P('using', repr(data.name))

def ls(path):
    try:
        d = data.get(path)
    except Exception as ex:
        P('ls fail', path, ex); return []
    rows = []
    for name, de in d.listdir().items():
        try:
            ino = de.inode
            rows.append((name, ino.size if ino.is_file() else -1, ino.mtime))
        except Exception as ex:
            rows.append((name, -2, None))
    return rows

def copy(path, dst):
    t = time.time()
    ino = data.get(path)
    size = ino.size
    s = ino.open()
    with open(dst, 'wb') as o:
        off = 0
        while off < size:
            s.seek(off)
            b = s.read(min(1 << 20, size - off))
            if not b:
                P('short read', path, off); break
            o.write(b); off += len(b)
    P('copied', path, os.path.getsize(dst), 'of', size, '%.1fs' % (time.time() - t))

since = datetime.datetime(2026, 11, 7, 0, 0, tzinfo=datetime.timezone.utc)

pers = '/private/var/db/diagnostics/Persist'
rows = sorted([r for r in ls(pers) if r[2]], key=lambda r: r[2])
for r in rows[-7:]:
    copy(pers + '/' + r[0], os.path.join(OUT, 'P_' + r[0]))
spec = '/private/var/db/diagnostics/Special'
for r in sorted([r for r in ls(spec) if r[2]], key=lambda r: r[2])[-3:]:
    copy(spec + '/' + r[0], os.path.join(OUT, 'S_' + r[0]))
P('DONE')
