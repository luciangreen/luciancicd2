// test: add(2,3) => 5
function add(a, b) {
  return a + b; // sum
}

/* A list helper. */
const double = xs => xs.map(x => x * 2);
const name = 'Lucian';
const greeting = `Hello, ${name}!`;
console.log(greeting, double([1, 2, 3]));
