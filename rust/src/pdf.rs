use pdf_writer::types::TextRenderingMode;
use pdf_writer::{Content, Finish, Name, Pdf, Rect, Ref, Str};
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{BufWriter, Cursor, Write};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PaperSize {
    A4,
    Letter,
    Fit,
}

impl Default for PaperSize {
    fn default() -> Self {
        PaperSize::A4
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PdfQuality {
    High,
    Medium,
    Low,
}

impl Default for PdfQuality {
    fn default() -> Self {
        PdfQuality::High
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PdfConfig {
    #[serde(default)]
    pub paper_size: PaperSize,
    #[serde(default)]
    pub quality: PdfQuality,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrTextItem {
    pub text: String,
    /// Normalized x coordinate (0.0 to 1.0 from left)
    pub x: f32,
    /// Normalized y coordinate (0.0 to 1.0 from bottom of page)
    pub y: f32,
    pub font_size: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageSpec {
    pub image_path: String,
    #[serde(default)]
    pub ocr_items: Vec<OcrTextItem>,
}

/// Generate multi-page PDF from a list of image file paths
pub fn create_pdf_from_images<P: AsRef<Path>>(
    image_paths: &[P],
    output_path: P,
) -> Result<(), String> {
    let specs: Vec<PageSpec> = image_paths
        .iter()
        .map(|p| PageSpec {
            image_path: p.as_ref().to_string_lossy().to_string(),
            ocr_items: Vec::new(),
        })
        .collect();

    create_searchable_pdf(&specs, output_path)
}

/// Generate Searchable Multi-Page PDF with default settings
pub fn create_searchable_pdf<P: AsRef<Path>>(
    pages: &[PageSpec],
    output_path: P,
) -> Result<(), String> {
    create_searchable_pdf_with_config(pages, &PdfConfig::default(), output_path)
}

/// Generate Searchable Multi-Page PDF with custom PaperSize & Quality
pub fn create_searchable_pdf_with_config<P: AsRef<Path>>(
    pages: &[PageSpec],
    config: &PdfConfig,
    output_path: P,
) -> Result<(), String> {
    if pages.is_empty() {
        return Err("No pages provided for PDF generation".to_string());
    }

    let mut pdf = Pdf::new();
    let mut page_refs = Vec::new();
    let mut alloc = 1;

    let catalog_ref = Ref::new(alloc);
    alloc += 1;
    let pages_ref = Ref::new(alloc);
    alloc += 1;
    let font_ref = Ref::new(alloc);
    alloc += 1;

    // Standard Type1 Helvetica font
    let font_name = Name(b"F1");
    pdf.type1_font(font_ref).base_font(Name(b"Helvetica"));

    struct PageRenderData {
        page_ref: Ref,
        content_ref: Ref,
        image_ref: Ref,
        page_w: f32,
        page_h: f32,
        img_draw_w: f32,
        img_draw_h: f32,
        offset_x: f32,
        offset_y: f32,
        jpeg_data: Vec<u8>,
        orig_w: u32,
        orig_h: u32,
        ocr_items: Vec<OcrTextItem>,
    }

    let mut render_pages = Vec::new();
    let jpeg_quality = match config.quality {
        PdfQuality::High => 90,
        PdfQuality::Medium => 70,
        PdfQuality::Low => 50,
    };

    for spec in pages {
        let img = image::open(&spec.image_path)
            .map_err(|e| format!("Failed to open image '{}': {}", spec.image_path, e))?;
        let (w, h) = (img.width(), img.height());

        // Encode to JPEG using selected compression quality
        let rgb = img.to_rgb8();
        let mut jpeg_buf = Cursor::new(Vec::new());
        let mut encoder =
            image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg_buf, jpeg_quality);
        encoder
            .encode(rgb.as_raw(), w, h, image::ExtendedColorType::Rgb8)
            .map_err(|e| format!("Failed to encode JPEG: {}", e))?;
        let jpeg_data = jpeg_buf.into_inner();

        // Calculate layout & paper geometry
        let (page_w, page_h, img_draw_w, img_draw_h, offset_x, offset_y) = match config.paper_size {
            PaperSize::A4 => {
                let pw = 595.28f32;
                let ph = 841.89f32;
                let scale = (pw / w as f32).min(ph / h as f32);
                let dw = w as f32 * scale;
                let dh = h as f32 * scale;
                let ox = (pw - dw) / 2.0;
                let oy = (ph - dh) / 2.0;
                (pw, ph, dw, dh, ox, oy)
            }
            PaperSize::Letter => {
                let pw = 612.0f32;
                let ph = 792.0f32;
                let scale = (pw / w as f32).min(ph / h as f32);
                let dw = w as f32 * scale;
                let dh = h as f32 * scale;
                let ox = (pw - dw) / 2.0;
                let oy = (ph - dh) / 2.0;
                (pw, ph, dw, dh, ox, oy)
            }
            PaperSize::Fit => {
                let pw = 595.28f32;
                let aspect = w as f32 / h as f32;
                let ph = pw / aspect;
                (pw, ph, pw, ph, 0.0, 0.0)
            }
        };

        let page_ref = Ref::new(alloc);
        alloc += 1;
        let content_ref = Ref::new(alloc);
        alloc += 1;
        let image_ref = Ref::new(alloc);
        alloc += 1;

        page_refs.push(page_ref);
        render_pages.push(PageRenderData {
            page_ref,
            content_ref,
            image_ref,
            page_w,
            page_h,
            img_draw_w,
            img_draw_h,
            offset_x,
            offset_y,
            jpeg_data,
            orig_w: w,
            orig_h: h,
            ocr_items: spec.ocr_items.clone(),
        });
    }

    // Catalog & Pages
    pdf.catalog(catalog_ref).pages(pages_ref);
    let mut pages_node = pdf.pages(pages_ref);
    pages_node.count(page_refs.len() as i32);
    pages_node.kids(page_refs.iter().copied());
    pages_node.finish();

    let image_name = Name(b"Im0");

    for p in &render_pages {
        // Page definition
        let mut page = pdf.page(p.page_ref);
        page.parent(pages_ref);
        page.media_box(Rect::new(0.0, 0.0, p.page_w, p.page_h));
        page.contents(p.content_ref);

        let mut resources = page.resources();
        let mut xobjs = resources.x_objects();
        xobjs.pair(image_name, p.image_ref);
        xobjs.finish();

        let mut fonts = resources.fonts();
        fonts.pair(font_name, font_ref);
        fonts.finish();

        resources.finish();
        page.finish();

        // Page content stream
        let mut content = Content::new();

        // 1. Draw page image bitmap at scaled offset position
        content.save_state();
        content.transform([
            p.img_draw_w,
            0.0,
            0.0,
            p.img_draw_h,
            p.offset_x,
            p.offset_y,
        ]);
        content.x_object(image_name);
        content.restore_state();

        // 2. Overlay invisible text layer for search & copy
        if !p.ocr_items.is_empty() {
            content.save_state();
            content.set_text_rendering_mode(TextRenderingMode::Invisible);
            for item in &p.ocr_items {
                let text_x = p.offset_x + (item.x.clamp(0.0, 1.0) * p.img_draw_w);
                let text_y = p.offset_y + (item.y.clamp(0.0, 1.0) * p.img_draw_h);
                let size = if item.font_size > 0.0 {
                    item.font_size
                } else {
                    12.0
                };

                content.begin_text();
                content.set_font(font_name, size);
                content.next_line(text_x, text_y);
                content.show(Str(item.text.as_bytes()));
                content.end_text();
            }
            content.restore_state();
        }

        pdf.stream(p.content_ref, &content.finish());

        // Image XObject
        let mut image_stream = pdf.image_xobject(p.image_ref, &p.jpeg_data);
        image_stream.width(p.orig_w as i32);
        image_stream.height(p.orig_h as i32);
        image_stream.color_space().device_rgb();
        image_stream.bits_per_component(8);
        image_stream.filter(pdf_writer::Filter::DctDecode);
        image_stream.finish();
    }

    let file = File::create(output_path).map_err(|e| format!("Failed to create PDF file: {}", e))?;
    let mut writer = BufWriter::new(file);
    writer
        .write_all(&pdf.finish())
        .map_err(|e| format!("Failed to write PDF: {}", e))?;

    Ok(())
}
