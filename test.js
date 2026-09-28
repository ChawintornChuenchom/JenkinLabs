const assert = require('assert');
const { sum } = require('./sum');

assert.strictEqual(sum(2, 3), 5, 'sum(2,3) should be 5');
console.log('all tests passed');
