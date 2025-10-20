unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.FileCtrl,
  IEView, ImageEnView, ImageEnIO, ImageEnProc, IEBitmap, IELayers, Types, Vcl.Imaging.pngimage;

// NOTE:
// - This sample targets Delphi XE 10.3 (Rio) with ImageEn installed.
// - Unit names may differ slightly depending on ImageEn version (IEView vs ImageEnView, etc.).
// - Adjust uses and API names to your installed ImageEn version if necessary.

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

type
  TPhotoSlot = record
    Center: TPoint;
    ImageLayerIdx: Integer; // index in ievMain.Layers
    MaskLayerIdx: Integer;  // optional, if using layer mask
    GuideLayerIdx: Integer; // ellipse outline for guidance
    FileName: string;       // original path
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
    procedure btnClearClick(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure chkStrictTangencyClick(Sender: TObject);
    procedure lstSlotsClick(Sender: TObject);
    procedure ievMainLayerNotify(Sender: TObject; layer: Integer; event: TIELayerEvent);
  private
    FSlots: array[0..5] of TPhotoSlot;
    FMaskPreviewEnabled: Boolean;
    procedure InitializeCanvas;
    procedure BuildGuides;
    procedure UpdateCenters;
    procedure ClearAll;
    procedure LoadImages(const Files: TStrings);
    procedure LoadImageIntoSlot(const SlotIndex: Integer; const AFile: string);
    procedure EnsureCoverage(const SlotIndex: Integer);
    function  ActiveSlotIndex: Integer;
    procedure SelectSlot(const SlotIndex: Integer);

    // Optional: Attach a shape mask layer to an image layer (API names may vary by ImageEn version)
    procedure CreateAndAttachMaskLayer(const SlotIndex: Integer);

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
  // Init list
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

  // ImageEnView
  ievMain.LayersEnabled := True;
  ievMain.MouseInteractGeneral := ievMain.MouseInteractGeneral + [miMoveLayers];
  ievMain.OnLayerNotify := ievMainLayerNotify;

  // Default: use given centers (y: 945/3375)
  chkStrictTangency.Checked := False;
  FMaskPreviewEnabled := False; // we use guide outlines; final mask applied on export

  InitializeCanvas;
  UpdateCenters;
  BuildGuides;
end;

procedure TFormMain.InitializeCanvas;
var
  bg: TIELayer;
begin
  // Create background black canvas as base layer
  ievMain.IEBitmap.SetSize(CANVAS_WIDTH, CANVAS_HEIGHT, ie32RGB);
  ievMain.IEBitmap.Fill(clBlack);
  ievMain.Update;

  // Lock background layer (usually index 0)
  if ievMain.LayersCount > 0 then
  begin
    bg := ievMain.Layers[0];
    bg.Locked := True;
    bg.Selectable := False;
    bg.Name := 'Background';
  end;
end;

procedure TFormMain.UpdateCenters;
var
  i: Integer;
  arr: PPoint;
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
end;

procedure TFormMain.BuildGuides;
var
  i, idx: Integer;
  shp: TIEShapeLayer;
  cx, cy: Integer;
begin
  // Remove old guide layers if any
  for i := 0 to 5 do
  begin
    if (FSlots[i].GuideLayerIdx > 0) and (FSlots[i].GuideLayerIdx < ievMain.LayersCount) then
      ievMain.LayersDelete(FSlots[i].GuideLayerIdx);
    FSlots[i].GuideLayerIdx := -1;
  end;

  // Build 6 ellipse outline guides
  for i := 0 to 5 do
  begin
    cx := FSlots[i].Center.X;
    cy := FSlots[i].Center.Y;

    idx := ievMain.LayersAdd(ielkShape);
    shp := TIEShapeLayer(ievMain.Layers[idx]);
    shp.Shape := ielsEllipse;
    shp.Left := cx - CIRCLE_RADIUS;
    shp.Top := cy - CIRCLE_RADIUS;
    shp.Width := CIRCLE_DIAM;
    shp.Height := CIRCLE_DIAM;
    shp.FillColor := clNone;          // transparent fill
    shp.FillOpacity := 0;
    shp.PenWidth := 4;
    shp.PenColor := clWhite;
    shp.PenStyle := psSolid;          // change to psDash for dashed outline if desired
    shp.Locked := True;
    shp.Selectable := False;
    shp.Name := Format('Guide%d', [i + 1]);

    FSlots[i].GuideLayerIdx := idx;
  end;

  // Make sure guides are on top
  ievMain.LayersReorderToTop(FSlots[5].GuideLayerIdx);
  ievMain.Update;
end;

procedure TFormMain.ClearAll;
var
  i: Integer;
begin
  // Clear all layers except background
  while ievMain.LayersCount > 1 do
    ievMain.LayersDelete(1);

  for i := 0 to 5 do
  begin
    FSlots[i].ImageLayerIdx := -1;
    FSlots[i].MaskLayerIdx := -1;
    FSlots[i].GuideLayerIdx := -1;
    FSlots[i].FileName := '';
  end;

  InitializeCanvas;
  UpdateCenters;
  BuildGuides;
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

  // Rebuild guides so they stay on top
  BuildGuides;

  // Select first slot if available
  SelectSlot(0);
end;

procedure TFormMain.LoadImageIntoSlot(const SlotIndex: Integer; const AFile: string);
var
  bmp: TIEBitmap;
  imgIdx: Integer;
  img: TIEImageLayer;
  s: Double;
  w, h, newW, newH: Integer;
  cx, cy: Integer;
begin
  if (SlotIndex < 0) or (SlotIndex > 5) then
    Exit;

  bmp := TIEBitmap.Create;
  try
    // Load image (adjust to your ImageEn version; Read/LoadFromFile/etc.)
    try
      bmp.Read(AFile);
    except
      bmp.LoadFromFile(AFile);
    end;

    w := bmp.Width;  h := bmp.Height;
    if (w = 0) or (h = 0) then Exit;

    // Scale: short edge -> 1890
    s := 1890.0 / Min(w, h);
    newW := Round(w * s);
    newH := Round(h * s);
    bmp.Resample(newW, newH, rfLanczos3);

    // Create image layer and assign bitmap
    imgIdx := ievMain.LayersAdd(ielkImage);
    img := TIEImageLayer(ievMain.Layers[imgIdx]);
    img.IEBitmap.Assign(bmp);

    // Initial position: center to circle center
    cx := FSlots[SlotIndex].Center.X;
    cy := FSlots[SlotIndex].Center.Y;
    img.Left := cx - img.Width div 2;
    img.Top := cy - img.Height div 2;

    img.Locked := False;
    img.Selectable := True;
    img.Resizable := False;  // disable resize; adjust if you want
    img.Rotatable := False;  // disable rotate
    img.Name := Format('Image%d', [SlotIndex + 1]);

    FSlots[SlotIndex].ImageLayerIdx := imgIdx;
    FSlots[SlotIndex].FileName := AFile;

    // Optional: create a dedicated mask layer attached to this image layer (if supported by your ImageEn version)
    // CreateAndAttachMaskLayer(SlotIndex);

    // Enforce that the circle is fully covered
    EnsureCoverage(SlotIndex);

  finally
    bmp.Free;
  end;
end;

procedure TFormMain.CreateAndAttachMaskLayer(const SlotIndex: Integer);
var
  maskIdx: Integer;
  m: TIEShapeLayer;
  cx, cy: Integer;
  imgIdx: Integer;
  img: TIEImageLayer;
begin
  if (SlotIndex < 0) or (SlotIndex > 5) then Exit;
  imgIdx := FSlots[SlotIndex].ImageLayerIdx;
  if (imgIdx < 0) or (imgIdx >= ievMain.LayersCount) then Exit;
  img := TIEImageLayer(ievMain.Layers[imgIdx]);

  // Create ellipse mask shape
  maskIdx := ievMain.LayersAdd(ielkShape);
  m := TIEShapeLayer(ievMain.Layers[maskIdx]);
  cx := FSlots[SlotIndex].Center.X;
  cy := FSlots[SlotIndex].Center.Y;
  m.Shape := ielsEllipse;
  m.Left := cx - CIRCLE_RADIUS;
  m.Top := cy - CIRCLE_RADIUS;
  m.Width := CIRCLE_DIAM;
  m.Height := CIRCLE_DIAM;
  m.FillColor := clWhite;  // mask area is white (visible)
  m.PenStyle := psClear;   // no outline
  m.Locked := True;
  m.Selectable := False;
  m.Name := Format('Mask%d', [SlotIndex + 1]);

  // Attach mask to image layer (the exact API may vary by ImageEn version)
  // Some versions may provide: img.MaskLayer := maskIdx; or ievMain.LayersSetMask(imgIdx, maskIdx);
  try
    img.MaskLayer := maskIdx; // adjust to your version if needed
  except
    // If your version uses a different API, set it here, e.g.:
    // ievMain.LayersSetMask(imgIdx, maskIdx);
  end;

  FSlots[SlotIndex].MaskLayerIdx := maskIdx;
end;

procedure TFormMain.EnsureCoverage(const SlotIndex: Integer);
var
  imgIdx: Integer;
  img: TIEImageLayer;
  cx, cy: Integer;
  L, T_, R, B: Integer;
  minLeft, maxLeft, minTop, maxTop: Integer;
begin
  if (SlotIndex < 0) or (SlotIndex > 5) then Exit;
  imgIdx := FSlots[SlotIndex].ImageLayerIdx;
  if (imgIdx < 0) or (imgIdx >= ievMain.LayersCount) then Exit;

  img := TIEImageLayer(ievMain.Layers[imgIdx]);
  cx := FSlots[SlotIndex].Center.X;
  cy := FSlots[SlotIndex].Center.Y;

  // For full coverage of circle (radius 900), enforce image rect covers [cx-r, cy-r] .. [cx+r, cy+r]
  // Allowed left range: [cx + r - img.Width, cx - r]
  minLeft := cx + CIRCLE_RADIUS - img.Width;
  maxLeft := cx - CIRCLE_RADIUS;
  if img.Left < minLeft then img.Left := minLeft;
  if img.Left > maxLeft then img.Left := maxLeft;

  // Allowed top range: [cy + r - img.Height, cy - r]
  minTop := cy + CIRCLE_RADIUS - img.Height;
  maxTop := cy - CIRCLE_RADIUS;
  if img.Top < minTop then img.Top := minTop;
  if img.Top > maxTop then img.Top := maxTop;

  ievMain.Update;
end;

function TFormMain.ActiveSlotIndex: Integer;
var
  i: Integer;
  idx: Integer;
begin
  Result := lstSlots.ItemIndex;
  if (Result >= 0) and (Result < 6) then Exit;

  // fallback: find by current layer
  idx := ievMain.CurrentLayer;
  for i := 0 to 5 do
    if FSlots[i].ImageLayerIdx = idx then
      Exit(i);

  Result := 0;
end;

procedure TFormMain.SelectSlot(const SlotIndex: Integer);
begin
  if (SlotIndex < 0) or (SlotIndex > 5) then Exit;
  lstSlots.ItemIndex := SlotIndex;
  if (FSlots[SlotIndex].ImageLayerIdx >= 0) and (FSlots[SlotIndex].ImageLayerIdx < ievMain.LayersCount) then
    ievMain.CurrentLayer := FSlots[SlotIndex].ImageLayerIdx;
end;

procedure TFormMain.lstSlotsClick(Sender: TObject);
begin
  SelectSlot(lstSlots.ItemIndex);
end;

procedure TFormMain.chkStrictTangencyClick(Sender: TObject);
begin
  UpdateCenters;
  BuildGuides;
  // Re-enforce coverage since the circle may shift vertically
  EnsureCoverage(ActiveSlotIndex);
end;

procedure TFormMain.ievMainLayerNotify(Sender: TObject; layer: Integer; event: TIELayerEvent);
var
  i: Integer;
begin
  // When a layer moves, if it is one of the image layers, keep coverage
  if event = ielChanged then
  begin
    for i := 0 to 5 do
      if FSlots[i].ImageLayerIdx = layer then
      begin
        EnsureCoverage(i);
        Break;
      end;
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
  pRow: PByte;
  tmp: array of byte;
  wBytes: Integer;
begin
  // Assumes pf32bit
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
  c: array[0..3] of byte;
begin
  // Invert RGB channels; keep alpha if present
  B.PixelFormat := pf32bit;
  for y := 0 to B.Height - 1 do
  begin
    p := B.Scanline[y];
    for x := 0 to B.Width - 1 do
    begin
      // Pixel format is BGRA in VCL
      p^ := 255 - p^;           // B
      Inc(p);
      p^ := 255 - p^;           // G
      Inc(p);
      p^ := 255 - p^;           // R
      Inc(p);
      // Alpha
      Inc(p);
    end;
  end;
end;

procedure TFormMain.ExportFinalImage(const AFileName: string);
var
  dest: TBitmap;
  i: Integer;
  cx, cy, r: Integer;
  imgIdx: Integer;
  img: TIEImageLayer;
  src, scaled: TBitmap;
  Rgn: HRGN;
  oldRgn: HRGN;
  destRect: TRect;
  sIE: TIEBitmap;
  Png: TPngImage;
begin
  dest := TBitmap.Create;
  try
    dest.SetSize(CANVAS_WIDTH, CANVAS_HEIGHT);
    dest.PixelFormat := pf32bit;
    dest.Canvas.Brush.Color := clBlack;
    dest.Canvas.FillRect(Rect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT));

    for i := 0 to 5 do
    begin
      cx := FSlots[i].Center.X;
      cy := FSlots[i].Center.Y;
      r := CIRCLE_RADIUS;

      imgIdx := FSlots[i].ImageLayerIdx;
      if (imgIdx < 0) or (imgIdx >= ievMain.LayersCount) then
        Continue;
      img := TIEImageLayer(ievMain.Layers[imgIdx]);

      // Obtain a bitmap for the current image layer
      src := TBitmap.Create;
      try
        src.PixelFormat := pf32bit;
        // Try to copy from IEBitmap directly
        try
          sIE := TIEBitmap.Create;
          try
            sIE.Assign(img.IEBitmap);
            sIE.AssignToBitmap(src);
          finally
            sIE.Free;
          end;
        except
          // Fallback: load original file and resample to current size
          src.LoadFromFile(FSlots[i].FileName);
          // Create scaled copy to match layer size
          scaled := TBitmap.Create;
          try
            scaled.PixelFormat := pf32bit;
            scaled.SetSize(img.Width, img.Height);
            SetStretchBltMode(scaled.Canvas.Handle, HALFTONE);
            StretchBlt(scaled.Canvas.Handle, 0, 0, scaled.Width, scaled.Height,
                       src.Canvas.Handle, 0, 0, src.Width, src.Height, SRCCOPY);
            src.Assign(scaled);
          finally
            scaled.Free;
          end;
        end;

        // Apply Horizontal Mirror and Negative
        MirrorHorizontalBitmap(src);
        NegativeBitmap(src);

        // Clip to ellipse and draw at image layer position
        Rgn := CreateEllipticRgn(cx - r, cy - r, cx + r, cy + r);
        try
          // Set clipping region
          SelectClipRgn(dest.Canvas.Handle, Rgn);
          // Draw at (img.Left, img.Top)
          destRect := Rect(img.Left, img.Top, img.Left + src.Width, img.Top + src.Height);
          SetStretchBltMode(dest.Canvas.Handle, HALFTONE);
          StretchBlt(dest.Canvas.Handle,
                     destRect.Left, destRect.Top, destRect.Width, destRect.Height,
                     src.Canvas.Handle, 0, 0, src.Width, src.Height, SRCCOPY);
        finally
          // Reset clip
          SelectClipRgn(dest.Canvas.Handle, 0);
          DeleteObject(Rgn);
        end;

      finally
        src.Free;
      end;
    end;

    // Save as PNG using VCL
    {$IF CompilerVersion >= 23.0} // XE2+
    var Png: Vcl.Imaging.pngimage.TPngImage;
    {$IFEND}
    {$IF CompilerVersion >= 23.0}
    Png := Vcl.Imaging.pngimage.TPngImage.Create;
    try
      Png.Assign(dest);
      Png.SaveToFile(AFileName);
    finally
      Png.Free;
    end;
    {$ELSE}
    dest.SaveToFile(AFileName); // fallback: BMP
    {$IFEND}

    ShowMessage('Exported: ' + AFileName);
  finally
    dest.Free;
  end;
end;

end.
