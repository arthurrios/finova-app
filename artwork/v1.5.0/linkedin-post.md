# Finova v1.5.0 — LinkedIn post

- `finova-v1.5.0-carousel.pdf` — 10 pages, 576×576 pt (8×8 in) square, lossless. Upload as
  a LinkedIn **document** post.
- `1.png` … `10.png` — the same pages at 1200×1200, if you need stills.

Every capture comes from **one** simulator session on the v1.5.0 line
(`port/v1.5.0-parity`, app reports `Finova v1.5.0`), so the figures agree from slide to
slide.

| # | Slide | Container halo (where) | Zoom callout (what) |
|---|---|---|---|
| 1 | Hero — Finova, credit cards & smarter budgets | — | — |
| 2 | Credit cards (Chase Sapphire, Amex Platinum) | The Chase card cell | Closing / due / limit |
| 3 | New transaction, paid by card | The Payment Method block | "Goes to Sep statement — Due: 10/09/2026" |
| 4 | Statement detail (Chase, US$ 954,70) | The statement summary card | — (device already 1.4× scale) |
| 5 | Installment detail (MacBook Pro, 6/12) | Additional Details card | "Pay installments early — 7 available" |
| 6 | Early payment — choosing installments | The Future Installments card | "Amount paid early · US$ 600,00" |
| 7 | A prepaid installment, greyed out in Sep | — | The faded "MacBook Pro (7/12)" row |
| 8 | Month projection on the budget card | The projection card | "By Aug 31st US$24.0k / If fully used US$22.6k" |
| 9 | Allocations donut with tag totals | The Allocations section | The Market row: used / allocated |
| 10 | Tag → category picker (Essentials) | — (the list is the screen) | "Meals — In Lifestyle" |

## How features are pointed at

Nothing is drawn on the screenshot. Two devices do the work:

- **container halo** — a magenta glow around the parent card, built morphologically (fill the
  silhouette, dilate, keep the difference) so it is outside-only by construction and follows
  any shape. That is what lets slide 9's halo contour around the floating **+** button
  instead of running underneath it. Total reach stays near 10 px because the app's cards sit
  only ~20 px (slide space) from the screen edges. The layer is clipped to the screen
  aperture so a halo can never spill onto the bezel.
- **zoom callout** — the detail cropped out of the native 1206×2622 capture and enlarged onto
  a card on the gradient, joined by a hairline. Crops use whole detected rows so no icon or
  figure is ever clipped, and each card's vertical centre is set to its target's centre so
  connectors run roughly horizontally.

The callout is what an animated highlight was really for: it directs attention *and*
magnifies. That matters because LinkedIn rasterises each document page to a static image —
embedded PDF animation, JavaScript and page transitions are all dropped — so the detail has
to be legible standing still. Page 1 was checked at 240 px as the feed thumbnail.

**Container boxes are measured, never eyeballed.** `detect.py` finds a card's true bounds by
growing from a seed pixel (cards sit at grey 249 against a 240 page) with hairline-bridging
so internal dividers don't cut a container short. `verify_boxes.py` draws every proposed box
onto the captures first — that check is what caught slide 5's target sitting on "Cancel
purchase" instead of "Pay installments early".

---

## Caption

Finova v1.5.0 is out — and this one is about the card in your pocket. 💳

When you spend on credit, the money doesn't leave when you tap. It leaves on the due date,
on a statement that closed days earlier. Budgeting apps usually flatten that away. This
release doesn't.

**Credit Card Intelligence**
• Track multiple cards, each with its own closing day, due day and limit
• Choose cash or card as you enter a charge — cash hits your balance now, a card charge is
  routed to the cycle that actually contains it, so a purchase after the closing date lands
  on next month's statement, exactly like your issuer does it
• Open a statement to see its period, closing date, due date, total and every line on it
• Installments chain across statements instead of dumping the whole purchase on month one

**Pay ahead, on your terms**
• Pick any future installments and settle them early, in one tap
• The app tells you which open statement they'll be added to before you confirm
• An installment you've prepaid greys out in the month it would have been billed — because
  it no longer counts toward that month's budget

**Smarter budgets**
• See where the month is heading before it ends: projected balance, and what's left if every
  allocation is fully used
• Give every category its own slice of the budget, with unallocated spending tracked rather
  than lost
• Group categories into tags — Essentials, Lifestyle, Wellbeing — so you can ask what a whole
  set of categories costs, not just one line

**Under the hood**
• New `CreditCard` and `CreditCardStatement` models, with `CreditCardRepository`,
  `StatementRepository` and a `CreditCardService` that owns the cycle maths
• Schema migration adding the card and statement tables, plus card/statement foreign keys on
  transactions
• Statement re-shaping limited to cycles that haven't closed — an invoice you were already
  billed for is a historical record, not something to rewrite
• Allocation tags persist as a single versioned blob, sanitised on every read, so a mapping
  can never point at a deleted tag
• Still 100% programmatic UIKit, MVVM + flow controllers + factory-injected dependencies

Swift · UIKit · SQLite.swift · Firebase Auth · iOS 16+

Available on the App Store. If you carry a credit card and a budget at the same time, I'd
genuinely like to know whether this matches how you think about it. 👇

#iOSDevelopment #Swift #UIKit #IndieDev #PersonalFinance #MobileDevelopment #Finova
