use crate::detection::detect_document_corners;
use crate::enhancement::{apply_filter, apply_rotation, FilterType};
use crate::pdf::{
    create_pdf_from_images, create_searchable_pdf, create_searchable_pdf_with_config, PageSpec,
    PdfConfig,
};
use crate::perspective::{warp_perspective, Point};
use image::GenericImageView;
use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn arch_scan_version() -> i32 {
    100
}

/// Detect 4 document corners in an image.
/// `out_points` must point to an array of 8 floats (4 * (x, y)).
/// Returns 0 on success, -1 on invalid path, -2 on load error.
#[no_mangle]
pub extern "C" fn arch_scan_detect_corners(
    image_path: *const c_char,
    out_points: *mut f32,
) -> i32 {
    if image_path.is_null() || out_points.is_null() {
        return -1;
    }

    let c_str = unsafe { CStr::from_ptr(image_path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let img = match image::open(path_str) {
        Ok(i) => i,
        Err(_) => return -2,
    };

    let corners = detect_document_corners(&img);
    unsafe {
        *out_points.add(0) = corners[0].x;
        *out_points.add(1) = corners[0].y;
        *out_points.add(2) = corners[1].x;
        *out_points.add(3) = corners[1].y;
        *out_points.add(4) = corners[2].x;
        *out_points.add(5) = corners[2].y;
        *out_points.add(6) = corners[3].x;
        *out_points.add(7) = corners[3].y;
    }

    0
}

/// Process a single scanned page: perspective crop + rotation + enhancement filter.
/// `points` points to 8 normalized floats [0.0..1.0]: [tl_x, tl_y, tr_x, tr_y, br_x, br_y, bl_x, bl_y].
/// Returns 0 on success, negative error code otherwise.
#[no_mangle]
pub extern "C" fn arch_scan_process_page(
    input_path: *const c_char,
    output_path: *const c_char,
    points: *const f32,
    filter_id: i32,
    rotation_deg: i32,
) -> i32 {
    if input_path.is_null() || output_path.is_null() || points.is_null() {
        return -1;
    }

    let in_str = match unsafe { CStr::from_ptr(input_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let out_str = match unsafe { CStr::from_ptr(output_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let img = match image::open(in_str) {
        Ok(i) => i,
        Err(_) => return -2,
    };

    let (w, h) = img.dimensions();
    let wf = w as f32;
    let hf = h as f32;

    // Denormalize points to image pixel coordinates
    let corners = unsafe {
        [
            Point::new(*points.add(0) * wf, *points.add(1) * hf),
            Point::new(*points.add(2) * wf, *points.add(3) * hf),
            Point::new(*points.add(4) * wf, *points.add(5) * hf),
            Point::new(*points.add(6) * wf, *points.add(7) * hf),
        ]
    };

    // Calculate target width and height based on top/bottom and left/right distances
    let top_w = ((corners[1].x - corners[0].x).powi(2) + (corners[1].y - corners[0].y).powi(2)).sqrt();
    let bot_w = ((corners[2].x - corners[3].x).powi(2) + (corners[2].y - corners[3].y).powi(2)).sqrt();
    let left_h = ((corners[3].x - corners[0].x).powi(2) + (corners[3].y - corners[0].y).powi(2)).sqrt();
    let right_h = ((corners[2].x - corners[1].x).powi(2) + (corners[2].y - corners[1].y).powi(2)).sqrt();

    let target_w = (top_w.max(bot_w).round() as u32).max(100);
    let target_h = (left_h.max(right_h).round() as u32).max(100);

    // 1. Warp perspective
    let warped = match warp_perspective(&img, &corners, target_w, target_h) {
        Some(w) => w,
        None => return -3,
    };

    // 2. Rotate if needed
    let rotated = apply_rotation(&warped, rotation_deg);

    // 3. Apply enhancement filter
    let enhanced = apply_filter(&rotated, FilterType::from(filter_id));

    // 4. Save to output path
    if enhanced.save(out_str).is_err() {
        return -4;
    }

    0
}

/// Generate PDF from a JSON array of image file paths: `["/path/1.jpg", "/path/2.jpg"]`.
/// Returns 0 on success, negative error code otherwise.
#[no_mangle]
pub extern "C" fn arch_scan_generate_pdf(
    images_json: *const c_char,
    output_pdf_path: *const c_char,
) -> i32 {
    if images_json.is_null() || output_pdf_path.is_null() {
        return -1;
    }

    let json_str = match unsafe { CStr::from_ptr(images_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let out_str = match unsafe { CStr::from_ptr(output_pdf_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let paths: Vec<String> = match serde_json::from_str(json_str) {
        Ok(p) => p,
        Err(_) => return -2,
    };

    match create_pdf_from_images(&paths, out_str.to_string()) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

/// Generate Searchable PDF with OCR metadata:
/// `pages_json` = `[{"image_path": "...", "ocr_items": [{"text": "...", "x": 0.1, "y": 0.8, "font_size": 12.0}]}]`
#[no_mangle]
pub extern "C" fn arch_scan_generate_searchable_pdf(
    pages_json: *const c_char,
    output_pdf_path: *const c_char,
) -> i32 {
    if pages_json.is_null() || output_pdf_path.is_null() {
        return -1;
    }

    let json_str = match unsafe { CStr::from_ptr(pages_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let out_str = match unsafe { CStr::from_ptr(output_pdf_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let specs: Vec<PageSpec> = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(_) => return -2,
    };

    match create_searchable_pdf(&specs, out_str.to_string()) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

/// Generate Searchable PDF with custom configuration (Paper size & Compression quality):
/// `config_json` = `{"paper_size": "A4", "quality": "High"}`
#[no_mangle]
pub extern "C" fn arch_scan_generate_pdf_configured(
    pages_json: *const c_char,
    config_json: *const c_char,
    output_pdf_path: *const c_char,
) -> i32 {
    if pages_json.is_null() || output_pdf_path.is_null() {
        return -1;
    }

    let pages_str = match unsafe { CStr::from_ptr(pages_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let out_str = match unsafe { CStr::from_ptr(output_pdf_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let specs: Vec<PageSpec> = match serde_json::from_str(pages_str) {
        Ok(s) => s,
        Err(_) => return -2,
    };

    let config: PdfConfig = if !config_json.is_null() {
        if let Ok(c_str) = unsafe { CStr::from_ptr(config_json) }.to_str() {
            serde_json::from_str(c_str).unwrap_or_default()
        } else {
            PdfConfig::default()
        }
    } else {
        PdfConfig::default()
    };

    match create_searchable_pdf_with_config(&specs, &config, out_str.to_string()) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}
