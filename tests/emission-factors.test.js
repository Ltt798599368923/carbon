const assert = require('node:assert/strict');
const test = require('node:test');
const factors = require('../data/emission-factors.json').factors;

function calculate(factor, amount) {
  return amount * factor.reductionKgPerUnit;
}

function points(factor, amount) {
  return Math.max(1, Math.round(amount * factor.pointsPerUnit));
}

test('all demo factors have the fields required by the MVP', () => {
  assert.ok(factors.length >= 5);
  for (const factor of factors) {
    assert.ok(factor.id);
    assert.ok(factor.label);
    assert.ok(factor.unit);
    assert.equal(typeof factor.reductionKgPerUnit, 'number');
    assert.equal(typeof factor.pointsPerUnit, 'number');
    assert.ok(factor.reductionKgPerUnit > 0);
    assert.ok(factor.pointsPerUnit > 0);
  }
});

test('walking 3 km calculates the product demo result', () => {
  const walk = factors.find((factor) => factor.id === 'walk');
  assert.equal(calculate(walk, 3), 0.6);
  assert.equal(points(walk, 3), 6);
});

test('reusable item recommendation calculates 0.06 kg and 6 points', () => {
  const reusable = factors.find((factor) => factor.id === 'reusable');
  assert.equal(calculate(reusable, 1), 0.06);
  assert.equal(points(reusable, 1), 6);
});

test('small positive behavior still awards at least one point', () => {
  const transit = factors.find((factor) => factor.id === 'transit');
  assert.equal(points(transit, 0.1), 1);
});
