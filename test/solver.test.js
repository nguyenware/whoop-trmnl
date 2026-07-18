'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { optimize, dealHacks } = require('../solver.js');

const u = (item, price, rewardPoints = null) => ({ item, price, rewardPoints });

test('no deals, no points: pay full price in one order', () => {
  const r = optimize([u('Big Mac', 5.69), u('Medium Fries', 3.79)], [], { maxOrders: 2 });
  assert.strictEqual(r.totalCost, 9.48);
  assert.strictEqual(r.orders.length, 1);
  assert.strictEqual(r.saved, 0);
  assert.strictEqual(r.pointsEarned, 948);
});

test('item_price deal is applied', () => {
  const deals = [{ kind: 'item_price', item: 'Big Mac', price: 2.0, label: 'Big Mac for $2' }];
  const r = optimize([u('Big Mac', 5.69), u('Medium Fries', 3.79)], deals, { maxOrders: 1 });
  assert.strictEqual(r.totalCost, 5.79);
  assert.strictEqual(r.orders[0].deal.label, 'Big Mac for $2');
});

test('bogo needs two of the item and frees one', () => {
  const deals = [{ kind: 'bogo', item: 'Big Mac' }];
  const one = optimize([u('Big Mac', 5.69)], deals, {});
  assert.strictEqual(one.totalCost, 5.69); // inapplicable
  const two = optimize([u('Big Mac', 5.69), u('Big Mac', 5.69)], deals, {});
  assert.strictEqual(two.totalCost, 5.69);
});

test('bundle_price covers all listed items together', () => {
  const deals = [{
    kind: 'bundle_price',
    items: ['McDouble', 'Small Fries', 'Medium Soft Drink'],
    price: 5.0,
    label: '$5 Meal Deal',
  }];
  const cart = [u('McDouble', 3.19), u('Small Fries', 2.89), u('Medium Soft Drink', 1.49), u('Big Mac', 5.69)];
  const r = optimize(cart, deals, { maxOrders: 1 });
  assert.strictEqual(r.totalCost, 10.69); // 5.00 bundle + 5.69 Big Mac
  // Bundle inapplicable if a component is missing:
  const r2 = optimize([u('McDouble', 3.19)], deals, {});
  assert.strictEqual(r2.totalCost, 3.19);
});

test('reward redemption respects the points balance', () => {
  const cart = [u('Big Mac', 5.69, 6000), u('McChicken', 2.99, 1500)];
  const broke = optimize(cart, [], { pointsBalance: 1000 });
  assert.strictEqual(broke.totalCost, 8.68);
  const rich = optimize(cart, [], { pointsBalance: 6000, maxOrders: 1 });
  // Only one reward per order; best single redemption is the Big Mac.
  assert.strictEqual(rich.totalCost, 2.99);
  assert.strictEqual(rich.pointsSpent, 6000);
  const richSplit = optimize(cart, [], { pointsBalance: 7500, maxOrders: 2 });
  // Splitting into two orders lets both be redeemed.
  assert.strictEqual(richSplit.totalCost, 0);
  assert.strictEqual(richSplit.orders.length, 2);
});

test('splitting orders unlocks a second deal', () => {
  const deals = [
    { kind: 'item_price', item: 'Big Mac', price: 2.0 },
    { kind: 'item_price', item: 'McChicken', price: 1.0 },
  ];
  const cart = [u('Big Mac', 5.69), u('McChicken', 2.99)];
  const single = optimize(cart, deals, { maxOrders: 1 });
  assert.strictEqual(single.totalCost, 4.99); // best one deal: Big Mac $2 + McChicken $2.99
  const split = optimize(cart, deals, { maxOrders: 2 });
  assert.strictEqual(split.totalCost, 3.0);
  assert.strictEqual(split.orders.length, 2);
});

test('allowDealPlusReward=false forces a choice within one order', () => {
  const deals = [{ kind: 'item_price', item: 'Big Mac', price: 2.0 }];
  const cart = [u('Big Mac', 5.69), u('McChicken', 2.99, 1500)];
  const both = optimize(cart, deals, { maxOrders: 1, pointsBalance: 1500, allowDealPlusReward: true });
  assert.strictEqual(both.totalCost, 2.0);
  const pick = optimize(cart, deals, { maxOrders: 1, pointsBalance: 1500, allowDealPlusReward: false });
  assert.strictEqual(pick.totalCost, 4.99); // deal on Big Mac ($2), pay for McChicken
  assert.strictEqual(pick.pointsSpent, 0);
  const split = optimize(cart, deals, { maxOrders: 2, pointsBalance: 1500, allowDealPlusReward: false });
  assert.strictEqual(split.totalCost, 2.0); // separate orders: deal in one, reward in the other
});

test('minCentsPerPoint blocks low-value redemptions', () => {
  // Cheeseburger at 3000 pts would be ~0.083 cents/point.
  const cart = [u('Cheeseburger', 2.49, 3000)];
  const any = optimize(cart, [], { pointsBalance: 3000 });
  assert.strictEqual(any.totalCost, 0);
  const picky = optimize(cart, [], { pointsBalance: 3000, minCentsPerPoint: 0.1 });
  assert.strictEqual(picky.totalCost, 2.49);
  assert.strictEqual(picky.pointsSpent, 0);
});

