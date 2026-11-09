use crate::perspective::Point;
use image::{imageops, DynamicImage, GenericImageView};

/// Detect 4 document corners in clockwise order: [Top-Left, Top-Right, Bottom-Right, Bottom-Left].
/// Returns normalized coordinates (0.0 to 1.0 relative to image width and height).
pub fn detect_document_corners(img: &DynamicImage) -> [Point; 4] {
    let (orig_w, orig_h) = img.dimensions();

    // Downscale for fast edge detection
    let max_dim = 500u32;
    let scale = if orig_w.max(orig_h) > max_dim {
        max_dim as f32 / orig_w.max(orig_h) as f32
    } else {
        1.0
    };

    let small_w = ((orig_w as f32 * scale).round() as u32).max(50);
    let small_h = ((orig_h as f32 * scale).round() as u32).max(50);

    let small = img.resize_exact(small_w, small_h, imageops::FilterType::Nearest);
    let luma = small.to_luma8();

    // Simple Sobel gradient magnitude
    let mut edge_points = Vec::new();
    let threshold = 55u32;

    for y in 1..(small_h - 1) {
        for x in 1..(small_w - 1) {
            let gx = (luma.get_pixel(x + 1, y - 1)[0] as i32
                + 2 * luma.get_pixel(x + 1, y)[0] as i32
                + luma.get_pixel(x + 1, y + 1)[0] as i32)
                - (luma.get_pixel(x - 1, y - 1)[0] as i32
                    + 2 * luma.get_pixel(x - 1, y)[0] as i32
                    + luma.get_pixel(x - 1, y + 1)[0] as i32);

            let gy = (luma.get_pixel(x - 1, y + 1)[0] as i32
                + 2 * luma.get_pixel(x, y + 1)[0] as i32
                + luma.get_pixel(x + 1, y + 1)[0] as i32)
                - (luma.get_pixel(x - 1, y - 1)[0] as i32
                    + 2 * luma.get_pixel(x, y - 1)[0] as i32
                    + luma.get_pixel(x + 1, y - 1)[0] as i32);

            let mag = (gx.abs() + gy.abs()) as u32;
            if mag > threshold {
                edge_points.push((x as f32 / small_w as f32, y as f32 / small_h as f32));
            }
        }
    }

    // If too few edges, return safe 5% inset rectangle
    if edge_points.len() < 50 {
        return [
            Point::new(0.05, 0.05),
            Point::new(0.95, 0.05),
            Point::new(0.95, 0.95),
            Point::new(0.05, 0.95),
        ];
    }

    // Find extreme corners:
    // Top-Left: min (x + y)
    // Top-Right: max (x - y)
    // Bottom-Right: max (x + y)
    // Bottom-Left: min (x - y)
    let mut min_sum = (f32::MAX, (0.05, 0.05));
    let mut max_diff = (f32::MIN, (0.95, 0.05));
    let mut max_sum = (f32::MIN, (0.95, 0.95));
    let mut min_diff = (f32::MAX, (0.05, 0.95));

    for &(x, y) in &edge_points {
        let sum = x + y;
        let diff = x - y;

        if sum < min_sum.0 {
            min_sum = (sum, (x, y));
        }
        if diff > max_diff.0 {
            max_diff = (diff, (x, y));
        }
        if sum > max_sum.0 {
            max_sum = (sum, (x, y));
        }
        if diff < min_diff.0 {
            min_diff = (diff, (x, y));
        }
    }

    // Clamp coordinates safely
    let tl = Point::new(min_sum.1 .0.clamp(0.0, 0.4), min_sum.1 .1.clamp(0.0, 0.4));
    let tr = Point::new(max_diff.1 .0.clamp(0.6, 1.0), max_diff.1 .1.clamp(0.0, 0.4));
    let br = Point::new(max_sum.1 .0.clamp(0.6, 1.0), max_sum.1 .1.clamp(0.6, 1.0));
    let bl = Point::new(min_diff.1 .0.clamp(0.0, 0.4), min_diff.1 .1.clamp(0.6, 1.0));

    [tl, tr, br, bl]
}
