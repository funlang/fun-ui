object WebBrowserForm: TWebBrowserForm
  BorderStyle = bsNone
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnClose = FormClose
  OnShow = FormShow
  OnCreate = FormCreate
  TextHeight = 15
  object WVWindowParent1: TWVWindowParent
    Align = alClient
    TabStop = True
    TabOrder = 0
    Browser = WVBrowser1
  end
  object Timer1: TTimer
    Enabled = False
    Interval = 300
    OnTimer = Timer1Timer
  end
  object WVBrowser1: TWVBrowser
    DefaultURL = ''
    TargetCompatibleBrowserVersion = '95.0.1020.44'
    AllowSingleSignOnUsingOSPrimaryAccount = False
    OnInitializationError = WVBrowser1InitializationError
    OnAfterCreated = WVBrowser1AfterCreated
    OnDocumentTitleChanged = WVBrowser1DocumentTitleChanged
    OnWebMessageReceived = WVBrowser1WebMessageReceived
  end
end
