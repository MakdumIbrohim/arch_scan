use image::{DynamicImage, GenericImageView, ImageBuffer, Rgba};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterType {
    Original = 0,
    MagicColor = 1,
    BlackAndWhite = 2,
    Grayscale = 3,
    Sharp = 4,
    Whiteboard = 5,
}

impl From<i32> for FilterType {
    fn from(val: i32) -> Self {
        match val {
            1 => FilterType::MagicColor,
            2 => FilterType::BlackAndWhite,
            3 => FilterType::Grayscale,
            4 => FilterType::Sharp,
            5 => FilterType::Whiteboard,
            _ => FilterType::Original,
        }
    }
}

pub fn apply_filter(img: &DynamicImage, filter: FilterType) -> DynamicImage {
    match filter {
        FilterType::Original => img.clone(),
        FilterType::MagicColor => apply_magic_color(img),
        FilterType::BlackAndWhite => apply_black_and_white(img),
        FilterType::Grayscale => apply_grayscale(img),
        FilterType::Sharp => apply_sharp(img),
        FilterType::Whiteboard => apply_whiteboard(img),
    }
}

pub fn apply_rotation(img: &DynamicImage, degrees: i32) -> DynamicImage {
    match ((degrees % 360) + 360) % 360 {
        90 => img.rotate90(),
        180 => img.rotate180(),
        270 => img.rotate270(),
        _ => img.clone(),
    }
}

/// Magic Color filter: Local contrast enhancement + white background stretching + unsharp masking
fn apply_magic_color(img: &DynamicImage) -> DynamicImage {
    let (w, h) = img.dimensions();
    let mut out: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::new(w, h);

    // Find 98th percentile brightness to normalize background to paper white
    let mut luma_hist = [0u32; 256];
    for y in 0..h {
        for x in 0..w {
            let p = img.get_pixel(x, y);
            let luma = (0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32) as usize;
            luma_hist[luma.min(255)] += 1;
        }
    }

    let total_pixels = (w * h) as f32;
    let target_count = (total_pixels * 0.96) as u32;
    let mut acc = 0u32;
    let mut white_point = 240.0f32;
    for (i, &count) in luma_hist.iter().enumerate() {
        acc += count;
        if acc >= target_count {
            white_point = (i as f32).max(180.0);
            break;
        }
    }

    let scale = 255.0 / white_point;

    for y in 0..h {
        for x in 0..w {
            let p = img.get_pixel(x, y);

            // Stretch colors towards normalized white point
            let mut r = (p[0] as f32 * scale).min(255.0);
            let mut g = (p[1] as f32 * scale).min(255.0);
            let mut b = (p[2] as f32 * scale).min(255.0);

            // Contrast curve: push dark ink darker, light paper lighter
            r = apply_contrast_curve(r);
            g = apply_contrast_curve(g);
            b = apply_contrast_curve(b);

            out.put_pixel(x, y, Rgba([r as u8, g as u8, b as u8, p[3]]));
        }
    }

    // Apply mild unsharp sharpening
    apply_sharp(&DynamicImage::ImageRgba8(out))
}

fn apply_contrast_curve(val: f32) -> f32 {
    let norm = val / 255.0;
    // S-curve centered at 0.5
    let enhanced = if norm < 0.5 {
        2.0 * norm * norm
    } else {
        1.0 - 2.0 * (1.0 - norm) * (1.0 - norm)
    };
    (enhanced * 255.0).clamp(0.0, 255.0)
}

