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

library libwv2;

uses
  SysUtils, Forms, uWVLoader, wv2;

function Init(cb: Integer): Integer; stdcall;
begin
  Callback := TEventCallback(cb);
  GlobalWebView2Loader := TWVLoader.Create(nil);
  with GlobalWebView2Loader do
  begin
    UserDataFolder := IncludeTrailingPathDelimiter(ExtractFileDir(GetModuleName(HINSTANCE))) + '\CustomCache';
    // Core configuration: disable CORS
    DisableWebSecurity := True;
    // Disable unused security and tracking features
    SmartScreenProtectionEnabled := False;
    AreBrowserExtensionsEnabled := False;
    EnableTrackingPrevention := False;
    // Additional hardening
    AllowFileAccessFromFiles := False;
    AllowInsecureLocalhost := False;
    HyperlinkAuditing := False;
    // Start WebView2
    StartWebView2;
  end;
  Result := 0;
end;

function Free: Integer; stdcall;
begin
  DestroyGlobalWebView2Loader;
  Result := 0;
end;

function Show(pHandle: Integer): Integer; stdcall;
begin
  WebBrowserForm := TWebBrowserForm.Create(nil);
  if pHandle = 0 then
    WebBrowserForm.BorderStyle := bsSizeable;
  WebBrowserForm.Show;
  Result := Integer(WebBrowserForm.Handle);
end;

function Navigate(url: PChar): Integer; stdcall;
begin
  if Assigned(WebBrowserForm) then
    WebBrowserForm.Navigate(url);
  Result := 0;
end;

function PostData(dataPtr: PByte; len: Integer): Integer; stdcall;
begin
  Result := 0;
  if Assigned(WebBrowserForm) then
    Result := WebBrowserForm.PostBinary(dataPtr, len);
end;

function ExecScript(script: PChar): Integer; stdcall;
begin
  if Assigned(WebBrowserForm) then
    WebBrowserForm.WVBrowser1.ExecuteScript(script);
  Result := 0;
end;

function Close: Integer; stdcall;
begin
  if Assigned(WebBrowserForm) then
  begin
    WebBrowserForm.Close;
    WebBrowserForm := nil;
  end;
  Result := 0;
end;

exports
  Init, Free, Show, Navigate, PostData, ExecScript, Close;

begin
end.
