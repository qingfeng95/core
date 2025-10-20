# Delphi XE 10.3 + ImageEn：8520x4320 黑底 + 6 个圆形遮罩（可拖拽编辑、翻转与负片导出）

本文档描述如何在 Delphi XE 10.3 环境下，使用 ImageEn 控件实现：
- 初始化 8520x4320 像素黑色画布（作为最终底图）
- 加载 6 张图片，以短边 1890 像素等比缩放
- 每图一个圆形遮罩（直径 1800），遮罩固定在背景上的指定坐标
- 用户可拖动图片层，在遮罩内调整可见区域
- 输出时，对 6 张图分别进行水平翻转与负片处理，合并遮罩与图层后导出为一张 8520x4320 最终图像

注：本文给出的 ImageEn API 以常见版本为参考，不同版本属性/方法名可能略有差异，请以实际安装版本为准。

---

## 1. 需求要点与坐标说明
- 背景/最终输出分辨率：8520 × 4320 像素（黑色）。
- 6 个圆形遮罩：直径 1800，半径 900。
- 图片缩放：以短边为 1890 像素，长边等比缩放。
- 遮罩中心坐标（给定）：
  - 上排： (1926, 945), (4260, 945), (6594, 945)
  - 下排： (1926, 3375), (4260, 3375), (6594, 3375)
- 若需要“与上/下边相切”，严格的圆心 y 应为 900 和 3420；给定的 945/3375 会上下各留约 45 像素边距，两种方式均可。

---

## 2. 实现总览（推荐工作流）
采用 ImageEn 的图层系统：
- FinalImageEnView：一个启用图层的 TImageEnView，底层是黑色背景图像（8520x4320），Locked。
- 遮罩层：6 个固定位置的“圆形遮罩层”（形状/矢量椭圆），设置为“用作裁剪/Layer Mask”。
- 图片层：6 个图片层（每图一个），可拖动，受对应遮罩层裁剪，仅圆内可见。
- 交互：开启 miMoveLayers，仅允许移动图片层；遮罩层锁定不动。
- 导出：复制当前图层到临时视图，对 6 个图片层执行水平翻转与负片处理后 Flatten（合并）输出。

优点：所见即所得、遮罩边缘可抗锯齿、导出逻辑简单。

---

## 3. 备用实现（Alpha 通道裁切 + 导出再裁剪）
若 ImageEn 版本不便直接使用图层遮罩：
- 为图片层 IEBitmap 分配 Alpha 通道，将圆形区域 Alpha=255、外部 Alpha=0。
- 预览时可以叠加一个圆形可视遮罩作为提示；
- 导出时在离屏位图中，按固定圆心设置椭圆 Clip 区域，再将（已翻转、负片处理的）图片绘制进去，完成最终裁切与合成。

该方案兼容性强，但导出时需要自定义合成流程。

---

## 4. 详细步骤

### 4.1 初始化最终画布
- FinalImageEnView.LayersEnabled := True
- FinalImageEnView.IEBitmap.SetSize(8520, 4320, ie32RGB); Fill(clBlack)
- 背景层 Locked := True（不可选中/移动）

### 4.2 创建 6 个圆形遮罩层
- 每个遮罩层：
  - Left = CenterX - 900
  - Top  = CenterY - 900
  - Width = Height = 1800
  - 形状：Ellipse（椭圆），填充白色，边线透明或极细；开启抗锯齿与少量 Feather（1–2 像素）
  - 设为“用作裁剪/Layer Mask”，并 Locked := True
- 坐标可用给定的 6 个点（会上下各留约 45px 边距），或严格相切的 y=900 / y=3420。

### 4.3 加载与缩放 6 张图片
- 读入到 TIEBitmap（或 TImageEnIO），注意 EXIF 方向。
- 计算缩放比例：s = 1890 / Min(w, h)。目标尺寸：(Round(w*s), Round(h*s))。
- 使用高质量插值（Lanczos3/BSpline）Resample。
- 创建图片层（ielkImage），将缩放后 IEBitmap 赋值到图片层。
- 初始定位：使图片中心与对应遮罩圆心重合（Left := CX - ImgW/2，Top := CY - ImgH/2）。
- 建立遮罩关系：将图片层与对应的遮罩层关联为“被其裁剪”。
- 图片层 Moveable := True；遮罩/背景 Locked。

### 4.4 交互拖动与边界约束（可选）
- FinalImageEnView.MouseInteractGeneral 包含 miMoveLayers。
- 为避免圆内露底，可在 OnLayerNotify 里为图片移动设置边界：
  - 判断图片相对于圆心的可覆盖范围，若某方向距离小于半径 900 时禁止继续朝该方向移动。
- 可叠加一个细线圆形作视觉辅助。

