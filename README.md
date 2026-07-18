# 🍟 mcoptimizer

Tell it what you want from McDonald's. It tells you **how to order it** — which deal to
apply, which reward to redeem your points on, and whether splitting into two separate
orders saves you money.

McDonald's has no public API, and deals are personalized per account — so instead of
scraping anything, you copy this week's deals from your app into the page (takes ~30
seconds) and the optimizer does the math.

## Use it

Open `index.html` in a browser — no build, no server, no dependencies. Everything you
enter (cart, prices, deals, points) is saved in `localStorage`.

1. **Your order** — add items. Prices are editable national ballparks; set them to what
   your store actually charges.
2. **Your points** — your MyMcDonald's balance.
3. **This week's deals** — copy them from the app. Supported shapes:
   - item for a fixed price ("Big Mac for $2")
   - bundle for a fixed price ("$5 Meal Deal")
   - buy one get one free
   - free item with a minimum purchase ("free fries with $1+")
   - % off the whole order
4. Hit **Optimize my order** for a specific cart — or **Show today's deal hacks**
   for the best plays available right now, cart or no cart.

## 🔥 Deal Hacks

Independent of any cart, the **Deal Hacks** panel ranks today's plays:

- every deal you entered, ordered by cash saved on its ideal items;
- every point redemption, ordered by ¢/point value, with the ones you can't yet
  afford dimmed;
- a headline **Deal Hack of the Day** — the single best deal + best affordable
  redemption, and whether to run them in one order or split them.

It's the "just tell me the best move" view; the full optimizer is for when you
already know exactly what you want to eat.

## What it models

- **Earning**: 100 points per $1 of cash spent.
- **Redemption tiers**: 1,500 / 3,000 / 4,500 / 6,000 points, using the US catalog
  (McChicken at 1,500, Medium Fries at 3,000, Big Mac at 6,000, etc. — see `data.js`).
- **App constraints**: at most **one deal** and **one reward redemption per order** —
  which is exactly why the solver may tell you to place two separate orders.
- **Point valuation**: every redemption is shown in ¢/point so you learn which tiers
  are actually worth it (a 1,500-pt McChicken ≈ 0.20¢/pt; a 6,000-pt Big Mac ≈ 0.09¢/pt).
  An optional threshold ("don't redeem below X ¢/point") stops the solver from burning
  points on low-value redemptions just to minimize today's cash.

The solver (`solver.js`, pure JS, no deps) enumerates every way to split the cart into
up to 3 orders, every applicable deal per order, and every redemption choice under your
points budget, then picks the plan with the lowest cash total (ties broken by fewer
points spent, then fewer orders). Carts are small, so brute force with memoization is
instant.

## Tests

```
node --test test/
```

## Caveats

- Prices vary by store; defaults are approximations. Edit them once — they persist.
- The rewards catalog rotates occasionally; update `data.js` if yours differs.
- Tax is not modeled.
- Whether the app allows a deal *and* a reward in the same order has varied over time —
  there's a toggle for it under **Options**.

Not affiliated with McDonald's Corporation in any way.
