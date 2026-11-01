// Objects and classes
class Counter {
  constructor() { this.n = 0; }
  inc() { this.n += 1; return this.n; }
}
const c = new Counter();
const o = { a: [1, 2], b: "two" };
if (c.inc() === 1) {
  console.log(JSON.stringify(o));
}
