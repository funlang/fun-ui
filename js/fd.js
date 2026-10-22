// Copyright (c) 2026 funlang.org
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/**
 * Funcally Data (FD) serializer / deserializer v1.8.0
 *
 * Features:
 * - Lenient parsing: all problems are collected in an issues array, never thrown.
 * - Self-describing error codes (E_/W_/I_ prefixes); severity is defined in the
 *   FDIssues table.
 * - Line tracking uses \n as the only line-break character; newlines inside
 *   multi-line strings and fixed-length binary data are counted too.
 * - Binary safe: fixed-length binary data is encoded/decoded losslessly with
 *   ISO-8859-1, avoiding UTF-8 conversion damage.
 * - Circular references are detected for arrays and objects, with safe
 *   null/[] fallbacks.
 * - Mixed named/unnamed keys are resolved by the first item type, with
 *   detailed issues.
 * - Integers longer than 15 digits are kept as "numbern" strings to avoid
 *   precision loss.
 * - Indentation supports spaces (2 spaces = 1 level), repeated '>' or "N>"
 *   depth markers.
 *
 * API:
 *   FD.parse(data)        -> returns the parsed value; issues in FD.lastParseIssues
 *   FD.stringify(value)   -> returns the string; issues in FD.lastStringifyIssues
 *   FD.parseEx(data)      -> returns { value, issues }
 *   FD.stringifyEx(value) -> returns { output, issues }
 */

class FD {
    // Issue collectors for the legacy parse/stringify API
    static lastParseIssues = [];
    static lastStringifyIssues = [];

    // ---------- Public API ----------

    /** Standard parse: returns the value; issues are available in FD.lastParseIssues */
    static parse(data, encoding = 'utf-8', reviver) {
        let bytes, actualEncoding;
        if (typeof data === 'string') {
            bytes = new TextEncoder().encode(data);
            actualEncoding = 'utf-8';
        } else {
            bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
            actualEncoding = encoding;
        }
        const parser = new FDParser(bytes, actualEncoding);
        let root = parser.parse();
        if (reviver) root = this._applyReviver(root, reviver);
        FD.lastParseIssues = parser.issues;
        return root;
    }

    /** Standard stringify: returns the string; issues are available in FD.lastStringifyIssues */
    static stringify(value, replacer, spaceMode = 0) {
        const stringifier = new FDStringifier(replacer, spaceMode);
        const output = stringifier.stringify(value);
        FD.lastStringifyIssues = stringifier.issues;
        return output;
    }

    /** Extended parse: returns { value, issues }; delegates to FD.parse */
    static parseEx(data, encoding = 'utf-8', reviver) {
        const value = this.parse(data, encoding, reviver);
        return { value, issues: FD.lastParseIssues };
    }

    /** Extended stringify: returns { output, issues }; delegates to FD.stringify */
    static stringifyEx(value, replacer, spaceMode = 0) {
        const output = this.stringify(value, replacer, spaceMode);
        return { output, issues: FD.lastStringifyIssues };
    }

    // Internal recursive reviver
    static _applyReviver(node, reviver, holder = { '': node }, key = '') {
        if (node && typeof node === 'object') {
            for (const k of Object.keys(node)) {
                const val = node[k];
                if (val && typeof val === 'object') this._applyReviver(val, reviver, node, k);
            }
        }
        return reviver.call(holder, key, node);
    }
}

// ========== Error definitions ==========

const FDIssues = {
    E_EmptyKey:          { level: 'error',   message: 'Empty key' },
    E_UnpairedSurrogate: { level: 'warning', message: 'Unpaired surrogate \\u{hex}' },
    E_MixedKeys:         { level: 'error',   message: 'Mixed named and unnamed (-) items inside object' },
    E_MixedRoots:        { level: 'error',   message: 'Mixed named/unnamed root keys' },
    W_UnknownEscape:     { level: 'warning', message: 'Unknown escape \\{ch}' },
    W_MixedIndent:       { level: 'warning', message: 'Mixed tabs and spaces in indentation' },
    W_NamedIgnored:      { level: 'warning', message: 'Named keys ignored in array context' },
    W_NoRoot:            { level: 'warning', message: 'No root nodes found' },
    I_EmptyDoc:          { level: 'info',    message: 'Empty document' },
    E_CircularRef:       { level: 'error',   message: 'Circular reference replaced with null' },
    E_CircularRefArr:    { level: 'error',   message: 'Circular reference in array replaced with []' }
};

