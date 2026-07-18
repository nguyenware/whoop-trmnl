/*
 * mcoptimizer solver — pure logic, no dependencies.
 * Works in the browser (window.McSolver) and in Node (module.exports).
 *
 * Model:
 *  - A cart is a list of "units" (one entry per individual item):
 *      { item: string, price: number, rewardPoints: number|null }
 *  - Deals (at most ONE per order):
 *      { kind: 'item_price',   item, price }            — named item for a fixed price
 *      { kind: 'bundle_price', items: [..], price }     — all listed items together for a fixed price
 *      { kind: 'bogo',         item }                   — buy one get one free
 *      { kind: 'free_with_min', item, minSpend }        — named item free with a minimum cash spend
 *      { kind: 'pct_off',      pct, minSpend? }         — % off the whole order (optional minimum)
 *    Deals may carry a `label` for display.
 *  - Rewards (at most ONE redemption per order): a unit with rewardPoints != null
 *    can be paid with points instead of cash, subject to the shared points balance.
 *  - The cart may be split into up to opts.maxOrders separate orders so that
 *    multiple deals/rewards can be used.
 *
 * optimize(units, deals, opts) minimizes total cash, tie-breaking on fewer
 * points spent, then fewer orders.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.McSolver = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const round2 = (x) => Math.round(x * 100) / 100;

  // Try to apply `deal` to the units of one order.
  // Returns { overrides: Map(unitIndex -> price), pctOff, minSpend } or null if inapplicable.
  function applyDeal(units, deal) {
    const overrides = new Map();
    const base = { overrides, pctOff: 0, minSpend: 0 };
    if (!deal) return base;
    switch (deal.kind) {
      case 'item_price': {
        const i = units.findIndex((u) => u.item === deal.item);
        if (i === -1) return null;
        overrides.set(i, deal.price);
        return base;
      }
      case 'bundle_price': {
        const taken = [];
        for (const item of deal.items) {
          const i = units.findIndex((u, idx) => u.item === item && !taken.includes(idx));
          if (i === -1) return null;
          taken.push(i);
        }
        taken.forEach((i, k) => overrides.set(i, k === 0 ? deal.price : 0));
        return base;
      }
      case 'bogo': {
        const idxs = units.reduce((a, u, i) => (u.item === deal.item ? (a.push(i), a) : a), []);
        if (idxs.length < 2) return null;
        // Mark BOTH units as consumed: the paid one keeps its price, so it
        // can't also be redeemed with points ("buy zero get one free").
        overrides.set(idxs[0], units[idxs[0]].price);
        overrides.set(idxs[1], 0);
        return base;
      }
      case 'free_with_min': {
        const i = units.findIndex((u) => u.item === deal.item);
        if (i === -1) return null;
        overrides.set(i, 0);
        return { overrides, pctOff: 0, minSpend: deal.minSpend || 0 };
      }
      case 'pct_off':
        return { overrides, pctOff: deal.pct, minSpend: deal.minSpend || 0 };
      default:
        return null;
    }
  }

  // Drop options that are dominated (>= cost AND >= points of another option).
  function pareto(options) {
    options.sort((a, b) => a.cost - b.cost || a.points - b.points);
    const kept = [];
    let minPoints = Infinity;
    for (const o of options) {
      if (o.points < minPoints) {
        kept.push(o);
        minPoints = o.points;
      }
    }
    return kept;
  }

  // All Pareto-optimal (cash, points) ways to pay for one order.
  function orderOptions(units, deals, opts) {
    const options = [];
    for (const deal of [null, ...deals]) {
      const app = applyDeal(units, deal);
      if (!app) continue;

      const rewardChoices = [null];
      if (!deal || opts.allowDealPlusReward !== false) {
        const seen = new Set();
        units.forEach((u, i) => {
          if (u.rewardPoints == null || app.overrides.has(i) || seen.has(u.item)) return;
          seen.add(u.item);
          const centsPerPoint = (u.price * 100) / u.rewardPoints;
          if (opts.minCentsPerPoint && centsPerPoint < opts.minCentsPerPoint) return;
          rewardChoices.push(i);
        });
      }

      for (const rw of rewardChoices) {
        let subtotal = 0;
        units.forEach((u, i) => {
          if (i === rw) return;
          subtotal += app.overrides.has(i) ? app.overrides.get(i) : u.price;
        });
        if (app.minSpend && subtotal < app.minSpend) continue;
        options.push({
          cost: round2(subtotal * (1 - app.pctOff / 100)),
          points: rw == null ? 0 : units[rw].rewardPoints,
          deal,
          rewardIdx: rw,
        });
      }
    }
    return pareto(options);
  }

  // Enumerate set partitions of n elements into at most maxK blocks
  // (restricted growth strings), invoking cb(assignment, blockCount).
  function forEachPartition(n, maxK, cb) {
    const a = new Array(n).fill(0);
    (function rec(i, maxUsed) {
      if (i === n) {
        cb(a, maxUsed + 1);
        return;
      }
      const top = Math.min(maxUsed + 1, maxK - 1);
      for (let v = 0; v <= top; v++) {
        a[i] = v;
        rec(i + 1, Math.max(maxUsed, v));
      }
    })(1, 0);
  }

  function optimize(units, deals, opts) {
    opts = opts || {};
    const n = units.length;
    const baseline = round2(units.reduce((s, u) => s + u.price, 0));
    if (n === 0) {
      return { orders: [], totalCost: 0, baseline: 0, saved: 0, pointsSpent: 0, pointsEarned: 0 };
    }
    if (n > 15) throw new Error('Cart too large to optimize (max 15 items).');

    const maxOrders = Math.max(1, Math.min(opts.maxOrders || 2, n));
    const balance = opts.pointsBalance || 0;
    const memo = new Map();

    const optionsFor = (group) => {
      const key = group.map((i) => units[i].item).join('|');
      let hit = memo.get(key);
      if (!hit) {
        hit = orderOptions(group.map((i) => units[i]), deals, opts);
        memo.set(key, hit);
      }
      return hit;
    };

    let best = null; // { cost, points, k, picks: [{group, option}] }

    forEachPartition(n, maxOrders, (assign, k) => {
      const groups = Array.from({ length: k }, () => []);
      for (let i = 0; i < n; i++) groups[assign[i]].push(i);
      // Sort each group's units by item name so memoized option indices line up.
      groups.forEach((g) => g.sort((x, y) => units[x].item.localeCompare(units[y].item)));
      const optionSets = groups.map(optionsFor);

      // Pick one option per group, minimizing cost under the points budget.
      const picks = [];
      (function choose(gi, cost, points) {
        if (best && cost > best.cost) return; // cost only grows; prune
        if (gi === k) {
          if (
            !best ||
            cost < best.cost ||
            (cost === best.cost && (points < best.points || (points === best.points && k < best.k)))
          ) {
            best = { cost: round2(cost), points, k, picks: picks.slice() };
          }
          return;
        }
        for (const o of optionSets[gi]) {
          if (points + o.points > balance) continue;
          picks.push({ group: groups[gi], option: o });
          choose(gi + 1, cost + o.cost, points + o.points);
          picks.pop();
        }
      })(0, 0, 0);
    });

    if (!best) {
      // Only possible if a points threshold filtered everything odd; fall back to paying cash.
      return {
        orders: [{ units, deal: null, reward: null, cost: baseline, points: 0 }],
        totalCost: baseline,
        baseline,
        saved: 0,
        pointsSpent: 0,
        pointsEarned: Math.round(baseline * 100),
      };
    }

    const orders = best.picks.map(({ group, option }) => {
      const orderUnits = group.map((i) => units[i]);
      const reward = option.rewardIdx == null ? null : orderUnits[option.rewardIdx];
      return {
        units: orderUnits,
        deal: option.deal,
        reward: reward
          ? {
              item: reward.item,
              points: reward.rewardPoints,
              value: reward.price,
              centsPerPoint: round2((reward.price * 100) / reward.rewardPoints * 100) / 100,
            }
          : null,
        cost: option.cost,
        points: option.points,
      };
    });

    return {
      orders,
      totalCost: best.cost,
      baseline,
      saved: round2(baseline - best.cost),
      pointsSpent: best.points,
      pointsEarned: Math.round(best.cost * 100),
    };
  }

  return { optimize, orderOptions, applyDeal };
});
