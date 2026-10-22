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

unit wv2;

interface

{$I webview2.inc}

uses
  Windows, Messages, Forms, ExtCtrls, Classes, EncdDecd, SysUtils,
  uWVLoader, uWVBrowser, uWVWindowParent, uWVTypes, uWVTypeLibrary,
  uWVCoreWebView2SharedBuffer, uWVCoreWebView2Args;

type
  TEventCallback = function(hwnd, msg, wParam, lParam: Integer): Integer; stdcall;

  TWebBrowserForm = class(TForm)
    WVWindowParent1: TWVWindowParent;
    Timer1: TTimer;
    WVBrowser1: TWVBrowser;

    procedure Timer1Timer(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure WVBrowser1AfterCreated(Sender: TObject);
    procedure WVBrowser1DocumentTitleChanged(Sender: TObject);
    procedure WVBrowser1InitializationError(Sender: TObject; aErrorCode: HRESULT; const aErrorMessage: wvstring);
    procedure WVBrowser1WebMessageReceived(Sender: TObject;
      const aWebView: ICoreWebView2;
      const aArgs: ICoreWebView2WebMessageReceivedEventArgs);
  private
    FSharedBuffer: TCoreWebView2SharedBuffer;
    FStatMax: Cardinal;
    FStatMin: Cardinal;
    FStatAvg: Double;
    FCalBufs: TStringList;
    procedure InitStats;
    procedure UpdateStats(DataSize: Cardinal);
    function  CalcTargetSize(NewDataSize: Cardinal): Cardinal;
    procedure EnsureBufferSize(NewDataSize: Cardinal);
    procedure SendBufferToJS;
    procedure CleanupFCALBuffers;
  protected
    procedure WMMove(var aMessage: TWMMove); message WM_MOVE;
    procedure WMMoving(var aMessage: TMessage); message WM_MOVING;
  public
    procedure Navigate(const url: string);
    function  PostBinary(dataPtr: Pointer; len: Integer): Integer;
  end;

var
  WebBrowserForm: TWebBrowserForm;
  Callback: TEventCallback;

const
  // Callback message codes (centralized; do not hard-code numbers)
  MSG_ERROR        = 0;   // WebView2 initialization or runtime error
  MSG_CREATED      = 1;   // Browser control created
  MSG_TITLE_CHANGED = 2;  // Document title changed
  MSG_BINARY       = 3;   // JS -> Fun binary message (B64 channel)
  MSG_TEXT         = 4;   // Other text messages
  MSG_FCAL_RESULT  = 5;   // fCAL result callback

implementation

{$R *.dfm}

const
  MAX_BUFFER_SIZE = 16 * 1024 * 1024;
  ALPHA           = 0.2;

// ---------- Error notification ----------
procedure NotifyError(hwnd: HWND; errorCode: HRESULT; const errorMsg: string);
begin
  if Assigned(Callback) then
    Callback(hwnd, MSG_ERROR, errorCode, Integer(PChar(errorMsg)));
end;

// ---------- Capacity statistics (jRET channel only) ----------
procedure TWebBrowserForm.InitStats;
begin
  FStatMax := 0;
  FStatMin := High(Cardinal);
  FStatAvg := 0;
end;

procedure TWebBrowserForm.UpdateStats(DataSize: Cardinal);
begin
  if DataSize > FStatMax then FStatMax := DataSize;
  if (DataSize < FStatMin) and (DataSize > 0) then FStatMin := DataSize;
  if FStatAvg = 0 then
    FStatAvg := DataSize
  else
    FStatAvg := ALPHA * DataSize + (1 - ALPHA) * FStatAvg;
end;

function TWebBrowserForm.CalcTargetSize(NewDataSize: Cardinal): Cardinal;
var
  Target: Cardinal;
begin
  Target := NewDataSize;
  if FStatMin <> High(Cardinal) then
    Target := Round((FStatAvg * 2) - FStatMin);
  if Target < NewDataSize then Target := NewDataSize;
  Result := Target;
end;

procedure TWebBrowserForm.EnsureBufferSize(NewDataSize: Cardinal);
var
  TargetSize: Cardinal;
  newIntf: ICoreWebView2SharedBuffer;
  newBuffer: TCoreWebView2SharedBuffer;
  needResize: Boolean;
  keepOldUntilSuccess: Boolean;  // Keep the old buffer until the new one exists
begin
  TargetSize := CalcTargetSize(NewDataSize);
  needResize := False;
  keepOldUntilSuccess := False;

  if not Assigned(FSharedBuffer) then
    needResize := True
  else if FSharedBuffer.Size < TargetSize then
    needResize := True  // Grow: the old buffer is too small, discard it immediately
  else if (FStatMin <> High(Cardinal)) and (FStatAvg > 0) then
    if (FSharedBuffer.Size > TargetSize * 3) and ((FStatAvg - FStatMin) / FStatAvg < 0.1) then
    begin
      needResize := True;
      keepOldUntilSuccess := True;  // Shrink: release the old buffer after the new one is created
    end;

  if needResize then
  begin
    // Grow or no buffer: release the old buffer before creating
    if not keepOldUntilSuccess and Assigned(FSharedBuffer) then
      FreeAndNil(FSharedBuffer);

    if WVBrowser1.CreateSharedBuffer(TargetSize, newIntf) then
    begin
      newBuffer := TCoreWebView2SharedBuffer.Create(newIntf);
      newIntf := nil;
      // Shrink: the new buffer exists, release the old one
      if keepOldUntilSuccess and Assigned(FSharedBuffer) then
        FreeAndNil(FSharedBuffer);
      FSharedBuffer := newBuffer;
    end
    else
      NotifyError(Self.Handle, E_FAIL, 'CreateSharedBuffer failed');
  end;
end;

procedure TWebBrowserForm.SendBufferToJS;
begin
  if Assigned(FSharedBuffer) then
    WVBrowser1.PostSharedBufferToScript(FSharedBuffer.BaseIntf,
      COREWEBVIEW2_SHARED_BUFFER_ACCESS_READ_ONLY, '');
end;

// ---------- Navigation ----------
procedure TWebBrowserForm.Navigate(const url: string);
begin
  with WVBrowser1 do begin
  {$IfNDef Debug}
    DevToolsEnabled := False;
    AreBrowserAcceleratorKeysEnabled := False;
  {$EndIf}
    DefaultContextMenusEnabled := False;
    IsSwipeNavigationEnabled := False;
    StatusBarEnabled := False;
    DefaultScriptDialogsEnabled := False;
    BuiltInErrorPageEnabled := False;
    UserAgent := 'Funcally';
    if url = '' then
    else if url[1] = '<' then NavigateToString(url)
    else Navigate(url);
  end;
end;

// ---------- Send (Fun -> JS; distinguishes jRET from fCAL) ----------
function TWebBrowserForm.PostBinary(dataPtr: Pointer; len: Integer): Integer;
var
  absLen: Cardinal;
  newBuffer: TCoreWebView2SharedBuffer;
  newIntf: ICoreWebView2SharedBuffer;
  handle: Integer;
begin
  if (len = 0) or (dataPtr = nil) then
  begin
    Result := 0;
    Exit;
  end;

  if len < 0 then
  begin
    absLen := Cardinal(-len);
    if not WVBrowser1.CreateSharedBuffer(absLen, newIntf) then
    begin
      Result := 0;
      Exit;
    end;
    newBuffer := TCoreWebView2SharedBuffer.Create(newIntf);
    newIntf := nil;
    Move(dataPtr^, newBuffer.Buffer^, absLen);
    handle := Integer(newBuffer);
    FCalBufs.AddObject(IntToStr(handle), TObject(handle));
    WVBrowser1.PostSharedBufferToScript(newBuffer.BaseIntf,
      COREWEBVIEW2_SHARED_BUFFER_ACCESS_READ_WRITE,
      PWideChar(WideString(IntToStr(handle))));
    Result := handle;
  end
  else
  begin
    UpdateStats(Cardinal(len));
    EnsureBufferSize(Cardinal(len));
    Move(dataPtr^, FSharedBuffer.Buffer^, len);
    SendBufferToJS;
    Result := 1;
  end;
end;

// ---------- Receive (B64 -> MSG_BINARY, FRET -> MSG_FCAL_RESULT, other -> MSG_TEXT) ----------
procedure TWebBrowserForm.WVBrowser1WebMessageReceived(Sender: TObject;
  const aWebView: ICoreWebView2;
  const aArgs: ICoreWebView2WebMessageReceivedEventArgs);
var
  TempArgs: TCoreWebView2WebMessageReceivedEventArgs;
  TempMsg: string;
  DecodedStr: AnsiString;
  handle: Integer;
  idx: Integer;
  keepAlive: Boolean;
  bufObj: TCoreWebView2SharedBuffer;
begin
  TempArgs := TCoreWebView2WebMessageReceivedEventArgs.Create(aArgs);
  TempMsg  := TempArgs.WebMessageAsString;
  TempArgs.Free;

  if Pos('B64:', TempMsg) = 1 then
  begin
    TempMsg := Copy(TempMsg, 5, Length(TempMsg) - 4);
    DecodedStr := DecodeString(TempMsg);
    Callback(Self.Handle, MSG_BINARY, Integer(PAnsiChar(DecodedStr)), Length(DecodedStr));
  end
  else if Pos('FRET:', TempMsg) = 1 then
  begin
    TempMsg := Copy(TempMsg, 6, MaxInt);
    keepAlive := False;
    if Pos(':keep', TempMsg) = Length(TempMsg) - 4 then
    begin
      keepAlive := True;
      SetLength(TempMsg, Length(TempMsg) - 5);
    end;
    handle := StrToIntDef(TempMsg, 0);
    idx := FCalBufs.IndexOf(IntToStr(handle));
    if idx >= 0 then
    begin
      bufObj := TCoreWebView2SharedBuffer(Pointer(FCalBufs.Objects[idx]));
      if Assigned(Callback) then
        Callback(Self.Handle, MSG_FCAL_RESULT, Integer(bufObj.Buffer), bufObj.Size);
      if not keepAlive then
      begin
        bufObj.Free;
        FCalBufs.Delete(idx);
      end;
    end;
  end
  else if TempMsg <> '' then
  begin
    Callback(Self.Handle, MSG_TEXT, Integer(PChar(TempMsg)), Length(TempMsg));
  end;
end;

// ---------- Window and lifetime ----------
procedure TWebBrowserForm.Timer1Timer(Sender: TObject);
begin
  Timer1.Enabled := False;
  if GlobalWebView2Loader.Initialized then
    WVBrowser1.CreateBrowser(WVWindowParent1.Handle)
  else
    Timer1.Enabled := True;
end;

procedure TWebBrowserForm.FormCreate(Sender: TObject);
begin
  inherited;
  InitStats;
  FCalBufs := TStringList.Create;
end;

procedure TWebBrowserForm.FormShow(Sender: TObject);
begin
  if GlobalWebView2Loader.InitializationError then
  begin
    NotifyError(Self.Handle, GlobalWebView2Loader.ErrorCode, GlobalWebView2Loader.ErrorMessage);
    Exit;
  end;
  Timer1Timer(Sender);
end;

procedure TWebBrowserForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  CleanupFCALBuffers;
  FCalBufs.Free;
  if Assigned(FSharedBuffer) then FSharedBuffer.Free;
end;

procedure TWebBrowserForm.CleanupFCALBuffers;
var
  i: Integer;
begin
  if Assigned(FCalBufs) then
  begin
    for i := 0 to FCalBufs.Count - 1 do
      TCoreWebView2SharedBuffer(Pointer(FCalBufs.Objects[i])).Free;
    FCalBufs.Clear;
  end;
end;

procedure TWebBrowserForm.WVBrowser1AfterCreated(Sender: TObject);
begin
  WVWindowParent1.UpdateSize;
  WVWindowParent1.SetFocus;
  if Assigned(Callback) then
    Callback(Self.Handle, MSG_CREATED, 0, 0);
end;

procedure TWebBrowserForm.WVBrowser1DocumentTitleChanged(Sender: TObject);
begin
  Caption := WVBrowser1.DocumentTitle;
  if Assigned(Callback) then
    Callback(Self.Handle, MSG_TITLE_CHANGED, Integer(@Caption[1]), Length(Caption));
end;

procedure TWebBrowserForm.WVBrowser1InitializationError(Sender: TObject;
  aErrorCode: HRESULT; const aErrorMessage: wvstring);
begin
  NotifyError(Self.Handle, aErrorCode, string(aErrorMessage));
end;

procedure TWebBrowserForm.WMMove(var aMessage: TWMMove);
begin
  inherited;
  if WVBrowser1 <> nil then
    WVBrowser1.NotifyParentWindowPositionChanged;
end;

procedure TWebBrowserForm.WMMoving(var aMessage: TMessage);
begin
  inherited;
  if WVBrowser1 <> nil then
    WVBrowser1.NotifyParentWindowPositionChanged;
end;

end.
