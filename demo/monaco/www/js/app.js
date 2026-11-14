// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// Offline Monaco editor demo: z-data drives the chrome, Monaco edits code,
// and the fun-ui bridge exposes one Fun method to the status bar.

(function (global) {
  'use strict';

  var LANGS = {
    fun: { label: 'Fun', model: 'fun', ext: 'fun' },
    fd: { label: 'FD', model: 'fd', ext: 'fd' },
    js: { label: 'JavaScript', model: 'javascript', ext: 'js' },
    html: { label: 'HTML', model: 'html', ext: 'html' },
    css: { label: 'CSS', model: 'css', ext: 'css' },
    zdata: { label: 'z-data', model: 'zdata', ext: 'html' }
  };

  var EXT_LANG = {
    fun: 'fun',
    fd: 'fd',
    js: 'js',
    mjs: 'js',
    cjs: 'js',
    html: 'html',
    htm: 'html',
    css: 'css'
  };

  var KEY_LANG = 'fun-monaco:lang';
  var KEY_THEME = 'fun-monaco:theme';

  function contentKey(lang) {
    return 'fun-monaco:content:' + lang;
  }

  function storageGet(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }

  function storageSet(key, value) {
    try { localStorage.setItem(key, value); } catch (e) {}
  }

  function themeName(theme) {
    return theme === 'light' ? 'fun-light' : 'fun-dark';
  }

  var Editor = {
    root: null,
    data: null,
    monaco: null,
    editor: null,
    lang: 'fun',
    saveTimer: null,
    logoTimer: null
  };

  Editor.start = function (root) {
    Editor.root = root;
    Editor.data = root.$data;
    root.removeAttribute('z-cloak');

    var lang = storageGet(KEY_LANG);
    if (!LANGS[lang]) lang = 'fun';
    var theme = storageGet(KEY_THEME);
    if (theme !== 'light' && theme !== 'dark') theme = 'dark';

    Editor.data.theme = theme;
    Editor.applyLanguage(lang, false);
    Editor.setSelect(lang);

    require.config({
      paths: { vs: '/vendor/monaco/vs' },
      'vs/nls': { availableLanguages: { '*': 'zh-cn' } }
    });

    require(['vs/editor/editor.main'], function () {
      global.monaco = monaco;
      Editor.monaco = monaco;
      MonacoLanguages.register(monaco);

      // The HTML and z-data grammars embed CSS and JavaScript. These modules
      // read self.monaco while loading, so require them only after the
      // editor module has published the global API.
      require([
        'vs/basic-languages/css/css',
        'vs/basic-languages/javascript/javascript'
      ], function () {
        Editor.create(lang, theme);
      });
    });
  };

  Editor.create = function (lang, theme) {
    if (Editor.editor) return;
    var monaco = Editor.monaco;

    var saved = storageGet(contentKey(lang));
    var value = saved !== null ? saved : (global.EDITOR_SAMPLES[lang] || '');
    var info = LANGS[lang];

    Editor.editor = monaco.editor.create(document.getElementById('editor'), {
      value: value,
      language: info.model,
      theme: themeName(theme),
      automaticLayout: true,
      fontSize: 14,
      tabSize: 2,
      insertSpaces: true,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      smoothScrolling: true,
      renderWhitespace: 'selection',
      bracketPairColorization: { enabled: true },
      padding: { top: 12, bottom: 12 },
      wordWrap: 'off',
      fixedOverflowWidgets: true
    });

    Editor.editor.onDidChangeCursorPosition(function (e) {
      Editor.data.position = 'Ln ' + e.position.lineNumber + ', Col ' + e.position.column;
    });

    Editor.editor.onDidChangeModelContent(function () {
      clearTimeout(Editor.saveTimer);
      Editor.saveTimer = setTimeout(function () {
        Editor.saveContent(Editor.lang);
      }, 300);
    });

    Editor.editor.addCommand(
      monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS,
      function () { Editor.download(); }
    );

    Editor.editor.focus();
    Editor.updatePosition();
    Editor.callFun();
    Editor.notify('Monaco loaded offline');
  };

  Editor.applyLanguage = function (lang, loadContent) {
    var info = LANGS[lang] || LANGS.fun;
    Editor.lang = lang;
    if (Editor.data) {
      Editor.data.lang = lang;
      Editor.data.langLabel = info.label;
    }
    if (Editor.editor) {
      Editor.monaco.editor.setModelLanguage(Editor.editor.getModel(), info.model);
      if (loadContent) {
        var saved = storageGet(contentKey(lang));
        Editor.editor.setValue(saved !== null ? saved : (global.EDITOR_SAMPLES[lang] || ''));
        Editor.editor.setPosition({ lineNumber: 1, column: 1 });
        Editor.editor.focus();
      }
      Editor.updatePosition();
    }
    storageSet(KEY_LANG, lang);
    Editor.setSelect(lang);
  };

  Editor.setSelect = function (lang) {
    var select = document.getElementById('lang');
    if (select) select.value = lang;
  };

  Editor.setLang = function (lang) {
    if (!LANGS[lang] || lang === Editor.lang) return;
    Editor.saveContent(Editor.lang);
    Editor.applyLanguage(lang, true);
    Editor.notify('Language: ' + LANGS[lang].label);
  };

  Editor.saveContent = function (lang) {
    if (!Editor.editor) return;
    storageSet(contentKey(lang), Editor.editor.getValue());
  };

  Editor.loadSample = function () {
    if (!Editor.editor) return;
    Editor.saveContent(Editor.lang);
    var current = Editor.editor.getValue();
    var sample = global.EDITOR_SAMPLES[Editor.lang] || '';
    if (current.trim() && current !== sample &&
        !global.confirm('Replace the current buffer with the ' + LANGS[Editor.lang].label + ' sample?')) {
      return;
    }
    Editor.editor.setValue(sample);
    Editor.editor.setPosition({ lineNumber: 1, column: 1 });
    Editor.editor.focus();
    Editor.notify('Sample: ' + LANGS[Editor.lang].label);
  };

  Editor.openFile = function () {
    var input = document.getElementById('file');
    if (input) input.click();
  };

  Editor.onFile = function (input) {
    var file = input && input.files && input.files[0];
    if (!file) return;
    var reader = new FileReader();
    reader.onload = function () {
      var ext = (file.name.split('.').pop() || '').toLowerCase();
      var lang = EXT_LANG[ext] || Editor.lang;
      Editor.saveContent(Editor.lang);
      if (lang !== Editor.lang) Editor.applyLanguage(lang, false);
      Editor.editor.setValue(String(reader.result));
      Editor.editor.setPosition({ lineNumber: 1, column: 1 });
      Editor.editor.focus();
      Editor.saveContent(lang);
      Editor.notify('Opened ' + file.name);
    };
    reader.readAsText(file);
    input.value = '';
  };

  Editor.download = function () {
    if (!Editor.editor) return;
    Editor.saveContent(Editor.lang);
    var info = LANGS[Editor.lang];
    var blob = new Blob([Editor.editor.getValue()], { type: 'text/plain;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'untitled.' + info.ext;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    Editor.notify('Downloaded untitled.' + info.ext);
  };

  Editor.applyTheme = function (theme) {
    if (Editor.data) Editor.data.theme = theme;
    if (Editor.editor) Editor.monaco.editor.setTheme(themeName(theme));
    storageSet(KEY_THEME, theme);
  };

  Editor.toggleTheme = function () {
    Editor.applyTheme(Editor.data.theme === 'dark' ? 'light' : 'dark');
  };

  Editor.updatePosition = function () {
    if (!Editor.editor) return;
    var pos = Editor.editor.getPosition();
    Editor.data.position = 'Ln ' + pos.lineNumber + ', Col ' + pos.column;
  };

  Editor.callFun = function () {
    if (typeof global.Fun !== 'function') {
      Editor.data.funStatus = 'standalone (no Fun bridge)';
      return;
    }
    global.Fun('info').then(function (reply) {
      var name = reply && (reply.service || reply.status);
      Editor.data.funStatus = 'Fun bridge: ' + (name || 'connected');
    }).catch(function (err) {
      Editor.data.funStatus = 'Fun bridge: ' + (err && err.message ? err.message : err);
    });
  };

  Editor.notify = function (text) {
    if (!Editor.data) return;
    Editor.data.message = text;
    clearTimeout(Editor.logoTimer);
    Editor.logoTimer = setTimeout(function () {
      if (Editor.data) Editor.data.message = '';
    }, 3000);
  };

  global.Editor = Editor;

  global.app = function () {
    return {
      lang: 'fun',
      langLabel: 'Fun',
      theme: 'dark',
      position: 'Ln 1, Col 1',
      funStatus: 'checking Fun bridge...',
      message: ''
    };
  };

  global.addEventListener('beforeunload', function () {
    if (Editor.editor) Editor.saveContent(Editor.lang);
  });
})(window);