class Issue {
    constructor(code, level, line = -1, extra = '') {
        this.code = code;
        this.level = level;
        this.line = line;
        let msg = (FDIssues[code] && FDIssues[code].message) || code;
        if (extra && msg.includes('{')) {
            msg = msg.replace(/\{(\w+)\}/g, (_, key) => extra);
        } else if (extra) {
            msg += ' ' + extra;
        }
        this.message = msg;
    }

    toString() {
        let s = `[${this.code}][${this.level.toUpperCase()}] ${this.message}`;
        if (this.line >= 1) s += ` (line ${this.line})`;
        return s;
    }
}

// ========== Constants and state ==========

const BYTE = {
    SP: 32, TAB: 9, LF: 10, CR: 13,
    QUOT: 34, APOS: 39, BACKTICK: 96,
    BACKSLASH: 92, GT: 62, HASH: 35,
    ZERO: 48, NINE: 57, x: 120, X: 88
};

const ParseState = { LINE_START: 0, KEY: 1 };

// ========== Byte-stream parser ==========

class FDParser {
    constructor(bytes, encoding) {
        this._bytes = bytes;
        this._decoder = new TextDecoder(encoding);
        this._latin1Decoder = new TextDecoder('iso-8859-1');
        this._logicalLines = [];
        this._pos = 0;
        this._len = bytes.length;
        this._line = 1;                    // Current line number; incremented on \n
        this.issues = [];
        this._tokenize();
    }

    _addIssue(code, extra = '') {
        const def = FDIssues[code];
        const level = def ? def.level : 'warning';
        this.issues.push(new Issue(code, level, this._line, extra));
    }

    // ---------- Byte classification ----------
    _isWhitespace(b) { return b === BYTE.SP || b === BYTE.TAB; }
    _isLineBreak(b)   { return b === BYTE.LF || b === BYTE.CR; }
    _isDigit(b)       { return b >= BYTE.ZERO && b <= BYTE.NINE; }
    _isAlphaX(b)      { return b === BYTE.x || b === BYTE.X; }
    _isQuote(b)       { return b === BYTE.QUOT || b === BYTE.APOS || b === BYTE.BACKTICK; }

    // ---------- Basic cursor movement ----------
    _skipWhile(pred)      { while (this._pos < this._len && pred(this._bytes[this._pos])) this._pos++; }
    _extractWhile(pred)   { const s = this._pos; this._skipWhile(pred); return this._bytes.slice(s, this._pos); }
    _skipUntil(pred)      { while (this._pos < this._len && !pred(this._bytes[this._pos])) this._pos++; }
    _extractUntil(pred)   { const s = this._pos; this._skipUntil(pred); return this._bytes.slice(s, this._pos); }
    _decodeBytes(b)       { return b.length ? this._decoder.decode(b) : ''; }

    // ---------- Line breaks and line numbers ----------

    /** Skip line breaks; only \n increments the line counter, \r is ignored */
    _skipLineBreaks() {
        while (this._pos < this._len) {
            const b = this._bytes[this._pos];
            if (b === BYTE.LF) { this._line++; this._pos++; }
            else if (b === BYTE.CR) this._pos++;
            else break;
        }
    }

    /** Count \n bytes and update the line counter (multi-line strings, fixed-length binary) */
    _updateLineForBytes(bytes) {
        for (let i = 0; i < bytes.length; i++) {
            if (bytes[i] === BYTE.LF) this._line++;
        }
    }

    // ---------- Lexical helpers ----------

    /** Parse a quoted string with doubled-delimiter escapes ("" -> ") */
    _parseQuoted(delimByte) {
        const resultBytes = [];
        this._pos++;                     // Skip the opening quote
        while (true) {
            const part = this._extractUntil(b => b === delimByte);
            resultBytes.push(...part);
            if (this._pos >= this._len) break;
            // Doubled delimiter: "" '' `` are treated as a literal quote
            if (this._pos + 1 < this._len && this._bytes[this._pos + 1] === delimByte) {
                resultBytes.push(delimByte);
                this._pos += 2;
            } else {
                this._pos++;             // Closing quote
                break;
            }
        }
        const finalBytes = new Uint8Array(resultBytes);
        this._updateLineForBytes(finalBytes);   // Count newlines inside the string
        return this._decodeBytes(finalBytes);
    }

