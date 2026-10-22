import sys, collections
sys.path.insert(0, '.')
import dbc
sp, ss, _, _ = dbc.load('../dbc/Spell.dbc')
spell = {r[0]: r for r in sp}
def st(o):
    try: return ss(o)
    except Exception: return ''
sl, sls, _, _ = dbc.load('../dbc/SkillLine.dbc')
cat = {r[0]: r[1] for r in sl}
src, _, _, _ = dbc.load('../dbc/SkillRaceClassInfo.dbc')
sla, _, _, _ = dbc.load('../dbc/SkillLineAbility.dbc')
# Rank chains (SupercededBySpell): the real spells, not their effect/tick helpers
chain = set()
classmask = {}
for r in sla:
    classmask[r[2]] = classmask.get(r[2], 0) | r[4]
    if r[8]:
        chain.add(r[2]); chain.add(r[8])
CLASSES = {1: 'WARRIOR', 2: 'PALADIN', 3: 'HUNTER', 4: 'ROGUE', 5: 'PRIEST', 6: 'DEATHKNIGHT', 7: 'SHAMAN', 8: 'MAGE', 9: 'WARLOCK', 11: 'DRUID'}
out = {}
for cid, cname in CLASSES.items():
    bit = 1 << (cid - 1)
    lines = {r[1] for r in src if r[3] & bit and cat.get(r[1]) == 7}
    ids = {}
    for r in sla:
        if r[1] in lines and r[2] in spell:
            s = spell[r[2]]
            if s[39] <= 0:          # trainers teach spells with a spell level
                continue
            key = (st(s[145]), st(s[162]))
            if not key[0] or not key[1].startswith('Rang'):
                continue            # only ranked spells need a rank-exact link
            ids.setdefault(key, set()).add(r[2])
    dup = {k: v for k, v in ids.items() if len(v) > 1}
    def pick(v):
        # The castable player spell: class mask on its skill row, not-shapeshift
        # attribute (helpers lack both), part of a rank chain; else the lowest ID
        def score(i):
            return ((classmask.get(i, 0) & bit) != 0, (spell[i][4] & 0x10000) != 0, i in chain, -i)
        return max(v, key=score)
    out[cname] = sorted(pick(v) for v in ids.values())
    for k, v in list(dup.items())[:6]:
        print('   ', k, sorted(v), '->', pick(v))
    print(cname, 'lines', len(lines), 'ranked', len(ids), 'dups', len(dup), list(dup.items())[:3])
import json
json.dump(out, open('../dbc/classids.json', 'w'))
print(sum(len(v) for v in out.values()))
