// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fd2.js: streaming FD parser and serializer for chunked input. Use
// FD.createStreamParser() to feed chunks.

(function() {
    'use strict';

    // ==================== Error definitions ====================
    const E_EMPTY_KEY          = { code: 'E_EmptyKey',          level: 'error',   message: 'Empty key' };
    const E_UNPAIRED_SURROGATE = { code: 'E_UnpairedSurrogate', level: 'warning', message: 'Unpaired surrogate \\u{hex}' };
    const E_MIXED_KEYS         = { code: 'E_MixedKeys',         level: 'error',   message: 'Mixed named and unnamed (-) items inside object' };
    const E_MIXED_ROOTS        = { code: 'E_MixedRoots',        level: 'error',   message: 'Mixed named/unnamed root keys' };
    const W_UNKNOWN_ESCAPE     = { code: 'W_UnknownEscape',     level: 'warning', message: 'Unknown escape \\{ch}' };
    const W_MIXED_INDENT       = { code: 'W_MixedIndent',       level: 'warning', message: 'Mixed tabs and spaces in indentation' };
    const W_NAMED_IGNORED      = { code: 'W_NamedIgnored',      level: 'warning', message: 'Named keys ignored in array context' };
    const W_NO_ROOT             = { code: 'W_NoRoot',            level: 'warning', message: 'No root nodes found' };
    const I_EMPTY_DOC           = { code: 'I_EmptyDoc',          level: 'info',    message: 'Empty document' };
    const E_CIRCULAR_REF        = { code: 'E_CircularRef',       level: 'error',   message: 'Circular reference replaced with null' };
    const E_CIRCULAR_REF_ARR    = { code: 'E_CircularRefArr',    level: 'error',   message: 'Circular reference in array replaced with []' };
    const E_STREAM_END_STRING   = { code: 'E_StreamEndInString', level: 'error',   message: 'Stream ended inside string' };
    const E_STREAM_END_BINARY   = { code: 'E_StreamEndInBinary', level: 'error',   message: 'Stream ended inside fixed-length binary' };
    const E_DECRYPT_FAILURE     = { code: 'E_DecryptFailure',    level: 'error',   message: 'Decryption failed, message skipped' };

    class Issue {
        constructor(error, line = -1, extra = '') {
            this.code = error.code;
            this.level = error.level;
            this.line = line;
            this.message = error.message;
            if (extra) this.message += ' ' + extra;
        }
        toString() {
            return `[${this.code}][${this.level.toUpperCase()}] ${this.message}` +
                   (this.line >= 1 ? ` (line ${this.line})` : '');
        }
    }

    // ==================== Constants ====================
    const BYTE = {
        SP: 32, TAB: 9, LF: 10, CR: 13,
        QUOT: 34, APOS: 39, BACKTICK: 96,
        BACKSLASH: 92, GT: 62, HASH: 35,
        ZERO: 48, NINE: 57, x: 120, X: 88
    };

    const STATE = { LINE_START: 0, KEY: 1 };
    const UNESCAPE_RE = /\\(?:u([Dd][89aAbB][0-9a-fA-F]{2})u([Dd][cCdDeEfF][0-9a-fA-F]{2})|u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2})|(.))/g;
    const NUMBER_RE = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
    const FIXED_LEN_RE = /^[0-9A-Fa-f]+$/;

    function concatUint8Arrays(...arrs) {
        let total = 0;
        for (const a of arrs) total += a.length;
        const c = new Uint8Array(total);
        let off = 0;
        for (const a of arrs) { c.set(a, off); off += a.length; }
        return c;
    }

    // ==================== FD main class ====================
    class FD {
        static lastParseIssues = [];
        static lastStringifyIssues = [];

        static createStreamParser(options) { return new FDParser(options); }

        static parse(data, encoding, reviver) {
            let bytes, actualEncoding;
            if (typeof data === 'string') {
                bytes = new TextEncoder().encode(data);
                actualEncoding = 'utf-8';
            } else {
                bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
                actualEncoding = encoding || 'utf-8';
            }
            const parser = new FDParser({ encoding: actualEncoding });
            parser._streamEnded = true;
            parser._buffer = bytes;
            parser._pos = 0;

            const gen = parser._tokenize();
            let genResult = gen.next();
            while (!genResult.done) {
                if (genResult.value?.type === 'need data') {
                    genResult = gen.next();
                } else {
                    genResult = gen.next();
                }
            }
            parser._finalize();

            const result = parser._results[0];
            if (!result) {
                FD.lastParseIssues = parser.issues || [];
                return reviver ? FD._applyReviver({}, reviver) : {};
            }
            FD.lastParseIssues = result.issues;
            return reviver ? FD._applyReviver(result.value, reviver) : result.value;
        }

        static stringify(value, replacer, spaceMode = 0) {
            const s = new FDStringifier(replacer, spaceMode);
            const output = s.stringify(value);
            FD.lastStringifyIssues = s.issues;
            return output;
        }

        static parseEx(data, encoding, reviver) {
            const value = this.parse(data, encoding, reviver);
            return { value, issues: FD.lastParseIssues };
        }

        static stringifyEx(value, replacer, spaceMode) {
            const output = this.stringify(value, replacer, spaceMode);
            return { output, issues: FD.lastStringifyIssues };
        }

        static _applyReviver(node, reviver, holder = { '': node }, key = '') {
            if (node && typeof node === 'object') {
                for (const k of Object.keys(node)) {
                    const v = node[k];
                    if (v && typeof v === 'object') this._applyReviver(v, reviver, node, k);
                }
            }
            return reviver.call(holder, key, node);
        }
    }

    // ==================== Streaming parser ====================
    class FDParser {
        constructor(options = {}) {
            this._encoding = options.encoding || 'utf-8';
            this._transform = options.transform || null;
            this._maxBuffer = options.maxBufferSize || 16 * 1024 * 1024;
            this._decoder = new TextDecoder(this._encoding);
            this._latin1Decoder = new TextDecoder('iso-8859-1');
            this._buffer = new Uint8Array(0);
            this._pos = 0;
            this._line = 1;
            this._kvd = null;                  // #!kvd:<char> custom key/value delimiter
            this._streamEnded = false;
            this.issues = [];
            this._results = [];
            this._nodeStack = [{ depth: -1, key: '', value: undefined, children: [] }];
            this._gen = this._tokenize();
            this._genNext = this._gen.next();
            this._done = false;
        }

        _addIssue(error, extra = '') {
            this.issues.push(new Issue(error, this._line, extra));
        }

        _isWhitespace(b) { return b === BYTE.SP || b === BYTE.TAB; }
        _isLineBreak(b)  { return b === BYTE.LF || b === BYTE.CR; }
        _isDigit(b)      { return b >= BYTE.ZERO && b <= BYTE.NINE; }
        _isAlphaX(b)     { return b === BYTE.x || b === BYTE.X; }
        _isQuote(b)      { return b === BYTE.QUOT || b === BYTE.APOS || b === BYTE.BACKTICK; }
        _isKvd(b)        { return this._kvd === null ? this._isWhitespace(b) : b === this._kvd; }
        _decodeBytes(b)  { return b.length ? this._decoder.decode(b) : ''; }

        _updateLineForBytes(bytes) {
            for (let i = 0; i < bytes.length; i++)
                if (bytes[i] === BYTE.LF) this._line++;
        }

        *_NEOF(n) {
            while (this._pos + n > this._buffer.length) {
                if (this._streamEnded) return false;
                yield { type: 'need data' };
            }
            return true;
        }

        *_skipWhile(pred) {
            while ((yield* this._NEOF(1)) && pred(this._buffer[this._pos])) this._pos++;
        }
        *_extractWhile(pred) {
            const start = this._pos;
            yield* this._skipWhile(pred);
            return this._buffer.slice(start, this._pos);
        }
        *_skipUntil(pred) {
            while ((yield* this._NEOF(1)) && !pred(this._buffer[this._pos])) this._pos++;
        }
        *_extractUntil(pred) {
            const start = this._pos;
            yield* this._skipUntil(pred);
            return this._buffer.slice(start, this._pos);
        }

        *_skipLineBreaks() {
            while (yield* this._NEOF(1)) {
                const b = this._buffer[this._pos];
                if (b === BYTE.LF) { this._line++; this._pos++; }
                else if (b === BYTE.CR) this._pos++;
                else break;
            }
        }

        *_parseQuoted(delimByte) {
            const chunks = [];
            this._pos++;
            while (true) {
                const part = yield* this._extractUntil(b => b === delimByte);
                chunks.push(part);
                if (!(yield* this._NEOF(2))) {
                    this._addIssue(E_STREAM_END_STRING);
                    break;
                }
                if (this._buffer[this._pos + 1] === delimByte) {
                    chunks.push(new Uint8Array([delimByte]));
                    this._pos += 2;
                    continue;
                }
                this._pos++;
                break;
            }
            const final = concatUint8Arrays(...chunks);
            this._updateLineForBytes(final);
            return this._decodeBytes(final);
        }

        *_parseFixedLength() {
            if (!(yield* this._NEOF(1))) return null;
            const prefixBytes = yield* this._extractWhile(b => this._isAlphaX(b));
            const prefix = this._decodeBytes(prefixBytes);
            if (!prefix || prefix.length > 2) return null;
            let hexLen = 0;
            for (let i = 0; i < prefix.length; i++) hexLen += prefix[i] === 'x' ? 4 : 6;
            if (!(yield* this._NEOF(hexLen))) { this._addIssue(E_STREAM_END_BINARY); return null; }
            const lenHex = this._decodeBytes(this._buffer.slice(this._pos, this._pos + hexLen));
            if (!FIXED_LEN_RE.test(lenHex)) return null;
            this._pos += hexLen;
            const dataLen = parseInt(lenHex, 16);
            if (isNaN(dataLen)) return null;
            if (!(yield* this._NEOF(dataLen))) { this._addIssue(E_STREAM_END_BINARY); return null; }
            const data = this._buffer.slice(this._pos, this._pos + dataLen);
            this._pos += dataLen;
            this._updateLineForBytes(data);
            return data;
        }

        *_parseRawToken(stopSet, outIsQuoted) {
            outIsQuoted.value = false;
            yield* this._skipWhile(b => this._isWhitespace(b));
            if (!(yield* this._NEOF(1))) return null;

            let needEscape = false;
            if (this._buffer[this._pos] === BYTE.BACKSLASH) {
                if ((yield* this._NEOF(2)) && this._isQuote(this._buffer[this._pos + 1])) {
                    needEscape = true;
                    this._pos++;
                }
            }
            if (!(yield* this._NEOF(1))) return null;
            const chByte = this._buffer[this._pos];
            if (this._isQuote(chByte)) {
                outIsQuoted.value = true;
                if (chByte === BYTE.BACKTICK) {
                    if ((yield* this._NEOF(2)) && this._buffer[this._pos + 1] === BYTE.BACKTICK) {
                        this._pos += 2;
                        return yield* this._parseFixedLength();
                    }
                    const raw = yield* this._parseQuoted(chByte);
                    return needEscape ? this._unescapeJSON(raw) : raw;
                } else {
                    const raw = yield* this._parseQuoted(chByte);
                    return needEscape ? this._unescapeJSON(raw) : raw;
                }
            } else {
                const bytes = yield* this._extractUntil(b => stopSet(b));
                return this._decodeBytes(bytes);
            }
        }

        *_parseKey() {
            const isQuoted = { value: false };
            return yield* this._parseRawToken(b => this._isKvd(b) || this._isLineBreak(b), isQuoted);
        }

        *_parseValue() {
            const isQuoted = { value: false };
            let token = yield* this._parseRawToken(b => this._isLineBreak(b), isQuoted);
            if (token === null) return undefined;
            if (isQuoted.value) return token;
            const str = token.trim();
            if (str === '') return undefined;
            if (str === '[]') return [];
            if (str === '{}') return {};
            if (str === 'true') return true;
            if (str === 'false') return false;
            if (str === 'null') return null;
            if (NUMBER_RE.test(str)) {
                const num = Number(str);
                if (str.indexOf('.') === -1 && str.indexOf('e') === -1 && str.indexOf('E') === -1) {
                    if (Number.isSafeInteger(num)) return num;
                    return str;
                }
                if (isFinite(num)) return num;
            }
            return str;
        }

        *_parseDepth() {
            const start = this._pos;
            const gts = yield* this._extractWhile(b => b === BYTE.GT);
            if (gts.length > 0) {
                yield* this._skipWhile(b => this._isWhitespace(b));
                return gts.length;
            }
            this._pos = start;
            yield* this._skipWhile(b => this._isWhitespace(b));
            const nums = yield* this._extractWhile(b => this._isDigit(b));
            if (nums.length > 0) {
                if ((yield* this._NEOF(1)) && this._buffer[this._pos] === BYTE.GT) {
                    this._pos++;
                    yield* this._skipWhile(b => this._isWhitespace(b));
                    return parseInt(this._decodeBytes(nums), 10);
                }
            }
            this._pos = start;
            let sp = 0, tab = 0;
            while ((yield* this._NEOF(1)) && this._isWhitespace(this._buffer[this._pos])) {
                if (this._buffer[this._pos] === BYTE.SP) sp++;
                else if (this._buffer[this._pos] === BYTE.TAB) tab++;
                this._pos++;
            }
            if (sp > 0 && tab > 0) this._addIssue(W_MIXED_INDENT);
            return Math.floor((sp + tab * 2) / 2);
        }

        _unescapeJSON(s) {
            return s.replace(UNESCAPE_RE, (_, highHex, lowHex, hex, hexByte, ch) => {
                if (highHex && lowHex) {
                    const hi = parseInt(highHex, 16), lo = parseInt(lowHex, 16);
                    return String.fromCodePoint((hi - 0xD800) * 0x400 + (lo - 0xDC00) + 0x10000);
                }
                if (hex) {
                    const code = parseInt(hex, 16);
                    if (code >= 0xD800 && code <= 0xDFFF) this._addIssue(E_UNPAIRED_SURROGATE, hex);
                    return String.fromCharCode(code);
                }
                if (hexByte) return String.fromCharCode(parseInt(hexByte, 16));
                switch (ch) {
                    case 'n': return '\n'; case 't': return '\t'; case 'r': return '\r';
                    case 'b': return '\b'; case 'f': return '\f'; case '\\': return '\\';
                    case '"': return '"'; case "'": return "'"; case '`': return '`'; case '/': return '/';
                    default: this._addIssue(W_UNKNOWN_ESCAPE, ch); return '\\' + ch;
                }
            });
        }

        *_tokenize() {
            let state = STATE.LINE_START, curDepth = 0;
            outer: while (yield* this._NEOF(1)) {
                switch (state) {
                    case STATE.LINE_START: {
                        const newDepth = yield* this._parseDepth();
                        while (yield* this._NEOF(1)) {
                            const b = this._buffer[this._pos];
                            if (this._isLineBreak(b)) {
                                yield* this._skipLineBreaks();
                                continue outer;
                            } else if (b === BYTE.HASH) {
                                const start = this._pos;
                                yield* this._skipUntil(b => this._isLineBreak(b));
                                if (this._pos - start > 6 &&
                                    this._decodeBytes(this._buffer.slice(start, start + 6)) === '#!kvd:') {
                                    this._kvd = this._buffer[start + 6];
                                }
                                yield* this._skipLineBreaks();
                                continue outer;
                            } else break;
                        }
                        if (!(yield* this._NEOF(1))) break outer;
                        curDepth = newDepth;
                        state = STATE.KEY;
                        continue;
                    }
                    case STATE.KEY: {
                        const key = yield* this._parseKey();
                        if (key === null || key === '') {
                            this._addIssue(E_EMPTY_KEY);
                            yield* this._skipUntil(b => this._isLineBreak(b));
                            yield* this._skipLineBreaks();
                            state = STATE.LINE_START;
                            continue;
                        }
                        yield* this._skipWhile(b => this._isKvd(b));
                        let value;
                        if (!(yield* this._NEOF(1)) || this._isLineBreak(this._buffer[this._pos])) {
                            value = undefined;
                        } else {
                            value = yield* this._parseValue();
                        }
                        yield* this._skipLineBreaks();
                        const node = { depth: curDepth, key, value, children: value === undefined ? [] : undefined };
                        while (this._nodeStack.length && this._nodeStack[this._nodeStack.length - 1].depth >= curDepth)
                            this._nodeStack.pop();
                        const parent = this._nodeStack[this._nodeStack.length - 1];
                        parent.children.push(node);
                        if (node.value === undefined) this._nodeStack.push(node);
                        state = STATE.LINE_START;
                        break;
                    }
                }
            }
        }

        _buildTree() {}

        _buildValue(node) {
            if (node.value !== undefined) return node.value;
            if (node.children && node.children.length) {
                const hasNamed = node.children.some(c => c.key !== '-');
                const hasUnnamed = node.children.some(c => c.key === '-');
                if (hasNamed && hasUnnamed) {
                    this._addIssue(E_MIXED_KEYS);
                    if (node.children[0].key !== '-') {
                        const obj = {}; let idx = 0;
                        for (const c of node.children) {
                            if (c.key === '-') obj['_' + (idx++)] = this._buildValue(c);
                            else obj[c.key] = this._buildValue(c);
                        }
                        return obj;
                    }
                    this._addIssue(W_NAMED_IGNORED);
                    return node.children.map(c => this._buildValue(c));
                }
                if (!hasNamed) return node.children.map(c => this._buildValue(c));
            }
            const obj = {};
            if (node.children)
                for (const c of node.children)
                    if (c.key !== '-') obj[c.key] = this._buildValue(c);
            return obj;
        }

        _finalize() {
            const roots = this._nodeStack[0].children;
            if (roots.length === 0) {
                this._addIssue(I_EMPTY_DOC);
                this._results.push({ value: [], issues: this.issues.splice(0) });
            } else if (roots.every(r => r.key === '-')) {
                this._results.push({ value: roots.map(r => this._buildValue(r)), issues: this.issues.splice(0) });
            } else {
                const result = {};
                for (const r of roots) {
                    if (r.key === '-') {
                        this._addIssue(E_MIXED_ROOTS);
                        const arr = Object.values(result);
                        arr.push(this._buildValue(r));
                        this._results.push({ value: arr, issues: this.issues.splice(0) });
                        return;
                    }
                    result[r.key] = this._buildValue(r);
                }
                this._results.push({ value: result, issues: this.issues.splice(0) });
            }
        }

        _resume() {
            if (this._done) return;
            try {
                while (!this._done) {
                    if (this._genNext.done) {
                        this._done = true;
                        this._finalize();
                        return;
                    }
                    if (this._genNext.value?.type === 'need data') {
                        // After end(), a pending request for more data can be satisfied.
                        if (!this._streamEnded) return;
                        this._genNext = this._gen.next();
                        continue;
                    }
                    this._genNext = this._gen.next();
                }
            } catch (e) {
                this._addIssue(E_STREAM_END_STRING);
                this._done = true;
            }
        }

        async feed(chunk) {
            if (this._done) return;
            let data = chunk;
            if (typeof data === 'string') data = new TextEncoder().encode(data);
            else if (!(data instanceof Uint8Array)) data = new Uint8Array(data);
            if (this._transform) {
                try { data = await this._transform(data); }
                catch (_) { this._addIssue(E_DECRYPT_FAILURE); return; }
            }
            this._buffer = concatUint8Arrays(this._buffer, data);
            if (this._buffer.length - this._pos > this._maxBuffer) throw new Error('Buffer overflow');
            this._resume();
        }

        end() {
            if (this._streamEnded) return;
            this._streamEnded = true;
            this._resume();
        }

        hasResult() { return this._results.length > 0; }
        getResult() { return this._results.shift(); }
    }

    // ==================== Stringifier ====================
    class FDStringifier {
        constructor(replacer, spaceMode) {
            this._replacer = replacer;
            this._spaceMode = (spaceMode === 1 || spaceMode === 2) ? spaceMode : 0;
            this._indent = 0;
            this._seen = new WeakSet();
            this._latin1Decoder = new TextDecoder('iso-8859-1');
            this.issues = [];
        }

        _addIssue(error, extra = '') {
            this.issues.push(new Issue(error, -1, extra));
        }

        _getIndent() {
            const d = this._indent;
            if (this._spaceMode === 1) return '>'.repeat(d);
            if (this._spaceMode === 2) return d > 0 ? d + '>' : '';
            return '  '.repeat(d);
        }

        stringify(value) { return this._serialize(value, '', true); }

        _serialize(value, key, isRoot, isArrayItem = false) {
            if (this._replacer) {
                if (typeof this._replacer === 'function') value = this._replacer(key, value);
                else if (Array.isArray(this._replacer) && !isArrayItem && key !== '' && !this._replacer.includes(key)) return undefined;
            }
            if (value === undefined) return undefined;
            if (value === null) return 'null';
            const t = typeof value;
            if (t === 'boolean') return value ? 'true' : 'false';
            if (t === 'number') return (isNaN(value) || !isFinite(value)) ? 'null' : String(value);
            if (t === 'string') return this._quoteString(value);
            if (value instanceof Uint8Array) return this._serializeBinary(value);
            if (Array.isArray(value)) return this._serializeArray(value, isRoot);
            if (t === 'object') {
                if (this._seen.has(value)) { this._addIssue(E_CIRCULAR_REF); return 'null'; }
                this._seen.add(value);
                const res = this._serializeObject(value, isRoot);
                this._seen.delete(value);
                return res;
            }
            return 'null';
        }

        _serializeBinary(bytes) {
            const PREFIX_TABLE = [
                { max: 0xFFFF,       p: 'x',  d: 4 },
                { max: 0xFFFFFF,     p: 'X',  d: 6 },
                { max: 0xFFFFFFFF,   p: 'xx', d: 8 },
                { max: 0xFFFFFFFFFF, p: 'xX', d: 10 },
                { max: Infinity,     p: 'XX', d: 12 }
            ];
            const len = bytes.length;
            const entry = PREFIX_TABLE.find(e => len <= e.max);
            const dataStr = this._latin1Decoder.decode(bytes);
            return `\`\`${entry.p}${len.toString(16).padStart(entry.d, '0')}${dataStr}`;
        }

        _serializeArray(arr, isRoot) {
            if (this._seen.has(arr)) { this._addIssue(E_CIRCULAR_REF_ARR); return '[]'; }
            this._seen.add(arr);
            if (!arr.length) { this._seen.delete(arr); return '[]'; }
            const lines = [];
            if (!isRoot) this._indent++;
            const indent = this._getIndent();
            for (let i = 0; i < arr.length; i++) {
                const item = this._serialize(arr[i], String(i), false, true);
                lines.push(indent + '- ' + (item === undefined ? 'null' : item));
            }
            if (!isRoot) this._indent--;
            this._seen.delete(arr);
            return isRoot ? lines.join('\n') : '\n' + lines.join('\n');
        }

        _serializeObject(obj, isRoot) {
            const keys = Object.keys(obj);
            if (!keys.length) return '{}';
            const lines = [];
            if (!isRoot) this._indent++;
            const indent = this._getIndent();
            for (const key of keys) {
                if (Array.isArray(this._replacer) && !this._replacer.includes(key)) continue;
                const val = obj[key];
                const qk = this._quoteKey(key);
                const sv = this._serialize(val, key, false);
                if (sv === undefined) continue;
                lines.push(indent + qk + (sv.startsWith('\n') ? sv : ' ' + sv));
            }
            if (!isRoot) this._indent--;
            return isRoot ? lines.join('\n') : '\n' + lines.join('\n');
        }

        _shouldQuoteValue(s) {
            if (s === '') return true;
            if (s.includes('\n') || /^\s|\s$/.test(s)) return true;
            if (/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(s)) return true;
            if (['true','false','null','[]','{}'].includes(s)) return true;
            if (/^["'`]/.test(s)) return true;
            return false;
        }

        _shouldQuoteKey(key) {
            return this._shouldQuoteValue(key) || /\s|^[>#\-\d]/.test(key);
        }

        _addQuotes(s) {
            if (!s.includes('"')) return `"${s}"`;
            if (!s.includes("'")) return `'${s}'`;
            if (!s.includes('`')) return `\`${s}\``;
            return `"${s.replace(/"/g, '""')}"`;
        }

        _quoteString(s) { return this._shouldQuoteValue(s) ? this._addQuotes(s) : s; }
        _quoteKey(key)   { return this._shouldQuoteKey(key) ? this._addQuotes(key) : key; }
    }

    // ==================== Exports ====================
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { FD, Issue };
    } else {
        window.FD = FD;
        window.FDIssue = Issue;
    }
})();
