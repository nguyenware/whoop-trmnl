/*
 * Default menu prices (US national ballpark — edit to match your store!)
 * and the MyMcDonald's Rewards redemption catalog (points per item).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.McData = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // Redemption tiers: 1500 / 3000 / 4500 / 6000 points.
  const REWARDS = {
    'Cheeseburger': 1500,
    'McChicken': 1500,
    'Hash Browns': 1500,
    'Vanilla Cone': 1500,
    'Medium Fries': 3000,
    '6 pc McNuggets': 3000,
    'Sausage Burrito': 3000,
    'Large Iced Coffee': 3000,
    'Large Fries': 4500,
    'Filet-O-Fish': 4500,
    'Large Frappe': 4500,
    'Sausage McMuffin with Egg': 4500,
    'Hotcakes': 4500,
    'Big Mac': 6000,
    'Quarter Pounder with Cheese': 6000,
    '20 pc McNuggets': 6000,
    'Bacon Egg & Cheese Biscuit': 6000,
    'Happy Meal': 6000,
  };

  const MENU = [
    { name: 'Big Mac', price: 5.69 },
    { name: 'Quarter Pounder with Cheese', price: 6.19 },
    { name: 'McDouble', price: 3.19 },
    { name: 'Cheeseburger', price: 2.49 },
    { name: 'McChicken', price: 2.99 },
    { name: 'McCrispy', price: 5.29 },
    { name: 'Filet-O-Fish', price: 5.29 },
    { name: '6 pc McNuggets', price: 3.89 },
    { name: '10 pc McNuggets', price: 5.49 },
    { name: '20 pc McNuggets', price: 7.99 },
    { name: 'Small Fries', price: 2.89 },
    { name: 'Medium Fries', price: 3.79 },
    { name: 'Large Fries', price: 4.39 },
    { name: 'Vanilla Cone', price: 1.69 },
    { name: 'McFlurry (Oreo)', price: 4.69 },
    { name: 'Apple Pie', price: 1.89 },
    { name: 'Medium Soft Drink', price: 1.49 },
    { name: 'Large Iced Coffee', price: 2.99 },
    { name: 'Large Frappe', price: 4.89 },
    { name: 'Hash Browns', price: 2.79 },
    { name: 'Sausage Burrito', price: 2.99 },
    { name: 'Sausage McMuffin with Egg', price: 4.89 },
    { name: 'Egg McMuffin', price: 4.99 },
    { name: 'Bacon Egg & Cheese Biscuit', price: 5.19 },
    { name: 'Hotcakes', price: 4.19 },
    { name: 'Happy Meal', price: 5.49 },
  ];

  return { MENU, REWARDS };
});
