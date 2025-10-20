unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.FileCtrl,
  IEView, ImageEnView, ImageEnIO, IEBitmap, Types, Vcl.Imaging.pngimage;

// Delphi XE 10.3 + ImageEn (no layer properties required)
// This version uses a single TImageEnView as a canvas (no layers),
// manages six images' positions in memory, allows dragging to adjust
// their visible area inside fixed circular regions, and exports the
// final composition with horizontal mirror + negative effects.

const
  CANVAS_WIDTH  = 8520;
  CANVAS_HEIGHT = 4320;
  CIRCLE_DIAM   = 1800;
  CIRCLE_RADIUS = CIRCLE_DIAM div 2; // 900

  // Given coordinates (leave ~45px top/bottom margin)
  CENTERS_GIVEN: array[0..5] of TPoint = (
    (X: 1926; Y:  945), (X: 4260; Y:  945), (X: 6594; Y:  945),
    (X: 1926; Y: 3375), (X: 4260; Y: 3375), (X: 6594; Y: 3375)
  );

  // Strict tangency to top/bottom: y = 900 (top row), 3420 (bottom row)
  CENTERS_TANGENT: array[0..5] of TPoint = (
    (X: 1926; Y:  900), (X: 4260; Y:  900), (X: 6594; Y:  900),
    (X: 1926; Y: 3420), (X: 4260; Y: 3420), (X: 6594; Y: 3420)
  );

  SHORT_EDGE_TARGET = 1890; // scale short edge to 1890 px

 type
  TPhotoSlot = record
    Center: TPoint;   // circle center
    FileName: string; // loaded file
    Img: TBitmap;     // scaled image bitmap
    LeftTop: TPoint;  // image top-left position on canvas
  end;

  TFormMain = class(TForm)
    PanelTop: TPanel;
    btnLoad: TButton;
    btnExport: TButton;
    btnClear: TButton;
    chkStrictTangency: TCheckBox;
    lblInfo: TLabel;
    lstSlots: TListBox;
    OpenDialog1: TOpenDialog;
    ievMain: TImageEnView;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure chkStrictTangencyClick(Sender: TObject);
    procedure lstSlotsClick(Sender: TObject);
    procedure ievMainMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ievMainMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ievMainMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  private
    FSlots: array[0..5] of TPhotoSlot;
    FDragging: Boolean;
    FActiveSlot: Integer;
    FDragOffset: TPoint; // mouse pos relative to image top-left (in bitmap coords)

    procedure InitializeCanvas;
    procedure UpdateCenters;
    procedure ClearAll;
    procedure RedrawPreview;
    procedure LoadImages(const Files: TStrings);
    procedure LoadImageIntoSlot(const SlotIndex: Integer; const AFile: string);
    procedure EnsureCoverage(const SlotIndex: Integer);
    function  ActiveSlotIndex: Integer;
    procedure SelectSlot(const SlotIndex: Integer);

    // Export helpers
    procedure ExportFinalImage(const AFileName: string);
    procedure MirrorHorizontalBitmap(B: TBitmap);
    procedure NegativeBitmap(B: TBitmap);
  public
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

procedure TFormMain.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  // Init list box labels
  lstSlots.Items.BeginUpdate;
  try
    lstSlots.Clear;
    for i := 0 to 5 do
      lstSlots.Items.Add(Format('Photo %d', [i + 1]));
  finally
    lstSlots.Items.EndUpdate;
  end;
  lstSlots.ItemIndex := 0;

  // Open dialog
  OpenDialog1.Options := OpenDialog1.Options + [ofAllowMultiSelect];
  OpenDialog1.Filter := 'Image Files|*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff|All Files|*.*';

  // ImageEnView mouse interactions (no layer interactions required)
  // Use official TIEMouseInteract items
  ievMain.MouseInteract := [miZoom, miSmoothZoom, miScroll, miSelectZoom];

  // Default: use given centers (y: 945/3375)
  chkStrictTangency.Checked := False;

  InitializeCanvas;
  UpdateCenters;
  RedrawPreview;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to 5 do
    FreeAndNil(FSlots[i].Img);
end;

procedure TFormMain.InitializeCanvas;
begin
  // Prepare base canvas (IEBitmap) with black background
  ievMain.IEBitmap.SetSize(CANVAS_WIDTH, CANVAS_HEIGHT, ie32RGB);
  ievMain.IEBitmap.Fill(clBlack);
  ievMain.Update;
end;

procedure TFormMain.UpdateCenters;
var
  i: Integer;
