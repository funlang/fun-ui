@echo off
rem ============================================================
rem fun-ui WebView2 bridge build environment
rem Copyright (c) 2026 funlang.org
rem
rem Permission is hereby granted, free of charge, to any person obtaining a copy
rem of this software and associated documentation files (the "Software"), to deal
rem in the Software without restriction, including without limitation the rights
rem to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
rem copies of the Software, and to permit persons to whom the Software is
rem furnished to do so, subject to the following conditions:
rem
rem The above copyright notice and this permission notice shall be included in all
rem copies or substantial portions of the Software.
rem
rem THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
rem IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
rem FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
rem AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
rem LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
rem OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
rem SOFTWARE.
rem ============================================================
rem Edit the paths below to match your machine, then run
rem make-2006.bat. You may also pre-set any of these variables
rem in your shell or IDE; the `if not defined` guards let
rem your values win.
rem ============================================================

rem --- Fun language checkout (the sibling `fun` repository) ---
rem     The Fun-side libraries in fun/lib expect the standard
rem     Fun runtime and its lib/ folder on the module path.
if not defined FUN_ROOT set "FUN_ROOT=%~dp0..\..\..\..\fun"
for %%I in ("%FUN_ROOT%") do set "FUN_ROOT=%%~fI"

rem --- Delphi 2006 (used by make-2006.bat) ---
if not defined DELPHI2006 set "DELPHI2006=D:\Borland\Delphi2006"

rem --- WebView4Delphi source folder ---
rem     Must contain uWVLoader.pas, uWVBrowser.pas and the other
rem     WebView4Delphi units. The default assumes this repository
rem     and WebView4Delphi are checked out side by side:
rem         <parent>\fun-ui\src\prj\lib.wv2\  ->  <parent>\WebView4Delphi\source
if not defined WV2_SRC set "WV2_SRC=%~dp0..\..\..\..\WebView4Delphi\source"
for %%I in ("%WV2_SRC%") do set "WV2_SRC=%%~fI"
