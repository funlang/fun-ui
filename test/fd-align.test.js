// fd.js / fd2.js FD alignment test.
//
//     node test/fd-align.test.js
//
// Node's TextDecoder does not implement iso-8859-1, which the binary encoder
// uses. The polyfill below only covers the encodings the FD code asks for.

const assert = require('assert');

class TextDecoderPolyfill {
  constructor(enc = 'utf-8') { this.enc = String(enc).toLowerCase(); }
  decode(bytes) {
    if (!bytes || !bytes.length) return '';
    const buf = Buffer.from(bytes);
    if (this.enc === 'iso-8859-1' || this.enc === 'latin1') return buf.toString('latin1');
    return buf.toString('utf8');
  }
}
global.TextDecoder = TextDecoderPolyfill;
global.TextEncoder = class { encode(s) { return new Uint8Array(Buffer.from(s, 'utf8')); } };

const { FD: FD1 } = require('../js/fd.js');
const { FD: FD2 } = require('../js/fd2.js');

const nl = '\n';
const sl = '\\';

function check(FD, tag) {
  const p = s => FD.parse(s);
  const one = s => p(s).a;

  // FD number grammar (fd.bnf.fd)
  assert.strictEqual(one('a 03'), '03', tag + ' 03');
  assert.strictEqual(one('a 01'), '01', tag + ' 01');
  assert.strictEqual(one('a 0.5'), 0.5, tag + ' 0.5');
  assert.strictEqual(one('a 1.'), '1.', tag + ' 1.');
  assert.strictEqual(one('a .5'), '.5', tag + ' .5');
  assert.strictEqual(one('a 0x10'), '0x10', tag + ' 0x10');
  assert.strictEqual(one('a +1'), '+1', tag + ' +1');
  assert.strictEqual(one('a 1e'), '1e', tag + ' 1e');
  assert.strictEqual(one('a 1.2.3'), '1.2.3', tag + ' 1.2.3');
  assert.strictEqual(one('a 1e+3'), 1000, tag + ' 1e+3');
  assert.strictEqual(one('a true'), true, tag + ' true');
  assert.strictEqual(one('a false'), false, tag + ' false');
  assert.strictEqual(one('a null'), null, tag + ' null');
  assert.strictEqual(one('a yes'), 'yes', tag + ' yes');
  assert.strictEqual(one('a no'), 'no', tag + ' no');

  // host number type (IEEE-754 double); values beyond 2^53 may round
  assert.strictEqual(one('a 9007199254740991'), 9007199254740991, tag + ' 2^53-1');
  assert.strictEqual(one('a 9007199254740992'), 9007199254740992, tag + ' 2^53');
  assert.strictEqual(typeof one('a 9223372036854775808'), 'number', tag + ' beyond int64 is number');
  assert.strictEqual(one('a 1e400'), '1e400', tag + ' float overflow');

  // empty / comment-only document
  assert.ok(Array.isArray(p('')), tag + ' empty is []');
  assert.ok(Array.isArray(p('# only a comment')), tag + ' comment-only is []');

  // escapes (only a leading \" enables them)
  assert.strictEqual(one('a \\"x' + sl + 'ny"'), 'x\ny', tag + ' \\n');
  assert.strictEqual(one('a \\"x' + sl + 'x41y"'), 'xAy', tag + ' \\x41');
  assert.strictEqual(one('a \\"x' + sl + 'qy"'), 'x' + sl + 'qy', tag + ' unknown escape');
  assert.strictEqual(one('a \"x' + sl + 'ny"'), 'x' + sl + 'ny', tag + ' raw string');

  // custom key/value delimiter
  const kvd = '#!kvd:=' + nl + 'a=85' + nl + 'b=hello world' + nl;
  assert.strictEqual(p(kvd).a, 85, tag + ' kvd number');
  assert.strictEqual(p(kvd).b, 'hello world', tag + ' kvd string');

  // duplicate keys: last wins
  assert.strictEqual(one('a 1' + nl + 'a 2'), 2, tag + ' duplicate key');

  // writer quoting follows the reader grammar
  assert.strictEqual(FD.stringify({ a: '0x10' }), 'a 0x10', tag + ' write 0x10');
  assert.strictEqual(FD.stringify({ a: '.5' }), 'a .5', tag + ' write .5');
  assert.strictEqual(FD.stringify({ a: '01' }), 'a 01', tag + ' write 01');
  assert.strictEqual(FD.stringify({ a: '03' }), 'a 03', tag + ' write 03');
  assert.strictEqual(FD.stringify({ a: '+1' }), 'a +1', tag + ' write +1');
  assert.strictEqual(FD.stringify({ a: '9007199254740992' }), 'a "9007199254740992"', tag + ' write big');
}

check(FD1, 'fd.js');
check(FD2, 'fd2.js');
console.log('fd-align: PASS');