begin
  if chkStrictTangency.Checked then
  begin
    for i := 0 to 5 do
      FSlots[i].Center := CENTERS_TANGENT[i];
  end
  else
  begin
    for i := 0 to 5 do
      FSlots[i].Center := CENTERS_GIVEN[i];
  end;

  // Re-center any loaded images onto their circles (preserve offsets if desired)
  for i := 0 to 5 do
    if Assigned(FSlots[i].Img) then
    begin
      FSlots[i].LeftTop.X := FSlots[i].Center.X - FSlots[i].Img.Width div 2;
      FSlots[i].LeftTop.Y := FSlots[i].Center.Y - FSlots[i].Img.Height div 2;
      EnsureCoverage(i);
    end;
end;

procedure TFormMain.ClearAll;
var
  i: Integer;
begin
  for i := 0 to 5 do
  begin
    FreeAndNil(FSlots[i].Img);
    FSlots[i].FileName := '';
    FSlots[i].LeftTop := Point(0, 0);
  end;

  InitializeCanvas;
  UpdateCenters;
  RedrawPreview;
end;

procedure TFormMain.btnClearClick(Sender: TObject);
begin
  ClearAll;
end;

procedure TFormMain.btnLoadClick(Sender: TObject);
begin
  if OpenDialog1.Execute then
  begin
    ClearAll;
    LoadImages(OpenDialog1.Files);
  end;
end;

procedure TFormMain.LoadImages(const Files: TStrings);
var
  i: Integer;
begin
  // Load up to 6 images
  for i := 0 to Min(5, Files.Count - 1) do
    LoadImageIntoSlot(i, Files[i]);

  // Select first slot if available
  SelectSlot(0);

  RedrawPreview;
end;

procedure TFormMain.LoadImageIntoSlot(const SlotIndex: Integer; const AFile: string);
var
  src, scaled: TBitmap;
  w, h, newW, newH: Integer;
  s: Double;
  cx, cy: Integer;
begin
  if (SlotIndex < 0) or (SlotIndex > 5) then Exit;

  FreeAndNil(FSlots[SlotIndex].Img);
  FSlots[SlotIndex].FileName := '';

  src := TBitmap.Create;
  try
    // Load via VCL bitmap (supports BMP/JPG/PNG if JPEG/PNG units are in uses; we have PNG unit)
    src.PixelFormat := pf32bit;
    src.LoadFromFile(AFile);

    w := src.Width; h := src.Height;
    if (w = 0) or (h = 0) then Exit;

    // Scale short edge to 1890
    s := SHORT_EDGE_TARGET / Min(w, h);
    newW := Round(w * s);
    newH := Round(h * s);

    scaled := TBitmap.Create;
    try
      scaled.PixelFormat := pf32bit;
      scaled.SetSize(newW, newH);
      SetStretchBltMode(scaled.Canvas.Handle, HALFTONE);
      StretchBlt(scaled.Canvas.Handle, 0, 0, newW, newH, src.Canvas.Handle, 0, 0, w, h, SRCCOPY);

      FSlots[SlotIndex].Img := TBitmap.Create;
      FSlots[SlotIndex].Img.Assign(scaled);
      FSlots[SlotIndex].FileName := AFile;

      // Initial position: center to circle center
      cx := FSlots[SlotIndex].Center.X;
      cy := FSlots[SlotIndex].Center.Y;
      FSlots[SlotIndex].LeftTop.X := cx - FSlots[SlotIndex].Img.Width div 2;
      FSlots[SlotIndex].LeftTop.Y := cy - FSlots[SlotIndex].Img.Height div 2;
      EnsureCoverage(SlotIndex);
    finally
      scaled.Free;
    end;
  finally
    src.Free;
  end;
end;

procedure TFormMain.EnsureCoverage(const SlotIndex: Integer);
var
  cx, cy: Integer;
  minLeft, maxLeft, minTop, maxTop: Integer;
  Img: TBitmap;
begin
  if (SlotIndex < 0) or (SlotIndex > 5) then Exit;
  Img := FSlots[SlotIndex].Img;
  if not Assigned(Img) then Exit;

  cx := FSlots[SlotIndex].Center.X;
  cy := FSlots[SlotIndex].Center.Y;

  // Ensure the circle (radius 900) is fully covered by the image rect
  // Allowed left range: [cx + r - img.Width, cx - r]
  minLeft := cx + CIRCLE_RADIUS - Img.Width;
  maxLeft := cx - CIRCLE_RADIUS;
  if FSlots[SlotIndex].LeftTop.X < minLeft then FSlots[SlotIndex].LeftTop.X := minLeft;
  if FSlots[SlotIndex].LeftTop.X > maxLeft then FSlots[SlotIndex].LeftTop.X := maxLeft;

  // Allowed top range: [cy + r - img.Height, cy - r]
  minTop := cy + CIRCLE_RADIUS - Img.Height;
  maxTop := cy - CIRCLE_RADIUS;
  if FSlots[SlotIndex].LeftTop.Y < minTop then FSlots[SlotIndex].LeftTop.Y := minTop;
  if FSlots[SlotIndex].LeftTop.Y > maxTop then FSlots[SlotIndex].LeftTop.Y := maxTop;
