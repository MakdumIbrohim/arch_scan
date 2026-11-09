use image::{DynamicImage, GenericImageView, ImageBuffer, Rgba};

#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl Point {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}

/// Compute 3x3 homography matrix mapping destination coordinates [0, W]x[0, H]
/// back to source quadrilateral coordinates (top_left, top_right, bottom_right, bottom_left).
fn solve_homography_inv(src: &[Point; 4], dst_w: f32, dst_h: f32) -> Option<[f32; 9]> {
    // Destination 4 corners:
    // 0: (0, 0), 1: (dst_w, 0), 2: (dst_w, dst_h), 3: (0, dst_h)
    let dst = [
        Point::new(0.0, 0.0),
        Point::new(dst_w, 0.0),
        Point::new(dst_w, dst_h),
        Point::new(0.0, dst_h),
    ];

    // System A * h = b for mapping dst -> src
    let mut a = [[0.0f32; 8]; 8];
    let mut b = [0.0f32; 8];

    for i in 0..4 {
        let u = dst[i].x;
        let v = dst[i].y;
        let x = src[i].x;
        let y = src[i].y;

        let row1 = i * 2;
        let row2 = row1 + 1;

        a[row1] = [u, v, 1.0, 0.0, 0.0, 0.0, -u * x, -v * x];
        b[row1] = x;

        a[row2] = [0.0, 0.0, 0.0, u, v, 1.0, -u * y, -v * y];
        b[row2] = y;
    }

    // Solve via Gaussian elimination with partial pivoting
    for i in 0..8 {
        let mut max_row = i;
        let mut max_val = a[i][i].abs();
        for r in (i + 1)..8 {
            if a[r][i].abs() > max_val {
                max_val = a[r][i].abs();
                max_row = r;
            }
        }
        if max_val < 1e-9 {
            return None;
        }
        if max_row != i {
            a.swap(i, max_row);
            b.swap(i, max_row);
        }

        let pivot = a[i][i];
        for c in i..8 {
            a[i][c] /= pivot;
        }
        b[i] /= pivot;

        for r in 0..8 {
            if r != i {
                let factor = a[r][i];
                if factor.abs() > 1e-9 {
                    for c in i..8 {
                        a[r][c] -= factor * a[i][c];
                    }
                    b[r] -= factor * b[i];
                }
            }
        }
    }

    Some([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], 1.0])
}

/// Bilinear sampling of pixel at (x, y)
fn sample_bilinear(img: &DynamicImage, x: f32, y: f32) -> Rgba<u8> {
    let (w, h) = img.dimensions();
    let x_clamped = x.clamp(0.0, (w - 1) as f32);
    let y_clamped = y.clamp(0.0, (h - 1) as f32);

    let x0 = x_clamped.floor() as u32;
    let y0 = y_clamped.floor() as u32;
    let x1 = (x0 + 1).min(w - 1);
    let y1 = (y0 + 1).min(h - 1);

    let fx = x_clamped - x0 as f32;
    let fy = y_clamped - y0 as f32;

    let p00 = img.get_pixel(x0, y0);
    let p10 = img.get_pixel(x1, y0);
    let p01 = img.get_pixel(x0, y1);
    let p11 = img.get_pixel(x1, y1);

    let mut out = [0u8; 4];
    for c in 0..4 {
        let top = (1.0 - fx) * p00[c] as f32 + fx * p10[c] as f32;
        let bottom = (1.0 - fx) * p01[c] as f32 + fx * p11[c] as f32;
        out[c] = ((1.0 - fy) * top + fy * bottom).round().clamp(0.0, 255.0) as u8;
    }
    Rgba(out)
}

/// Warp 4-point quadrilateral to rectangular image
pub fn warp_perspective(
    img: &DynamicImage,
    corners: &[Point; 4],
    target_width: u32,
    target_height: u32,
) -> Option<DynamicImage> {
    let h = solve_homography_inv(corners, target_width as f32, target_height as f32)?;

    let mut output: ImageBuffer<Rgba<u8>, Vec<u8>> =
        ImageBuffer::new(target_width, target_height);

    for v in 0..target_height {
        let vf = v as f32;
        for u in 0..target_width {
            let uf = u as f32;
            let z = h[6] * uf + h[7] * vf + h[8];
            if z.abs() < 1e-9 {
                continue;
            }
            let src_x = (h[0] * uf + h[1] * vf + h[2]) / z;
            let src_y = (h[3] * uf + h[4] * vf + h[5]) / z;

            let pixel = sample_bilinear(img, src_x, src_y);
            output.put_pixel(u, v, pixel);
        }
    }

    Some(DynamicImage::ImageRgba8(output))
}