    /** Fixed-length binary: `` (x|X)hexLen followed by raw bytes */
    _parseFixedLength() {
        const prefixBytes = this._extractWhile(b => this._isAlphaX(b));
        const prefix = this._decodeBytes(prefixBytes);
        if (!prefix || prefix.length > 2) return null;

        let hexLen = 0;
        for (let i = 0; i < prefix.length; i++) hexLen += prefix[i] === 'x' ? 4 : 6;
        if (this._pos + hexLen > this._len) return null;

        const lenHex = this._decodeBytes(this._bytes.slice(this._pos, this._pos + hexLen));
        if (!/^[0-9A-Fa-f]+$/.test(lenHex)) return null;
        this._pos += hexLen;

        const dataLen = parseInt(lenHex, 16);
        if (isNaN(dataLen) || this._pos + dataLen > this._len) return null;

        const data = this._bytes.slice(this._pos, this._pos + dataLen);
        this._pos += dataLen;
        this._updateLineForBytes(data);          // Count newlines inside the binary data
        return data;
    }

    /** Extract one raw token (key or value); a leading \" declares JSON escapes */
    _parseRawToken(stopSet, outIsQuoted) {
        let token = null;
        outIsQuoted.value = false;
        this._skipWhile(b => this._isWhitespace(b));
        if (this._pos >= this._len) return token;

        let needEscape = false;
        if (this._bytes[this._pos] === BYTE.BACKSLASH &&
            this._pos + 1 < this._len &&
            this._isQuote(this._bytes[this._pos + 1])) {
            needEscape = true;
            this._pos++;                     // Skip the backslash
        }

        const chByte = this._bytes[this._pos];
        if (this._isQuote(chByte)) {
            outIsQuoted.value = true;
            if (chByte === BYTE.BACKTICK && this._pos + 1 < this._len && this._bytes[this._pos + 1] === BYTE.BACKTICK) {
                this._pos += 2;
                token = this._parseFixedLength();
            } else {
                const rawStr = this._parseQuoted(chByte);
                token = needEscape ? this._unescapeJSON(rawStr) : rawStr;
            }
        } else {
            const bytes = this._extractUntil(b => stopSet(b));
            token = this._decodeBytes(bytes);
        }
        return token;
    }

    _parseKey() {
        const isQuoted = { value: false };
        return this._parseRawToken(b => this._isWhitespace(b) || this._isLineBreak(b), isQuoted);
    }

    _parseValue() {
        const isQuoted = { value: false };
        let token = this._parseRawToken(b => this._isLineBreak(b), isQuoted);
        if (token === null) return undefined;
        if (isQuoted.value) return token;

        const str = token.trim();
        if (str === '') return undefined;
        // Special literals
        if (str === '[]') return [];
        if (str === '{}') return {};
        if (str === 'true') return true;
        if (str === 'false') return false;
        if (str === 'null') return null;

        // Number parsing (including big integers)
        if (/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(str) && !str.startsWith('+')) {
            if (/^-?\d{16,}$/.test(str) && str.indexOf('.') === -1 && str.indexOf('e') === -1 && str.indexOf('E') === -1) {
                return str + 'n';   // Keep as a string to avoid precision loss
            }
            const num = parseFloat(str);
            if (!isNaN(num)) return num;
        }
        return str;   // Keep the original text as a string
    }

    // ---------- Indentation depth ----------

    _parseDepth() {
        const start = this._pos;

        // Repeated >
        const gtsBytes = this._extractWhile(b => b === BYTE.GT);
        if (gtsBytes.length > 0) {
            this._skipWhile(b => this._isWhitespace(b));
            return gtsBytes.length;
        }

        // Numeric depth (N>)
        this._pos = start;
        this._extractWhile(b => this._isWhitespace(b));
        const numsBytes = this._extractWhile(b => this._isDigit(b));
        if (numsBytes.length > 0 && this._pos < this._len && this._bytes[this._pos] === BYTE.GT) {
            this._pos++;
            this._skipWhile(b => this._isWhitespace(b));
            return parseInt(this._decodeBytes(numsBytes), 10);
        }

        // Space indentation (tabs count as 2 spaces; mixed indentation is reported)
        this._pos = start;
        let spaceCount = 0, tabCount = 0;
        while (this._pos < this._len && this._isWhitespace(this._bytes[this._pos])) {
            if (this._bytes[this._pos] === BYTE.SP) spaceCount++;
            else if (this._bytes[this._pos] === BYTE.TAB) tabCount++;
            this._pos++;
        }
        if (spaceCount > 0 && tabCount > 0) this._addIssue('W_MixedIndent');
        return Math.floor((spaceCount + tabCount * 2) / 2);
    }

    // ---------- JSON-compatible escapes ----------