end;

function TFormMain.ActiveSlotIndex: Integer;
begin
  Result := lstSlots.ItemIndex;
  if (Result < 0) or (Result > 5) then
    Result := 0;
end;

procedure TFormMain.SelectSlot(const SlotIndex: Integer);
begin
  if (SlotIndex < 0) or (SlotIndex > 5) then Exit;
  lstSlots.ItemIndex := SlotIndex;
end;

procedure TFormMain.lstSlotsClick(Sender: TObject);
begin
  SelectSlot(lstSlots.ItemIndex);
end;

procedure TFormMain.chkStrictTangencyClick(Sender: TObject);
begin
  UpdateCenters;
  RedrawPreview;
end;

procedure TFormMain.ievMainMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  bx, by: Integer;
  i: Integer;
  dx, dy: Integer;
begin
  if Button <> mbLeft then Exit;

  // Convert screen coords to bitmap coords using ImageEn helpers
  bx := ievMain.XScr2Bmp(X);
  by := ievMain.YScr2Bmp(Y);

  // Find which circle was clicked
  FActiveSlot := -1;
  for i := 0 to 5 do
    if Assigned(FSlots[i].Img) then
    begin
      dx := bx - FSlots[i].Center.X;
      dy := by - FSlots[i].Center.Y;
      if (dx * dx + dy * dy) <= (CIRCLE_RADIUS * CIRCLE_RADIUS) then
      begin
        FActiveSlot := i;
        Break;
      end;
    end;

  if FActiveSlot >= 0 then
  begin
    FDragging := True;
    FDragOffset.X := bx - FSlots[FActiveSlot].LeftTop.X;
    FDragOffset.Y := by - FSlots[FActiveSlot].LeftTop.Y;
    SelectSlot(FActiveSlot);
  end;
end;

procedure TFormMain.ievMainMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  bx, by: Integer;
begin
  if not FDragging then Exit;
  bx := ievMain.XScr2Bmp(X);
  by := ievMain.YScr2Bmp(Y);

  if (FActiveSlot >= 0) and (FActiveSlot <= 5) and Assigned(FSlots[FActiveSlot].Img) then
  begin
    FSlots[FActiveSlot].LeftTop.X := bx - FDragOffset.X;
    FSlots[FActiveSlot].LeftTop.Y := by - FDragOffset.Y;
    EnsureCoverage(FActiveSlot);
    RedrawPreview;
  end;
end;

procedure TFormMain.ievMainMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    FDragging := False;
end;

procedure TFormMain.RedrawPreview;
var
  dest: TBitmap;
  i: Integer;
  cx, cy, r: Integer;
  Rgn: HRGN;
begin
  dest := TBitmap.Create;
  try
    dest.PixelFormat := pf32bit;
    dest.SetSize(CANVAS_WIDTH, CANVAS_HEIGHT);
    dest.Canvas.Brush.Color := clBlack;
    dest.Canvas.FillRect(Rect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT));

    // Draw each image clipped to its circle
    for i := 0 to 5 do
      if Assigned(FSlots[i].Img) then
      begin
        cx := FSlots[i].Center.X;
        cy := FSlots[i].Center.Y;
        r := CIRCLE_RADIUS;

        Rgn := CreateEllipticRgn(cx - r, cy - r, cx + r, cy + r);
        try
          SelectClipRgn(dest.Canvas.Handle, Rgn);
          SetStretchBltMode(dest.Canvas.Handle, HALFTONE);
          BitBlt(dest.Canvas.Handle,
                 FSlots[i].LeftTop.X, FSlots[i].LeftTop.Y,
                 FSlots[i].Img.Width, FSlots[i].Img.Height,
                 FSlots[i].Img.Canvas.Handle, 0, 0, SRCCOPY);
        finally
          SelectClipRgn(dest.Canvas.Handle, 0);
          DeleteObject(Rgn);
        end;
      end;

    // Draw guide circles (white outline)
    dest.Canvas.Brush.Style := bsClear;
    dest.Canvas.Pen.Color := clWhite;
    dest.Canvas.Pen.Width := 4;
    for i := 0 to 5 do
    begin
      cx := FSlots[i].Center.X;
      cy := FSlots[i].Center.Y;
      r := CIRCLE_RADIUS;
      dest.Canvas.Ellipse(cx - r, cy - r, cx + r, cy + r);
    end;

    // Assign to ImageEnView
    ievMain.IEBitmap.AssignFromBitmap(dest);
    ievMain.Update;
  finally
    dest.Free;
  end;
