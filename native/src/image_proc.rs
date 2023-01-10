use crate::api::ImageData;
use std::cmp::{max, min};
use image::{RgbaImage, Rgba};

pub type U8ColorTriple = (u8, u8, u8);

pub fn convert(img: &ImageData) -> RgbaImage {
    let mut result = RgbaImage::new(img.width as u32, img.height as u32);
    generic_yuv_rgba(&img, |x, y, (r, g, b)| {
        result.put_pixel(x as u32, y as u32, Rgba([r, g, b, 100]));
    });
    result
}

pub fn simple_yuv_rgb(img: &ImageData) -> Vec<U8ColorTriple> {
    let mut result = vec![];
    generic_yuv_rgba(img, |_,_,rgb| { result.push(rgb)});
    result
}

/// Translated and adapted from: https://stackoverflow.com/a/57604820/906268
pub fn inner_yuv_rgba(img: &ImageData) -> Vec<u8> {
    let mut result = Vec::new();
    generic_yuv_rgba(img, |_,_,(r, g, b)| {
        result.push(r);
        result.push(g);
        result.push(b);
        result.push(u8::MAX);
    });
    result
}

pub fn generic_yuv_rgba<F: FnMut(i64, i64, (u8, u8, u8))>(img: &ImageData, mut add: F) {
    for y in 0..img.height {
        for x in 0..img.width {
            let uv_index = (img.uv_pixel_stride * (x/2) + img.uv_row_stride * (y/2)) as usize;
            let index = (y * img.width + x) as usize;
            let rgb = yuv2rgb(img.ys[index] as i64, img.us[uv_index] as i64, img.vs[uv_index] as i64);
            add(x, y, rgb);
        }
    }
}

fn yuv2rgb(yp: i64, up: i64, vp: i64) -> (u8, u8, u8) {
    (clamp_u8(yp + vp * 1436 / 1024 - 179), 
     clamp_u8(yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91), 
     clamp_u8(yp + up * 1814 / 1024 - 227))
}

fn clamp_u8(value: i64) -> u8 {
    min(max(value, 0), u8::MAX as i64) as u8
}