test('pct_off with minimum spend', () => {
  const deals = [{ kind: 'pct_off', pct: 20, minSpend: 10 }];
  const small = optimize([u('Big Mac', 5.69)], deals, {});
  assert.strictEqual(small.totalCost, 5.69);
  const big = optimize([u('Big Mac', 5.69), u('20 pc McNuggets', 7.99)], deals, { maxOrders: 1 });
  assert.strictEqual(big.totalCost, 10.94); // 13.68 * 0.8
});

test('free_with_min requires the rest of the order to qualify', () => {
  const deals = [{ kind: 'free_with_min', item: 'Large Fries', minSpend: 1 }];
  const alone = optimize([u('Large Fries', 4.39)], deals, {});
  assert.strictEqual(alone.totalCost, 4.39); // nothing else to satisfy the minimum
  const withBurger = optimize([u('Large Fries', 4.39), u('McDouble', 3.19)], deals, { maxOrders: 1 });
  assert.strictEqual(withBurger.totalCost, 3.19);
});

test('reward is not double-dipped with a deal on the same unit', () => {
  const deals = [{ kind: 'item_price', item: 'Big Mac', price: 2.0 }];
  const cart = [u('Big Mac', 5.69, 6000)];
  const r = optimize(cart, deals, { maxOrders: 1, pointsBalance: 6000 });
  // Best is redeeming (free) — but never "deal price AND points" on one unit.
  assert.strictEqual(r.totalCost, 0);
  assert.strictEqual(r.pointsSpent, 6000);
});

test('BOGO paid unit cannot also be redeemed with points', () => {
  const deals = [{ kind: 'bogo', item: 'Big Mac' }];
  const cart = [{ item: 'Big Mac', price: 5.69, rewardPoints: 6000 }, { item: 'Big Mac', price: 5.69, rewardPoints: 6000 }];
  const r = optimize(cart, deals, { maxOrders: 1, pointsBalance: 12000 });
  // Best legal play: BOGO (pay one) — not BOGO + redeem the paid one for $0.
  assert.strictEqual(r.totalCost, 5.69);
  assert.strictEqual(r.pointsSpent, 0);
});

test('empty cart', () => {
  const r = optimize([], [], {});
  assert.strictEqual(r.totalCost, 0);
  assert.strictEqual(r.orders.length, 0);
});

// ---- Deal Hacks --------------------------------------------------------

const PRICES = { 'Big Mac': 5.69, 'McChicken': 2.99, 'Large Fries': 4.39, 'Cheeseburger': 2.49, 'Medium Fries': 3.79 };
const REWARDS = { 'McChicken': 1500, 'Cheeseburger': 1500, 'Medium Fries': 3000, 'Large Fries': 4500, 'Big Mac': 6000 };

test('dealHacks ranks deals by cash saved', () => {
  const deals = [
    { kind: 'item_price', item: 'McChicken', price: 1.0 },   // saves 1.99
    { kind: 'bogo', item: 'Big Mac' },                        // saves 5.69
  ];
  const h = dealHacks(deals, PRICES, {}, {});
  assert.strictEqual(h.deals[0].deal.kind, 'bogo');
  assert.strictEqual(h.deals[0].savings, 5.69);
  assert.strictEqual(h.deals[1].savings, 1.99);
  assert.strictEqual(h.bestDeal.deal.kind, 'bogo');
});

test('dealHacks ranks rewards by cents-per-point and flags affordability', () => {
  const h = dealHacks([], PRICES, REWARDS, { pointsBalance: 2000 });
  // McChicken (2.99/1500 ≈ 0.199) beats Cheeseburger (2.49/1500 ≈ 0.166) at the top tier.
  assert.strictEqual(h.rewards[0].item, 'McChicken');
  assert.ok(h.rewards[0].centsPerPoint > h.rewards[1].centsPerPoint || h.rewards[0].points <= h.rewards[1].points);
  const bigMac = h.rewards.find((r) => r.item === 'Big Mac');
  assert.strictEqual(bigMac.affordable, false); // 6000 > 2000
  const mcchicken = h.rewards.find((r) => r.item === 'McChicken');
  assert.strictEqual(mcchicken.affordable, true);
});

test('dealHacks picks a hack-of-the-day combo that does not reuse the same item', () => {
  const deals = [{ kind: 'item_price', item: 'McChicken', price: 1.0 }];
  const h = dealHacks(deals, PRICES, REWARDS, { pointsBalance: 6000 });
  assert.strictEqual(h.bestDeal.item, 'McChicken');
  // Best affordable reward must not also be the McChicken the deal already covers.
  assert.notStrictEqual(h.bestReward.item, 'McChicken');
  assert.strictEqual(h.bestReward.affordable, true);
  assert.ok(h.comboSavings > 0);
});

test('dealHacks handles pct_off (no fixed savings, carries a rate)', () => {
  const h = dealHacks([{ kind: 'pct_off', pct: 20 }], PRICES, {}, {});
  assert.strictEqual(h.deals[0].savings, null);
  assert.strictEqual(h.deals[0].rate, 20);
});

test('dealHacks with nothing entered is empty, not an error', () => {
  const h = dealHacks([], PRICES, {}, {});
  assert.strictEqual(h.deals.length, 0);
  assert.strictEqual(h.rewards.length, 0);
  assert.strictEqual(h.bestDeal, null);
  assert.strictEqual(h.bestReward, null);
});
