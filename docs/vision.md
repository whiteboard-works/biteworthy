# Vision — what BiteWorthy is, and where it goes

> The product thesis, the moat, and the arc. This is the "why" behind
> the roadmap. The phase plan lives in `roadmap.md`; this is the thing
> the phases are in service of.

## The thesis

Strip away the stack and BiteWorthy is **an accessibility tool wearing a
restaurant app's clothes.**

For roughly a third of adults — celiac, allergies, intolerances,
religious observance, lifestyle — a restaurant menu is a wall of text
that hides the two or three things they can safely eat. The status-quo
"solution" is interrogating a server, googling in the parking lot, the
social tax of being "the difficult one," and, for some, a genuine
medical gamble.

BiteWorthy inverts the menu: **scan it, and see only what's yours —
ranked by what you'll love.**

What it really gives back is **dignity and spontaneity** — the freedom to
walk into a place you didn't pre-vet and just *eat*.

## The three convictions (baked into the schema, not bolted on)

1. **Safety filters, taste ranks.** Safety is binary and honest; taste
   only reorders. The two are kept religiously separate in the data
   model, the API, and the copy — because conflating "you might not like
   this" with "this could hospitalize you" is the one unforgivable bug.
   (See `docs/schema.md`: avoid-lists hide; taste signals only sort.)

2. **Honest disclosure is the product.** Every hidden item shows *why*
   it's hidden, with a confidence level (`confirmed` / `suggested` /
   `inferred`) and a source (`human` / `ai` / `owner`). Strict mode hides
   anything not `confirmed`. In a domain where being wrong is dangerous,
   **trust isn't a feature — it's the entire moat.**

3. **The menu graph is crowd-built, ethically.** Anyone can scan;
   community edits land at `suggested` confidence and stay invisible to
   strict-mode users until an admin confirms them. Every scan makes the
   shared map better for the next person with the same allergy —
   contributing is an act of care, not extraction.

## The arc

**1 — Win the wedge (Durango).** A finite restaurant set + word-of-mouth
in a real town. Prove the core loop: *scan → eat → review → the data
gets better.* Resist going wide before the loop spins on its own.

**2 — Build the moat nobody else has: a structured,
dietary-annotated menu graph.** Menus live as unstructured PDFs and
photos; no one owns the clean version because no one will hand-maintain
it. AI + the crowd can. City by city, BiteWorthy accretes something
genuinely defensible — not an app, a **dataset of what's safe to eat in
America.**

**3 — Turn on the supply side.** The restaurant claim flow already
exists (Phase 4.9). Owners who maintain their own menu attract
constrained diners — who are loyal, higher-spend, and bring the whole
table. "BiteWorthy-safe" becomes a signal worth earning.

**4 — Deepen personalization.** Today the taste weights are constants in
code (`packages/filter-engine`, mirrored in SQL). Tomorrow they're
learned from behavior (taps, reviews, overrides), then "people like
you." The explainer line — *"because you love Thai and basil"* — becomes
a real model, never a black box.

**5 — Go ambient, then invisible.** Open-and-scan → "I'm on this block,
which 6 of these 40 places are safe *and* great for me?" (near-me,
deferred today on `expo-location`) → travel mode → reservation /
delivery integrations → eventually an API + badge other apps embed. The
endgame isn't more screen time; it's the question *"can I eat here?"*
answered before you have to ask.

## User stories

### Today (the app already does these)
- *As a celiac diner,* I scan a menu I've never seen and immediately see
  only the gluten-free dishes — so dinner stops being an interrogation.
- *As a parent of a tree-nut-allergic kid,* I turn on strict mode and
  only see items every association has `confirmed`, and the hidden ones
  tell me exactly **why** — so I can trust it with my child's safety.
- *As a vegan,* I get a "Top Picks for you — because you love spicy and
  basil" row above an already-safe menu — so I find the dish I'll love,
  fast.
- *As a traveler in a town that isn't listed,* I photograph the menu on
  the wall and 60 seconds later I'm reading my own filtered version — and
  I just made that restaurant exist for the next person like me.
- *As a returning diner,* I pull up a restaurant I filtered last month
  from my history and reuse it — no re-scanning.
- *As a contributor,* I swipe-verify a staged menu and watch it go live —
  strict users stay protected until an admin confirms my work.

### Soon (next phases)
- *As a low-FODMAP diner on a restaurant row,* I see "6 of these 40
  places have something safe *and* great for you" without opening each
  one (near-me).
- *As a caretaker,* I keep separate profiles for my partner's celiac and
  my own shellfish allergy and switch between them — or filter for *both*
  at once for a shared meal.
- *As someone observing halal,* I trust the religious-observance filter
  the same way the celiac trusts theirs — same honest-disclosure
  machinery, same confidence model.
- *As a frequent user,* my Top Picks quietly get smarter from what I tap,
  review, and override — without me ever managing settings.

### Horizon (the vision)
- *As an anxious traveler abroad,* I point my phone at a menu in another
  language and get a safe, ranked, translated read — the highest-stakes,
  highest-relief moment this product can own.
- *As a restaurant owner,* I claim my listing, keep my menu current, and
  earn a "BiteWorthy-safe" badge that brings in the loyal,
  high-spend constrained-diner crowd.
- *As a delivery / reservation app,* I embed BiteWorthy's safety layer so
  my own users can filter — and BiteWorthy becomes infrastructure, not a
  destination.
- *As anyone, anywhere,* the question *"can I eat here?"* is answered
  ambiently — by the time I've sat down, I already know.

## The one thing to protect

The wall between **safe** and **liked**, and the habit of always showing
**why**. The moment a low-scored item reads as "unsafe," or a hidden item
won't say its reason, the trust that makes this a medical-grade tool —
not just another restaurant app — is gone. Everything else is
negotiable. That isn't.