/// Black & White: Adaptive local thresholding
fn apply_black_and_white(img: &DynamicImage) -> DynamicImage {
    let (w, h) = img.dimensions();
    let luma_img = img.to_luma8();
    let mut out: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::new(w, h);

    // Compute integral image for fast local mean computation
    let mut integral = vec![0u64; ((w + 1) * (h + 1)) as usize];
    for y in 0..h {
        let mut row_sum = 0u64;
        for x in 0..w {
            let val = luma_img.get_pixel(x, y)[0] as u64;
            row_sum += val;
            let idx = ((y + 1) * (w + 1) + (x + 1)) as usize;
            let top_idx = (y * (w + 1) + (x + 1)) as usize;
            integral[idx] = integral[top_idx] + row_sum;
        }
    }

    let win_size = (w.min(h) / 20).max(7) as i32;
    let c = 8i64; // threshold bias

    for y in 0..h {
        let y_i = y as i32;
        let y1 = (y_i - win_size).max(0) as u32;
        let y2 = (y_i + win_size).min(h as i32 - 1) as u32;

        for x in 0..w {
            let x_i = x as i32;
            let x1 = (x_i - win_size).max(0) as u32;
            let x2 = (x_i + win_size).min(w as i32 - 1) as u32;

            let area = ((x2 - x1 + 1) * (y2 - y1 + 1)) as u64;

            let idx_br = ((y2 + 1) * (w + 1) + (x2 + 1)) as usize;
            let idx_tr = (y1 * (w + 1) + (x2 + 1)) as usize;
            let idx_bl = ((y2 + 1) * (w + 1) + x1) as usize;
            let idx_tl = (y1 * (w + 1) + x1) as usize;

            let sum = integral[idx_br] + integral[idx_tl] - integral[idx_tr] - integral[idx_bl];
            let mean = (sum / area) as i64;

            let current_val = luma_img.get_pixel(x, y)[0] as i64;
            let binary_val = if current_val < (mean - c) { 0u8 } else { 255u8 };

            out.put_pixel(x, y, Rgba([binary_val, binary_val, binary_val, 255]));
        }
    }

    DynamicImage::ImageRgba8(out)
}

/// Grayscale with contrast normalization
fn apply_grayscale(img: &DynamicImage) -> DynamicImage {
    let (w, h) = img.dimensions();
    let mut out: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::new(w, h);

    for y in 0..h {
        for x in 0..w {
            let p = img.get_pixel(x, y);
            let luma = (0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32)
                .round()
                .clamp(0.0, 255.0) as u8;
            out.put_pixel(x, y, Rgba([luma, luma, luma, 255]));
        }
    }

    DynamicImage::ImageRgba8(out)
}

/// 3x3 Sharpening kernel
fn apply_sharp(img: &DynamicImage) -> DynamicImage {
    let (w, h) = img.dimensions();
    let mut out: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::new(w, h);

    for y in 0..h {
        for x in 0..w {
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 {
                out.put_pixel(x, y, img.get_pixel(x, y));
                continue;
            }

            let center = img.get_pixel(x, y);
            let top = img.get_pixel(x, y - 1);
            let bottom = img.get_pixel(x, y + 1);
            let left = img.get_pixel(x - 1, y);
            let right = img.get_pixel(x + 1, y);

            let mut out_p = [0u8; 4];
            for c in 0..3 {
                let v = 5.0 * center[c] as f32
                    - top[c] as f32
                    - bottom[c] as f32
                    - left[c] as f32
                    - right[c] as f32;
                out_p[c] = v.round().clamp(0.0, 255.0) as u8;
            }
            out_p[3] = center[3];
            out.put_pixel(x, y, Rgba(out_p));
        }
    }

    DynamicImage::ImageRgba8(out)
}

/// Stitch 2-sided ID Card (Front and Back) onto a single vertical A4 document sheet
pub fn stitch_id_card(front: &DynamicImage, back: &DynamicImage) -> DynamicImage {
    let a4_w = 1200u32;
    let a4_h = 1700u32;
    let mut canvas: ImageBuffer<Rgba<u8>, Vec<u8>> =
        ImageBuffer::from_pixel(a4_w, a4_h, Rgba([255, 255, 255, 255]));

    let target_card_w = 900u32;
    let front_aspect = front.width() as f32 / front.height() as f32;
    let target_card_h1 = (target_card_w as f32 / front_aspect).round() as u32;

    let front_resized = front.resize_exact(
        target_card_w,
        target_card_h1,
        image::imageops::FilterType::Lanczos3,
    );

    let back_aspect = back.width() as f32 / back.height() as f32;
    let target_card_h2 = (target_card_w as f32 / back_aspect).round() as u32;
    let back_resized = back.resize_exact(
        target_card_w,
        target_card_h2,
        image::imageops::FilterType::Lanczos3,
    );

    // Place Front in top half
    let ox1 = (a4_w - target_card_w) / 2;
    let oy1 = (a4_h / 2 - target_card_h1) / 2;
    image::imageops::overlay(&mut canvas, &front_resized, ox1 as i64, oy1 as i64);

    // Place Back in bottom half
    let ox2 = (a4_w - target_card_w) / 2;
    let oy2 = a4_h / 2 + (a4_h / 2 - target_card_h2) / 2;
    image::imageops::overlay(&mut canvas, &back_resized, ox2 as i64, oy2 as i64);

    DynamicImage::ImageRgba8(canvas)
}