end;

procedure TFormMain.btnExportClick(Sender: TObject);
var
  fn: string;
begin
  if SelectDirectory('Choose output folder', '', fn) then
    ExportFinalImage(IncludeTrailingPathDelimiter(fn) + 'output.png')
  else
  begin
    with TSaveDialog.Create(Self) do
    try
      Filter := 'PNG Image|*.png|JPEG Image|*.jpg;*.jpeg|Bitmap|*.bmp|All Files|*.*';
      DefaultExt := 'png';
      FileName := 'output.png';
      if Execute then
        ExportFinalImage(FileName);
    finally
      Free;
    end;
  end;
end;

procedure TFormMain.MirrorHorizontalBitmap(B: TBitmap);
var
  y, x: Integer;
  tmp: array of byte;
  wBytes: Integer;
begin
  B.PixelFormat := pf32bit;
  wBytes := B.Width * 4;
  SetLength(tmp, wBytes);
  for y := 0 to B.Height - 1 do
  begin
    Move(B.Scanline[y]^, tmp[0], wBytes);
    for x := 0 to B.Width - 1 do
      Move(tmp[(B.Width - 1 - x) * 4], PByte(B.Scanline[y])^[x * 4], 4);
  end;
end;

procedure TFormMain.NegativeBitmap(B: TBitmap);
var
  x, y: Integer;
  p: PByte;
begin
  B.PixelFormat := pf32bit;
  for y := 0 to B.Height - 1 do
  begin
    p := B.Scanline[y];
    for x := 0 to B.Width - 1 do
    begin
      // BGRA order in VCL
      p^ := 255 - p^; Inc(p); // B
      p^ := 255 - p^; Inc(p); // G
      p^ := 255 - p^; Inc(p); // R
      Inc(p);                 // A
    end;
  end;
end;

procedure TFormMain.ExportFinalImage(const AFileName: string);
var
  dest: TBitmap;
  i: Integer;
  cx, cy, r: Integer;
  Rgn: HRGN;
  tmp: TBitmap;
begin
  dest := TBitmap.Create;
  try
    dest.PixelFormat := pf32bit;
    dest.SetSize(CANVAS_WIDTH, CANVAS_HEIGHT);
    dest.Canvas.Brush.Color := clBlack;
    dest.Canvas.FillRect(Rect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT));

    for i := 0 to 5 do
      if Assigned(FSlots[i].Img) then
      begin
        // Prepare a copy for transformation (mirror + negative)
        tmp := TBitmap.Create;
        try
          tmp.PixelFormat := pf32bit;
          tmp.SetSize(FSlots[i].Img.Width, FSlots[i].Img.Height);
          BitBlt(tmp.Canvas.Handle, 0, 0, tmp.Width, tmp.Height, FSlots[i].Img.Canvas.Handle, 0, 0, SRCCOPY);

          MirrorHorizontalBitmap(tmp);
          NegativeBitmap(tmp);

          cx := FSlots[i].Center.X;
          cy := FSlots[i].Center.Y;
          r := CIRCLE_RADIUS;

          Rgn := CreateEllipticRgn(cx - r, cy - r, cx + r, cy + r);
          try
            SelectClipRgn(dest.Canvas.Handle, Rgn);
            SetStretchBltMode(dest.Canvas.Handle, HALFTONE);
            BitBlt(dest.Canvas.Handle,
                   FSlots[i].LeftTop.X, FSlots[i].LeftTop.Y,
                   tmp.Width, tmp.Height,
                   tmp.Canvas.Handle, 0, 0, SRCCOPY);
          finally
            SelectClipRgn(dest.Canvas.Handle, 0);
            DeleteObject(Rgn);
          end;
        finally
          tmp.Free;
        end;
      end;

    // Save as PNG (using VCL PNG)
    with TPngImage.Create do
    try
      Assign(dest);
      SaveToFile(AFileName);
    finally
      Free;
    end;

    ShowMessage('Exported: ' + AFileName);
  finally
    dest.Free;
  end;
end;

end.