    /**
     * Apply JSON escapes (\n \t \\ \uXXXX, etc.) to a string.
     * The regex first matches valid surrogate pairs, then plain \u escapes,
     * then simple escapes.
     */
    _unescapeJSON(s) {
        const re = /\\(?:u([Dd][89aAbB][0-9a-fA-F]{2})u([Dd][cCdDeEfF][0-9a-fA-F]{2})|u([0-9a-fA-F]{4})|(.))/g;
        return s.replace(re, (match, highHex, lowHex, hex, ch) => {
            if (highHex && lowHex) {        // Complete surrogate pair
                const high = parseInt(highHex, 16);
                const low  = parseInt(lowHex, 16);
                const cp   = (high - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000;
                return String.fromCodePoint(cp);
            }
            if (hex) {                      // Single \uXXXX
                const code = parseInt(hex, 16);
                if (code >= 0xD800 && code <= 0xDFFF) {
                    this._addIssue('E_UnpairedSurrogate', hex);
                }
                return String.fromCharCode(code);
            }
            // Simple escape
            switch (ch) {
                case 'n': return '\n'; case 't': return '\t'; case 'r': return '\r';
                case 'b': return '\b'; case 'f': return '\f'; case '\\': return '\\';
                case '"': return '"'; case "'": return "'"; case '`': return '`';
                case '/': return '/';
                default:
                    this._addIssue('W_UnknownEscape', ch);
                    return '\\' + ch;
            }
        });
    }

    // ---------- Tokenizer (line parsing) ----------

    _tokenize() {
        let state = ParseState.LINE_START;
        let curDepth = 0;

        while (this._pos < this._len) {
            switch (state) {
                case ParseState.LINE_START: {
                    const newDepth = this._parseDepth();
                    if (this._pos < this._len && this._isLineBreak(this._bytes[this._pos])) {
                        this._skipLineBreaks();
                        continue;
                    }
                    if (this._pos < this._len && this._bytes[this._pos] === BYTE.HASH) {
                        this._skipUntil(b => this._isLineBreak(b));
                        this._skipLineBreaks();
                        continue;
                    }
                    curDepth = newDepth;
                    state = ParseState.KEY;
                    break;
                }
                case ParseState.KEY: {
                    const key = this._parseKey();
                    if (key === null || key === '') {
                        this._addIssue('E_EmptyKey');
                        this._skipUntil(b => this._isLineBreak(b));
                        this._skipLineBreaks();
                        state = ParseState.LINE_START;
                        continue;
                    }
                    this._skipWhile(b => this._isWhitespace(b));
                    if (this._pos >= this._len || this._isLineBreak(this._bytes[this._pos])) {
                        this._logicalLines.push({ depth: curDepth, key, value: undefined });
                        state = ParseState.LINE_START;
                        this._skipLineBreaks();
                        continue;
                    }
                    const val = this._parseValue();
                    this._skipLineBreaks();
                    this._logicalLines.push({ depth: curDepth, key, value: val });
                    state = ParseState.LINE_START;
                    break;
                }
            }
        }
    }

    // ---------- Syntax tree construction ----------

    _buildTree() {
        if (!this._logicalLines.length) return [];
        for (const line of this._logicalLines) {
            if (line.value === undefined) line.children = [];
        }
        const stack = [], roots = [];
        for (const node of this._logicalLines) {
            while (stack.length && stack[stack.length - 1].depth >= node.depth) stack.pop();
            if (stack.length === 0) roots.push(node);
            else stack[stack.length - 1].children.push(node);
            if (node.value === undefined) stack.push(node);
        }
        return roots;
    }

    /** Recursively convert a node tree into JS objects/arrays */
    _buildValue(node) {
        if (node.value !== undefined) return node.value;
        if (node.children && node.children.length) {
            const hasNamed   = node.children.some(c => c.key !== '-');
            const hasUnnamed = node.children.some(c => c.key === '-');

            if (hasNamed && hasUnnamed) {
                this._addIssue('E_MixedKeys');
                if (node.children[0].key !== '-') {     // Decide by the first item type
                    const obj = {};
                    let idx = 0;
                    for (const child of node.children) {
                        if (child.key === '-') obj['_' + (idx++)] = this._buildValue(child);
                        else obj[child.key] = this._buildValue(child);
                    }
                    return obj;
                } else {
                    this._addIssue('W_NamedIgnored');
                    return node.children.map(c => this._buildValue(c));
                }
            }
            if (!hasNamed) return node.children.map(c => this._buildValue(c));
        }
        const obj = {};
        if (node.children) {
            for (const child of node.children) {
                if (child.key === '-') continue;
                obj[child.key] = this._buildValue(child);
            }
        }
        return obj;
    }

    /** Entry point: build the complete value and resolve mixed root keys */
    parse() {
        if (!this._logicalLines.length) {
            this._addIssue('I_EmptyDoc');
            return {};
        }
        const roots = this._buildTree();
        if (roots.length === 0) {
            this._addIssue('W_NoRoot');
            return {};
        }
        if (roots.every(r => r.key === '-')) return roots.map(r => this._buildValue(r));

        const result = {};
        for (const root of roots) {
            if (root.key === '-') {
                this._addIssue('E_MixedRoots');
                const arr = Object.values(result);
                arr.push(this._buildValue(root));
                return arr;
            } else {
                result[root.key] = this._buildValue(root);
            }
        }
        return result;
    }
}

// ========== Stringifier ==========

class FDStringifier {
    constructor(replacer, spaceMode) {
        this._replacer    = replacer;
        this._spaceMode   = (spaceMode === 1 || spaceMode === 2) ? spaceMode : 0;
        this._indent      = 0;
        this._seen        = new WeakSet();
        this._latin1Decoder = new TextDecoder('iso-8859-1');
        this.issues       = [];
    }

