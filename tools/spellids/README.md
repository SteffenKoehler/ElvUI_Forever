# Class spell IDs for spellbook links

`spellbook.lua` ends with `CLASS_SPELL_IDS`: the ranked class spells of every class,
used to turn a trainer entry (name + rank) into a spell link with the right rank.

Regenerate (Python 3 with `mpyq`):

1. `python extract_raw.py <WoW>/Data dbc DBFilesClient/Spell.dbc DBFilesClient/SkillLineAbility.dbc DBFilesClient/SkillLine.dbc DBFilesClient/SkillRaceClassInfo.dbc`
2. run `genids.py` next to a `../dbc` folder holding those files; it writes `../dbc/classids.json`
3. paste the lists into the table at the end of `spellbook.lua`

Selection: skill lines of category 7 (class) per class mask, spells with a spell
level and a "Rang" rank text. Duplicates of one name + rank (effect/tick helpers)
are resolved towards the castable spell: class mask on its skill row, the
not-shapeshift attribute, part of a rank chain, else the lowest ID.
The rank filter matches the German client the list was generated with; at runtime
only the IDs are used (names come from GetSpellInfo).
