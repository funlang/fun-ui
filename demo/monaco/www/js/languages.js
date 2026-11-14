// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// Monaco language definitions for the offline editor demo.
//
//   fun    Monarch grammar derived from funide's syntaxes/fun.tmLanguage.yaml
//   fd     line-oriented grammar derived from funide's src/ide/fdsyntax.pas
//   zdata  HTML plus z-data directives, derived from z-data's studio grammar
//
// HTML, CSS, and JavaScript use Monaco's built-in grammars; only the three
// Fun-specific languages are registered here.

(function (global) {
  'use strict';

  var FUN_KEYWORDS = [
    'and', 'as', 'atom', 'bit', 'case', 'class', 'div', 'do', 'else', 'elsif',
    'end', 'except', 'exit', 'finally', 'for', 'fun', 'if', 'in', 'is', 'loop',
    'mod', 'new', 'next', 'not', 'or', 'raise', 'return', 'step', 'then', 'to',
    'try', 'use', 'var', 'when', 'while', 'xor'
  ];

  var funConfiguration = {
    comments: {
      lineComment: '//',
      blockComment: ['#*', '#']
    },
    brackets: [
      ['{', '}'],
      ['[', ']'],
      ['(', ')']
    ],
    autoClosingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
      { open: '`', close: '`' }
    ],
    surroundingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
      { open: '`', close: '`' }
    ],
    wordPattern: /[$_@A-Za-z][$_@A-Za-z0-9]*/
  };

  var funLanguage = {
    defaultToken: '',
    tokenPostfix: '.fun',

    keywords: FUN_KEYWORDS,
    constants: ['true', 'false', 'null', 'nil'],
    languageVariables: ['this', 'base', 'result'],

    tokenizer: {
      root: [
        // Comments: '#* ... #' blocks, '#' and '//' line comments.
        [/#\*/, 'comment', '@blockComment'],
        [/#.*$/, 'comment'],
        [/\/\/.*$/, 'comment'],

        // Strings. Fun repeats the delimiter to escape it ('it''s').
        [/\$"/, 'regexp', '@dollarDouble'],
        [/\$'/, 'regexp', '@dollarSingle'],
        [/\$`/, 'regexp', '@dollarBacktick'],
        [/"/, 'string', '@stringDouble'],
        [/'/, 'string', '@stringSingle'],
        [/`/, 'string', '@stringBacktick'],

        // Regex literals: /.../flags and %...%flags.
        [/\/(?:[^\/\\\n]|\\.)+\/[a-z]*/, 'regexp'],
        [/%(?:[^%\\\n]|\\.)+%[a-z]*/, 'regexp'],

        // Numbers.
        [/\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+)\b/, 'number'],
        [/\b[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?\b/, 'number'],
        [/\.(?:[0-9]+)(?:[eE][-+]?[0-9]+)?/, 'number'],

        // Member access. Reserved words after a dot are member names, not
        // keywords (obj.fun, obj?.if), matching the Fun lexer.
        [/(\?\.)([$_@@A-Za-z][$_@@A-Za-z0-9]*)/, ['operator', 'variable']],
        [/(\.)([$_@@A-Za-z][$_@@A-Za-z0-9]*)/, ['delimiter', 'variable']],

        // The lone '@' is a language variable; '@name' is an ordinary
        // identifier (the identifier rule below handles it).
        [/@(?=[\s(.;,)\]}])/, 'variable.language'],

        [/[$_@@A-Za-z][$_@@A-Za-z0-9]*/, {
          cases: {
            '@keywords': 'keyword',
            '@constants': 'constant',
            '@languageVariables': 'variable.language',
            '@default': 'variable'
          }
        }],

        [/[{}()\[\]]/, '@brackets'],
        [/[;,.]/, 'delimiter'],
        [/[+\-*\/^<>=&|!~]+/, 'operator'],
        [/\s+/, 'white']
      ],

      blockComment: [
        [/[^#]+/, 'comment'],
        [/#/, 'comment', '@pop']
      ],

      stringDouble: [
        [/""/, 'string.escape'],
        [/"/, 'string', '@pop'],
        [/[^"]+/, 'string']
      ],

      stringSingle: [
        [/''/, 'string.escape'],
        [/'/, 'string', '@pop'],
        [/[^']+/, 'string']
      ],

      stringBacktick: [
        [/``/, 'string.escape'],
        [/`/, 'string', '@pop'],
        [/[^`]+/, 'string']
      ],

      dollarDouble: [
        [/""/, 'regexp.escape'],
        [/"/, 'regexp', '@pop'],
        [/[^"]+/, 'regexp']
      ],

      dollarSingle: [
        [/''/, 'regexp.escape'],
        [/'/, 'regexp', '@pop'],
        [/[^']+/, 'regexp']
      ],

      dollarBacktick: [
        [/``/, 'regexp.escape'],
        [/`/, 'regexp', '@pop'],
        [/[^`]+/, 'regexp']
      ]
    }
  };

  var fdConfiguration = {
    comments: { lineComment: '#' },
    brackets: [
      ['{', '}'],
      ['[', ']']
    ],
    autoClosingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
      { open: '`', close: '`' }
    ],
    surroundingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
      { open: '`', close: '`' }
    ]
  };

  // FD is indentation based: a line is `indent key [value]`, and '#' starts a
  // full-line comment. `#!kvd:<c>` switches the key/value delimiter; this
  // grammar recognises the common 'key=value' spelling as well.
  var fdLanguage = {
    defaultToken: '',
    tokenPostfix: '.fd',

    tokenizer: {
      root: [
        [/^([ \t]*)(#!.*)$/, ['indent', 'shebang']],
        [/^([ \t]*)(#.*)$/, ['indent', 'comment']],

        // key = value (the kvd variant; keys may contain spaces)
        [/^([ \t]*)([^#\n]+?)(\s*)(=)(\s*)/, ['indent', 'key', '', 'operator', ''], '@value'],

        // array item: "- value"
        [/^([ \t]*)(-)([ \t]+)/, ['indent', 'keyword', ''], '@value'],

        // key followed by a value
        [/^([ \t]*)([^\s#]+)([ \t]+)/, ['indent', 'key', ''], '@value'],

        // key with no value (nested object/array)
        [/^([ \t]*)([^\s#]+)([ \t]*)$/, ['indent', 'key', '']],

        [/^[ \t]*$/, ''],
        [/./, 'value']
      ],

      value: [
        [/#.*$/, 'comment', '@pop'],
        [/"(?:[^"]|"")*"/, 'string'],
        [/'(?:[^']|'')*'/, 'string'],
        [/`(?:[^`]|``)*`/, 'string'],
        [/\{\}|\[\]/, 'constant'],
        [/\b(?:true|false|null)\b/, 'constant'],
        [/-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?/, 'number'],
        [/[ \t]+/, ''],
        [/[^#"\s]+/, 'value'],
        [/$/, '', '@pop']
      ]
    }
  };

  var HTML_EMPTY_ELEMENTS = [
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'keygen',
    'link', 'menuitem', 'meta', 'param', 'source', 'track', 'wbr'
  ];

  var zdataConfiguration = {
    wordPattern: /(-?\d*\.\d\w*)|([^\`\~\!\@\$\^\&\*\(\)\=\+\[\{\]\}\\\|\;\:\'\"\,\.\<\>\/\s]+)/g,
    comments: { blockComment: ['<!--', '-->'] },
    brackets: [
      ['<!--', '-->'],
      ['<', '>'],
      ['{', '}'],
      ['(', ')']
    ],
    autoClosingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '"', close: '"' },
      { open: "'", close: "'" }
    ],
    surroundingPairs: [
      { open: '"', close: '"' },
      { open: "'", close: "'" },
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '<', close: '>' }
    ],
    onEnterRules: [
      {
        beforeText: new RegExp('<(?!(?:' + HTML_EMPTY_ELEMENTS.join('|') + '))([_:\\w][_:\\w-.\\d]*)([^/>]*(?!/)>)[^<]*$', 'i'),
        afterText: /^<\/([_:\w][_:\w-.\d]*)\s*>$/i,
        action: { indentAction: 2 }
      },
      {
        beforeText: new RegExp('<(?!(?:' + HTML_EMPTY_ELEMENTS.join('|') + '))(\\w[\\w\\d]*)([^/>]*(?!/)>)[^<]*$', 'i'),
        action: { indentAction: 1 }
      }
    ]
  };

  var zdataLanguage = {
    defaultToken: '',
    tokenPostfix: '.html',
    ignoreCase: true,

    tokenizer: {
      root: [
        [/^z-data\s*$/, 'keyword'],
        [/<!DOCTYPE/, 'metatag', '@doctype'],
        [/<!--/, 'comment', '@comment'],
        [/(<)((?:[\w\-]+:)?[\w\-]+)(\s*)(\/>)/, ['delimiter', 'tag', '', 'delimiter']],
        [/(<)(script)/, ['delimiter', { token: 'tag', next: '@script' }]],
        [/(<)(style)/, ['delimiter', { token: 'tag', next: '@style' }]],
        [/(<)((?:[\w\-]+:)?[\w\-]+)/, ['delimiter', { token: 'tag', next: '@otherTag' }]],
        [/(<\/)((?:[\w\-]+:)?[\w\-]+)/, ['delimiter', { token: 'tag', next: '@otherTag' }]],
        [/</, 'delimiter'],
        [/[^<]+/]
      ],

      doctype: [
        [/[^>]+/, 'metatag.content'],
        [/>/, 'metatag', '@pop']
      ],

      comment: [
        [/-->/, 'comment', '@pop'],
        [/[^-]+/, 'comment.content'],
        [/./, 'comment.content']
      ],

      otherTag: [
        [/\/?>/, 'delimiter', '@pop'],

        // Embedded data expression: z-data='{ ... }'
        [/\b(z-data)(=)(')/, ['keyword', 'delimiter', { token: 'attribute.name', next: '@zdataSingle', nextEmbedded: 'text/javascript' }]],
        [/\b(z-data)(=)(")/, ['keyword', 'delimiter', { token: 'attribute.name', next: '@zdataDouble', nextEmbedded: 'text/javascript' }]],

        // z-data component and directive attributes
        [/\b(z-data|z-comp|z-none|z-cloak)\b/, 'keyword'],
        [/\b(z-d-[\w-]+)/, 'keyword'],
        [/([:.@@!#]+)([\w-]+)/, ['metatag', 'attribute.name']],

        [/"([^"]*)"/, 'attribute.value'],
        [/'([^']*)'/, 'attribute.value'],
        [/[\w-]+/, 'attribute.name'],
        [/=/, 'delimiter'],
        [/[ \t\r\n]+/]
      ],

      zdataSingle: [
        [/'/, { token: 'attribute.name', next: '@pop', nextEmbedded: '@pop' }],
        [/[^']+/, '']
      ],

      zdataDouble: [
        [/"/, { token: 'attribute.name', next: '@pop', nextEmbedded: '@pop' }],
        [/[^"]+/, '']
      ],

      script: [
        [/type/, 'attribute.name', '@scriptAfterType'],
        [/"([^"]*)"/, 'attribute.value'],
        [/'([^']*)'/, 'attribute.value'],
        [/[\w-]+/, 'attribute.name'],
        [/=/, 'delimiter'],
        [/>/, { token: 'delimiter', next: '@scriptEmbedded', nextEmbedded: 'text/javascript' }],
        [/[ \t\r\n]+/],
        [/(<\/)(script\s*)(>)/, ['delimiter', 'tag', { token: 'delimiter', next: '@pop' }]]
      ],

      scriptAfterType: [
        [/=/, 'delimiter', '@scriptAfterTypeEquals'],
        [/>/, { token: 'delimiter', next: '@scriptEmbedded', nextEmbedded: 'text/javascript' }],
        [/[ \t\r\n]+/],
        [/<\/script\s*>/, { token: '@rematch', next: '@pop' }]
      ],

      scriptAfterTypeEquals: [
        [/"([^"]*)"/, { token: 'attribute.value', switchTo: '@scriptWithCustomType.$1' }],
        [/'([^']*)'/, { token: 'attribute.value', switchTo: '@scriptWithCustomType.$1' }],
        [/>/, { token: 'delimiter', next: '@scriptEmbedded', nextEmbedded: 'text/javascript' }],
        [/[ \t\r\n]+/],
        [/<\/script\s*>/, { token: '@rematch', next: '@pop' }]
      ],

      scriptWithCustomType: [
        [/>/, { token: 'delimiter', next: '@scriptEmbedded.$S2', nextEmbedded: '$S2' }],
        [/"([^"]*)"/, 'attribute.value'],
        [/'([^']*)'/, 'attribute.value'],
        [/[\w-]+/, 'attribute.name'],
        [/=/, 'delimiter'],
        [/[ \t\r\n]+/],
        [/<\/script\s*>/, { token: '@rematch', next: '@pop' }]
      ],

      scriptEmbedded: [
        [/<\/script/, { token: '@rematch', next: '@pop', nextEmbedded: '@pop' }],
        [/[^<]+/, '']
      ],

      style: [
        [/type/, 'attribute.name', '@styleAfterType'],
        [/"([^"]*)"/, 'attribute.value'],
        [/'([^']*)'/, 'attribute.value'],
        [/[\w-]+/, 'attribute.name'],
        [/=/, 'delimiter'],
        [/>/, { token: 'delimiter', next: '@styleEmbedded', nextEmbedded: 'text/css' }],
        [/[ \t\r\n]+/],
        [/(<\/)(style\s*)(>)/, ['delimiter', 'tag', { token: 'delimiter', next: '@pop' }]]
      ],

      styleAfterType: [
        [/=/, 'delimiter', '@styleAfterTypeEquals'],
        [/>/, { token: 'delimiter', next: '@styleEmbedded', nextEmbedded: 'text/css' }],
        [/[ \t\r\n]+/],
        [/<\/style\s*>/, { token: '@rematch', next: '@pop' }]
      ],

      styleAfterTypeEquals: [
        [/"([^"]*)"/, { token: 'attribute.value', switchTo: '@styleWithCustomType.$1' }],
        [/'([^']*)'/, { token: 'attribute.value', switchTo: '@styleWithCustomType.$1' }],
        [/>/, { token: 'delimiter', next: '@styleEmbedded', nextEmbedded: 'text/css' }],
        [/[ \t\r\n]+/],
        [/<\/style\s*>/, { token: '@rematch', next: '@pop' }]
      ],

      styleWithCustomType: [
        [/>/, { token: 'delimiter', next: '@styleEmbedded.$S2', nextEmbedded: '$S2' }],
        [/"([^"]*)"/, 'attribute.value'],
        [/'([^']*)'/, 'attribute.value'],
        [/[\w-]+/, 'attribute.name'],
        [/=/, 'delimiter'],
        [/[ \t\r\n]+/],
        [/<\/style\s*>/, { token: '@rematch', next: '@pop' }]
      ],

      styleEmbedded: [
        [/<\/style/, { token: '@rematch', next: '@pop', nextEmbedded: '@pop' }],
        [/[^<]+/, '']
      ]
    }
  };

  var themeRules = [
    { token: 'comment', foreground: '6A9955', fontStyle: 'italic' },
    { token: 'keyword', foreground: '569CD6' },
    { token: 'string', foreground: 'CE9178' },
    { token: 'string.escape', foreground: 'D7BA7D' },
    { token: 'number', foreground: 'B5CEA8' },
    { token: 'regexp', foreground: 'D16969' },
    { token: 'operator', foreground: 'D4D4D4' },
    { token: 'delimiter', foreground: 'D4D4D4' },
    { token: 'variable', foreground: '9CDCFE' },
    { token: 'variable.language', foreground: '4FC1FF' },
    { token: 'constant', foreground: '4FC1FF' },
    { token: 'tag', foreground: '569CD6' },
    { token: 'attribute.name', foreground: '9CDCFE' },
    { token: 'attribute.value', foreground: 'CE9178' },
    { token: 'metatag', foreground: 'DCDCAA' },
    { token: 'key.fd', foreground: 'DCDCAA', fontStyle: 'bold' },
    { token: 'value.fd', foreground: 'B5CEA8', fontStyle: 'italic' },
    { token: 'constant.fd', foreground: '4FC1FF' },
    { token: 'number', foreground: 'B5CEA8' },
    { token: 'keyword.fd', foreground: 'C586C0' },
    { token: 'operator.fd', foreground: 'D4D4D4' },
    { token: 'indent.fd', foreground: '404040' },
    { token: 'shebang.fd', foreground: 'F44747', fontStyle: 'bold italic' }
  ];

  function register(monaco) {
    monaco.languages.register({ id: 'fun', extensions: ['.fun'] });
    monaco.languages.setLanguageConfiguration('fun', funConfiguration);
    monaco.languages.setMonarchTokensProvider('fun', funLanguage);

    monaco.languages.register({ id: 'fd', extensions: ['.fd'] });
    monaco.languages.setLanguageConfiguration('fd', fdConfiguration);
    monaco.languages.setMonarchTokensProvider('fd', fdLanguage);

    monaco.languages.register({ id: 'zdata', aliases: ['z-data', 'ZData'] });
    monaco.languages.setLanguageConfiguration('zdata', zdataConfiguration);
    monaco.languages.setMonarchTokensProvider('zdata', zdataLanguage);

    monaco.editor.defineTheme('fun-dark', {
      base: 'vs-dark',
      inherit: true,
      rules: themeRules,
      colors: {
        'editor.background': '#1e1e1e',
        'editor.lineHighlightBackground': '#2a2d2e',
        'editor.selectionBackground': '#264f78'
      }
    });

    monaco.editor.defineTheme('fun-light', {
      base: 'vs',
      inherit: true,
      rules: [
        { token: 'comment', foreground: '008000', fontStyle: 'italic' },
        { token: 'keyword', foreground: '0000FF' },
        { token: 'string', foreground: 'A31515' },
        { token: 'number', foreground: '098658' },
        { token: 'regexp', foreground: '811F3F' },
        { token: 'variable.language', foreground: '0070C1' },
        { token: 'constant', foreground: '0070C1' },
        { token: 'tag', foreground: '800000' },
        { token: 'attribute.name', foreground: 'E50000' },
        { token: 'attribute.value', foreground: '0451A5' },
        { token: 'metatag', foreground: '795E26' },
        { token: 'key.fd', foreground: '795E26', fontStyle: 'bold' },
        { token: 'value.fd', foreground: '098658', fontStyle: 'italic' },
        { token: 'constant.fd', foreground: '0070C1' },
        { token: 'number', foreground: '098658' },
        { token: 'keyword.fd', foreground: 'AF00DB' },
        { token: 'indent.fd', foreground: 'C0C0C0' },
        { token: 'shebang.fd', foreground: 'CD3131', fontStyle: 'bold italic' }
      ],
      colors: {
        'editor.background': '#ffffff',
        'editor.lineHighlightBackground': '#f3f3f3'
      }
    });
  }

  global.MonacoLanguages = {
    register: register,
    funLanguage: funLanguage,
    fdLanguage: fdLanguage,
    zdataLanguage: zdataLanguage
  };
})(window);