### 4.5 输出（离屏导出，不破坏编辑态）
1) 复制当前图层到临时 TImageEnView（或用流保存/加载）
2) 在临时视图中，对 6 个图片层：
   - 水平翻转：IEBitmap.Mirror(ierHorizontal) 或 TImageEnProc.Mirror(ierHorizontal)
   - 负片处理：IEBitmap.Negative 或 TImageEnProc.Negative
3) 如需严格相切，可在副本中将遮罩层 y 调整为 900/3420
4) Flatten（合并所有图层）
5) 保存为 PNG/JPEG/TIFF（黑底，24/32 位均可）

---

## 5. 示例代码骨架（示意，API 以你的 ImageEn 版本为准）

```pascal
procedure TForm1.FormCreate(Sender: TObject);
begin
  FinalImageEnView.LayersEnabled := True;
  FinalImageEnView.IEBitmap.SetSize(8520, 4320, ie32RGB);
  FinalImageEnView.IEBitmap.Fill(clBlack);
  FinalImageEnView.Update;

  // 创建 6 个圆形遮罩层（示例：上排左侧）
  CreateCircleMaskAt(1926, 945);   // 其余依次创建 (4260,945), (6594,945), (1926,3375), ...

  // 开启交互（只移动图层）
  FinalImageEnView.MouseInteractGeneral := FinalImageEnView.MouseInteractGeneral + [miMoveLayers];
end;

procedure TForm1.CreateCircleMaskAt(CX, CY: Integer);
var
  L: TIELayer; // 实际为形状层类型，如 TIEShapeLayer
begin
  L := FinalImageEnView.LayersAdd(ielkShape);
  // 设为椭圆、填充白色、边线透明/极细、抗锯齿/Feather 见你版本 API
  L.Left := CX - 900;
  L.Top := CY - 900;
  L.Width := 1800;
  L.Height := 1800;
  // 标记为用作裁剪/Layer Mask
  // L.IsMask := True; 或 L.UseAsClipMask := True; （视版本）
  L.Locked := True;
end;

procedure TForm1.LoadImageToSlot(const AFileName: string; const CX, CY: Integer);
var
  Bmp: TIEBitmap;
  Img: TIELayer; // 实际为图片层类型，如 TIEImageLayer
  s: Double;
  w, h: Integer;
begin
  Bmp := TIEBitmap.Create;
  try
    Bmp.Read(AFileName);
    w := Bmp.Width; h := Bmp.Height;
    s := 1890 / Min(w, h);
    Bmp.Resample(Round(w*s), Round(h*s), rfLanczos3);

    Img := FinalImageEnView.LayersAdd(ielkImage);
    Img.IEBitmap.Assign(Bmp);
    Img.Left := CX - Img.Width div 2;
    Img.Top := CY - Img.Height div 2;
    Img.Locked := False; // 可拖动
    // Img.SetMask(MaskLayerAt(CX,CY)); 或 Img.Mask := 对应遮罩层
  finally
    Bmp.Free;
  end;
end;

procedure TForm1.BtnExportClick(Sender: TObject);
var
  Tmp: TImageEnView;
  i: Integer;
  L: TIELayer; // 图片层
begin
  Tmp := TImageEnView.Create(nil);
  try
    Tmp.LayersEnabled := True;
    // 复制所有图层（可用流保存/加载或 ImageEn 的 Assign/CopyAllLayers 方法）

    // 对 6 个图片层进行水平翻转与负片
    for i := 0 to 5 do
    begin
      L := Tmp.Layers[ImageLayerIndex[i]];
      L.IEBitmap.Mirror(ierHorizontal); // 或 TImageEnProc.Mirror(ierHorizontal)
      L.IEBitmap.Negative;              // 或 TImageEnProc.Negative
    end;

    // 若需要严格相切，可调整遮罩层位置（y=900 / y=3420）

    // 合并
    Tmp.LayersFlatten;

    // 保存
    Tmp.IO.SaveToFile('output.png');
  finally
    Tmp.Free;
  end;
end;
```

> 注意：上面代码使用的层类型与 API 需根据你安装的 ImageEn 版本对照修改（如：形状层/图片层的具体类名、Mask/Clip 的设置方式）。

---

## 6. 质量与性能建议
- 8520x4320 @ 32 位约 140MB，注意释放临时位图、使用 BeginUpdate/EndUpdate 降低重绘开销。
- 缩放使用高质量插值（Lanczos3/BSpline），遮罩边缘加 1–2 像素 Feather 提升观感。
- 若版本支持 GPU 加速，谨慎启用，优先保证稳定性与兼容性。

---

## 7. 小结
- 使用“固定圆形遮罩层 + 可拖动图片层”的图层工作流最直观稳定，导出前在离屏副本上对 6 图进行“水平翻转 + 负片”后 Flatten 合并即可。
- 若版本对 Layer Mask 支持受限，可采用“Alpha 通道 + 导出再裁剪合成”的备用方案，预览与导出分别处理，也能得到一致的正确结果。