    _addIssue(code, extra = '') {
        const def = FDIssues[code];
        const level = def ? def.level : 'warning';
        this.issues.push(new Issue(code, level, -1, extra));
    }

    _getIndent() {
        const depth = this._indent;
        if (this._spaceMode === 1) return '>'.repeat(depth);
        if (this._spaceMode === 2) return depth > 0 ? depth + '>' : '';
        return '  '.repeat(depth);
    }

    stringify(value) {
        return this._serialize(value, '', true);
    }

    _serialize(value, key, isRoot, isArrayItem = false) {
        // Apply the replacer once. An array replacer filters object keys only.
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
            if (this._seen.has(value)) {
                this._addIssue('E_CircularRef');
                return 'null';
            }
            this._seen.add(value);
            const res = this._serializeObject(value, isRoot);
            this._seen.delete(value);
            return res;
        }
        return 'null';
    }

    _serializeBinary(bytes) {
        const len = bytes.length;
        let prefix, hexDigits;
        if (len <= 0xFFFF)        { prefix = 'x';  hexDigits = 4; }
        else if (len <= 0xFFFFFF) { prefix = 'X';  hexDigits = 6; }
        else if (len <= 0xFFFFFFFF) { prefix = 'xx'; hexDigits = 8; }
        else if (len <= 0xFFFFFFFFFF) { prefix = 'xX'; hexDigits = 10; }
        else                      { prefix = 'XX'; hexDigits = 12; }
        const hexLen = len.toString(16).padStart(hexDigits, '0');
        const dataStr = this._latin1Decoder.decode(bytes);
        return `\`\`${prefix}${hexLen}${dataStr}`;
    }

    _serializeArray(arr, isRoot) {
        if (this._seen.has(arr)) {
            this._addIssue('E_CircularRefArr');
            return '[]';
        }
        this._seen.add(arr);
        if (!arr.length) { this._seen.delete(arr); return '[]'; }

        const lines = [];
        if (!isRoot) this._indent++;
        const indentStr = this._getIndent();
        for (let i = 0; i < arr.length; i++) {
            const item = this._serialize(arr[i], String(i), false, true);
            lines.push(indentStr + '- ' + (item === undefined ? 'null' : item));
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
        const indentStr = this._getIndent();
        for (const key of keys) {
            if (Array.isArray(this._replacer) && !this._replacer.includes(key)) continue;
            const val = obj[key];
            const qk = this._quoteKey(key);
            const serializedVal = this._serialize(val, key, false);
            if (serializedVal === undefined) continue;
            lines.push(indentStr + qk + (serializedVal.startsWith('\n') ? serializedVal : ' ' + serializedVal));
        }
        if (!isRoot) this._indent--;
        return isRoot ? lines.join('\n') : '\n' + lines.join('\n');
    }

    // ---------- Quote decision ----------
    _shouldQuoteValue(s) {
        if (s === '') return true;
        if (s.includes('\n') || /^\s|\s$/.test(s)) return true;
        if (/^[+-]?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(s)) return true;
        if (['true','false','null','[]','{}'].includes(s)) return true;
        if (/^["'`]/.test(s)) return true;
        return false;
    }

    _shouldQuoteKey(key) {
        return this._shouldQuoteValue(key) || /\s/.test(key) || /^[>#\-]/.test(key) || /^\d/.test(key);
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

// ========== Exports ==========
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { FD, Issue, FDIssues };
} else {
    window.FD      = FD;
    window.FDIssue = Issue;
    window.FDIssues = FDIssues;
}
