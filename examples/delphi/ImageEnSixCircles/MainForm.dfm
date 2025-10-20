object FormMain: TFormMain
  Left = 0
  Top = 0
  Caption = 'Six Circle Mask Composer - ImageEn'
  ClientHeight = 700
  ClientWidth = 1100
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnCreate = FormCreate
  TextHeight = 13
  object PanelTop: TPanel
    Left = 0
    Top = 0
    Width = 1100
    Height = 56
    Align = alTop
    TabOrder = 0
    object btnLoad: TButton
      Left = 16
      Top = 16
      Width = 120
      Height = 25
      Caption = 'Load 6 Images'
      TabOrder = 0
      OnClick = btnLoadClick
    end
    object btnExport: TButton
      Left = 152
      Top = 16
      Width = 120
      Height = 25
      Caption = 'Export Final'
      TabOrder = 1
      OnClick = btnExportClick
    end
    object btnClear: TButton
      Left = 288
      Top = 16
      Width = 90
      Height = 25
      Caption = 'Clear'
      TabOrder = 2
      OnClick = btnClearClick
    end
    object chkStrictTangency: TCheckBox
      Left = 392
      Top = 20
      Width = 193
      Height = 17
      Caption = 'Strict Tangency (Y=900/3420)'
      TabOrder = 3
      OnClick = chkStrictTangencyClick
    end
    object lblInfo: TLabel
      Left = 600
      Top = 8
      Width = 480
      Height = 41
      Caption = 'Drag each image layer to adjust what is visible inside the circle.\n'
        +'Guides show the circle bounds; final masking is applied on export.'
    end
  end
  object lstSlots: TListBox
    Left = 0
    Top = 56
    Width = 160
    Height = 644
    Align = alLeft
    ItemHeight = 13
    TabOrder = 1
    OnClick = lstSlotsClick
  end
  object ievMain: TImageEnView
    Left = 160
    Top = 56
    Width = 940
    Height = 644
    Align = alClient
    TabOrder = 2
  end
  object OpenDialog1: TOpenDialog
    Left = 984
    Top = 16
  end
end
