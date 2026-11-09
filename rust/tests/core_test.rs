use arch_scan_core::bridge::*;
use arch_scan_core::detection::detect_document_corners;
use arch_scan_core::enhancement::{apply_filter, FilterType};
use arch_scan_core::pdf::create_pdf_from_images;
use arch_scan_core::perspective::{warp_perspective, Point};
use image::{DynamicImage, ImageBuffer, Rgba};
use std::ffi::CString;

#[test]
fn test_core_version() {
    assert_eq!(arch_scan_version(), 100);
}

#[test]
fn test_perspective_and_enhancement() {
    let w = 200;
    let h = 300;
    let mut img: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::new(w, h);

    // Draw a document-like pattern
    for y in 0..h {
        for x in 0..w {
            if x > 20 && x < 180 && y > 30 && y < 270 {
                img.put_pixel(x, y, Rgba([240, 235, 220, 255])); // paper
            } else {
                img.put_pixel(x, y, Rgba([50, 50, 60, 255])); // background table
            }
        }
    }

    let dyn_img = DynamicImage::ImageRgba8(img);
    let corners = detect_document_corners(&dyn_img);
    assert_eq!(corners.len(), 4);

    // Test warp perspective
    let warped = warp_perspective(&dyn_img, &corners, 160, 240);
    assert!(warped.is_some());
    let warped_img = warped.unwrap();

    // Test filters
    let magic = apply_filter(&warped_img, FilterType::MagicColor);
    assert_eq!(magic.width(), 160);

    let bw = apply_filter(&warped_img, FilterType::BlackAndWhite);
    assert_eq!(bw.width(), 160);

    let gray = apply_filter(&warped_img, FilterType::Grayscale);
    assert_eq!(gray.width(), 160);

    let sharp = apply_filter(&warped_img, FilterType::Sharp);
    assert_eq!(sharp.width(), 160);
}

#[test]
fn test_pdf_creation() {
    let tmp_img = "/tmp/test_arch_scan_page.jpg";
    let tmp_pdf = "/tmp/test_arch_scan_doc.pdf";

    let img: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::new(100, 150);
    let dyn_img = DynamicImage::ImageRgba8(img);
    dyn_img.save(tmp_img).expect("Failed to save test image");

    let paths = vec![tmp_img.to_string()];
    let res = create_pdf_from_images(&paths, tmp_pdf.to_string());
    assert!(res.is_ok());
    assert!(std::path::Path::new(tmp_pdf).exists());

    // Clean up
    let _ = std::fs::remove_file(tmp_img);
    let _ = std::fs::remove_file(tmp_pdf);
}