/// Stitch arbitrary number of page images vertically into one continuous long image (CamScanner Long Picture Stitch)
pub fn stitch_long_image(images: &[DynamicImage]) -> Result<DynamicImage, String> {
    if images.is_empty() {
        return Err("No images to stitch".to_string());
    }

    let target_w = 1080u32;
    let mut total_h = 0u32;
    let gap = 16u32;

    let mut resized_images = Vec::new();
    for img in images {
        let aspect = img.width() as f32 / img.height() as f32;
        let h = (target_w as f32 / aspect).round() as u32;
        let r = img.resize_exact(target_w, h, image::imageops::FilterType::Lanczos3);
        total_h += h;
        resized_images.push(r);
    }

    if images.len() > 1 {
        total_h += (images.len() as u32 - 1) * gap;
    }

    let mut canvas: ImageBuffer<Rgba<u8>, Vec<u8>> =
        ImageBuffer::from_pixel(target_w, total_h, Rgba([245, 245, 245, 255]));

    let mut current_y = 0u32;
    for (i, img) in resized_images.iter().enumerate() {
        image::imageops::overlay(&mut canvas, img, 0, current_y as i64);
        current_y += img.height();
        if i + 1 < resized_images.len() {
            current_y += gap;
        }
    }

    Ok(DynamicImage::ImageRgba8(canvas))
}

/// Whiteboard filter: High-contrast whitening with vibrant marker preservation
fn apply_whiteboard(img: &DynamicImage) -> DynamicImage {
    let (w, h) = img.dimensions();
    let rgb = img.to_rgb8();
    let mut out = ImageBuffer::new(w, h);

    for (x, y, p) in rgb.enumerate_pixels() {
        let r = p[0] as f32;
        let g = p[1] as f32;
        let b = p[2] as f32;
        let lum = 0.299 * r + 0.587 * g + 0.114 * b;

        if lum > 155.0 {
            let t = (lum - 155.0) / 100.0;
            let factor = 1.0 + t * 0.5;
            let nr = ((r * factor).min(255.0)) as u8;
            let ng = ((g * factor).min(255.0)) as u8;
            let nb = ((b * factor).min(255.0)) as u8;
            out.put_pixel(x, y, Rgba([nr, ng, nb, 255]));
        } else {
            let boost = 1.2;
            let nr = ((r * boost).clamp(0.0, 255.0)) as u8;
            let ng = ((g * boost).clamp(0.0, 255.0)) as u8;
            let nb = ((b * boost).clamp(0.0, 255.0)) as u8;
            out.put_pixel(x, y, Rgba([nr, ng, nb, 255]));
        }
    }
    DynamicImage::ImageRgba8(out)
}

/// Composite a transparent overlay (such as a signature or stamp) onto a base image
pub fn composite_overlay(
    base: &DynamicImage,
    overlay: &DynamicImage,
    norm_x: f32,
    norm_y: f32,
    scale: f32,
) -> DynamicImage {
    let mut base_rgba = base.to_rgba8();
    let base_w = base.width() as f32;
    let base_h = base.height() as f32;

    let target_w = ((base_w * 0.35) * scale.clamp(0.1, 3.0)).round() as u32;
    let aspect = overlay.height() as f32 / overlay.width().max(1) as f32;
    let target_h = (target_w as f32 * aspect).round() as u32;

    let overlay_resized = overlay.resize_exact(
        target_w.max(1),
        target_h.max(1),
        image::imageops::FilterType::Lanczos3,
    );

    let px = (norm_x * base_w).round() as i64;
    let py = (norm_y * base_h).round() as i64;

    image::imageops::overlay(&mut base_rgba, &overlay_resized, px, py);
    DynamicImage::ImageRgba8(base_rgba)
}
