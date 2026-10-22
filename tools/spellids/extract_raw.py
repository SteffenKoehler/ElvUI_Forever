import sys, glob, os, mpyq
root, out = sys.argv[1], sys.argv[2]
BS = chr(92)
wanted = [w.lower().replace('/', BS) for w in sys.argv[3:]]
files = sorted(glob.glob(os.path.join(root, '*.MPQ'))) + sorted(glob.glob(os.path.join(root, 'deDE', '*.MPQ')))
found = {}
for f in files:
    try:
        a = mpyq.MPQArchive(f, listfile=True)
    except Exception:
        continue
    for n in a.files or []:
        s = n.decode('latin-1')
        if s.lower() in wanted:
            found[s.lower()] = (f, s)
for key, (f, s) in found.items():
    data = mpyq.MPQArchive(f, listfile=True).read_file(s)
    name = s.split(BS)[-1]
    open(os.path.join(out, name), 'wb').write(data)
    print(name, len(data), os.path.basename(f))
