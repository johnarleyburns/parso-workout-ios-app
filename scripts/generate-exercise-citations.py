#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
data = json.loads((root / "CadenceCore/Sources/CadenceCore/Resources/free-exercise-db-plusplus.json").read_text())
refs = data["metadata"]["evidence"]["references"]
labels = {"systematic_review": "Systematic review", "experimental": "Experimental study", "meta_regression": "Meta-regression", "review_or_position": "Review / position statement", "training_intervention": "Training intervention", "randomized_controlled_trial": "Randomized controlled trial"}
lines = ["## Movement evidence (generated — do not hand-edit)", "", "These references back the DB++ muscle-role attributions, rather than coaching decisions. This block is regenerated from the bundled snapshot.", "", "<!-- BEGIN exercise-evidence -->"]
for key in sorted(refs):
    ref = refs[key]
    identifier = ref.get("pmid") or ref.get("doi") or ""
    lines.append(f"- `exdb.{key}` — {ref['title']}. **{labels.get(ref['type'], ref['type'])}**, {identifier}, {ref['url']}")
lines += ["<!-- END exercise-evidence -->", ""]
path = root / "docs/CITATIONS.md"
text = path.read_text()
start = text.find("## Movement evidence (generated — do not hand-edit)")
if start >= 0:
    text = text[:start].rstrip() + "\n"
path.write_text(text + "\n".join(lines))
