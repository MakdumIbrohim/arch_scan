use pdf_writer::{Content, Finish, Name, Pdf, Rect, Ref};
use std::fs::File;
use std::io::{BufWriter, Cursor, Write};
use std::path::Path;

/// Generate multi-page PDF from a list of image file paths
pub fn create_pdf_from_images<P: AsRef<Path>>(
    image_paths: &[P],
    output_path: P,
) -> Result<(), String> {
    if image_paths.is_empty() {
        return Err("No images provided for PDF generation".to_string());
    }

    let mut pdf = Pdf::new();
    let mut page_refs = Vec::new();
    let mut alloc = 1;

    let catalog_ref = Ref::new(alloc);
    alloc += 1;
    let pages_ref = Ref::new(alloc);
    alloc += 1;

    struct PageData {
        page_ref: Ref,
        content_ref: Ref,
        image_ref: Ref,
        width: f32,
        height: f32,
        jpeg_data: Vec<u8>,
        img_w: u32,
        img_h: u32,
    }

    let mut pages_data = Vec::new();

    for img_path in image_paths {
        let img = image::open(img_path).map_err(|e| format!("Failed to open image: {}", e))?;
        let (w, h) = (img.width(), img.height());

        // Encode to JPEG bytes
        let mut jpeg_buf = Cursor::new(Vec::new());
        img.write_to(&mut jpeg_buf, image::ImageFormat::Jpeg)
            .map_err(|e| format!("Failed to encode JPEG: {}", e))?;
        let jpeg_data = jpeg_buf.into_inner();

        // Standard A4 point dimensions: 595.28 x 841.89
        // Scale to fit A4 page
        let a4_w = 595.28f32;
        let a4_h = 841.89f32;
        let aspect = w as f32 / h as f32;

        let (page_w, page_h) = if aspect > (a4_w / a4_h) {
            // Width bounded
            (a4_w, a4_w / aspect)
        } else {
            // Height bounded
            (a4_h * aspect, a4_h)
        };

        let page_ref = Ref::new(alloc);
        alloc += 1;
        let content_ref = Ref::new(alloc);
        alloc += 1;
        let image_ref = Ref::new(alloc);
        alloc += 1;

        page_refs.push(page_ref);
        pages_data.push(PageData {
            page_ref,
            content_ref,
            image_ref,
            width: page_w,
            height: page_h,
            jpeg_data,
            img_w: w,
            img_h: h,
        });
    }

    // Set catalog and page tree
    pdf.catalog(catalog_ref).pages(pages_ref);
    let mut pages = pdf.pages(pages_ref);
    pages.count(page_refs.len() as i32);
    pages.kids(page_refs.iter().copied());
    pages.finish();

    let image_name = Name(b"Im0");

    for p in &pages_data {
        // Page object
        let mut page = pdf.page(p.page_ref);
        page.parent(pages_ref);
        page.media_box(Rect::new(0.0, 0.0, p.width, p.height));
        page.contents(p.content_ref);

        let mut resources = page.resources();
        let mut xobjs = resources.x_objects();
        xobjs.pair(image_name, p.image_ref);
        xobjs.finish();
        resources.finish();
        page.finish();

        // Content stream to draw image full page
        let mut content = Content::new();
        content.save_state();
        content.transform([p.width, 0.0, 0.0, p.height, 0.0, 0.0]);
        content.x_object(image_name);
        content.restore_state();
        pdf.stream(p.content_ref, &content.finish());

        // Image XObject stream
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
