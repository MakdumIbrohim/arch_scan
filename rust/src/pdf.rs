use pdf_writer::types::TextRenderingMode;
use pdf_writer::{Content, Finish, Name, Pdf, Rect, Ref, Str};
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{BufWriter, Cursor, Write};
use std::path::Path;

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

/// Generate Searchable Multi-Page PDF with optional invisible OCR text layer
pub fn create_searchable_pdf<P: AsRef<Path>>(
    pages: &[PageSpec],
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
        width: f32,
        height: f32,
        jpeg_data: Vec<u8>,
        img_w: u32,
        img_h: u32,
        ocr_items: Vec<OcrTextItem>,
    }

    let mut render_pages = Vec::new();

    for spec in pages {
        let img = image::open(&spec.image_path)
            .map_err(|e| format!("Failed to open image '{}': {}", spec.image_path, e))?;
        let (w, h) = (img.width(), img.height());

        let mut jpeg_buf = Cursor::new(Vec::new());
        img.write_to(&mut jpeg_buf, image::ImageFormat::Jpeg)
            .map_err(|e| format!("Failed to encode JPEG: {}", e))?;
        let jpeg_data = jpeg_buf.into_inner();

        let a4_w = 595.28f32;
        let a4_h = 841.89f32;
        let aspect = w as f32 / h as f32;

        let (page_w, page_h) = if aspect > (a4_w / a4_h) {
            (a4_w, a4_w / aspect)
        } else {
            (a4_h * aspect, a4_h)
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
            width: page_w,
            height: page_h,
            jpeg_data,
            img_w: w,
            img_h: h,
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
        page.media_box(Rect::new(0.0, 0.0, p.width, p.height));
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

        // 1. Draw page image bitmap
        content.save_state();
        content.transform([p.width, 0.0, 0.0, p.height, 0.0, 0.0]);
        content.x_object(image_name);
        content.restore_state();

        // 2. Overlay invisible text layer for search & copy
        if !p.ocr_items.is_empty() {
            content.save_state();
            content.set_text_rendering_mode(TextRenderingMode::Invisible);
            for item in &p.ocr_items {
                let text_x = item.x.clamp(0.0, 1.0) * p.width;
                let text_y = item.y.clamp(0.0, 1.0) * p.height;
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
        image_stream.width(p.img_w as i32);
        image_stream.height(p.img_h as i32);
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
