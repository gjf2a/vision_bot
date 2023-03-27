use crate::api::ImageData;
use cv::{
    bitarray::BitArray, feature::akaze::KeyPoint,
    image::imageproc::drawing::BresenhamLinePixelIterMut,
};
use image::{ImageBuffer, Rgba, RgbaImage};
use ordered_float::OrderedFloat;
use std::cmp::{max, min};

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
    generic_yuv_rgba(img, |_, _, rgb| result.push(rgb));
    result
}

/// Translated and adapted from: https://stackoverflow.com/a/57604820/906268
pub fn inner_yuv_rgba(img: &ImageData) -> Vec<u8> {
    let mut result = Vec::new();
    generic_yuv_rgba(img, |_, _, (r, g, b)| {
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
            let uv_index = (img.uv_pixel_stride * (x / 2) + img.uv_row_stride * (y / 2)) as usize;
            let index = (y * img.width + x) as usize;
            let rgb = yuv2rgb(
                img.ys[index] as i64,
                img.us[uv_index] as i64,
                img.vs[uv_index] as i64,
            );
            add(x, y, rgb);
        }
    }
}

fn yuv2rgb(yp: i64, up: i64, vp: i64) -> (u8, u8, u8) {
    (
        clamp_u8(yp + vp * 1436 / 1024 - 179),
        clamp_u8(yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91),
        clamp_u8(yp + up * 1814 / 1024 - 227),
    )
}

fn clamp_u8(value: i64) -> u8 {
    min(max(value, 0), u8::MAX as i64) as u8
}

pub fn correspondences(
    last_features: &Vec<BitArray<64>>,
    features: &Vec<BitArray<64>>,
) -> Vec<(usize, usize)> {
    stable_matching::stable_matching_distance(last_features, features, BitArray::distance)
}

#[derive(Copy, Clone)]
pub struct KeyPointInfo {
    pub point: KeyPoint,
    pub feature: BitArray<64>,
}

pub fn kp_distance(kp1: &KeyPoint, kp2: &KeyPoint) -> OrderedFloat<f32> {
    OrderedFloat(
        ((kp1.point.0 - kp2.point.0).powf(2.0) + (kp1.point.1 - kp2.point.1).powf(2.0)).sqrt(),
    )
}

pub fn kp_distance_f64(kp1: &KeyPoint, kp2: &KeyPoint) -> f64 {
    ((kp1.point.0 as f64 - kp2.point.0 as f64)).powf(2.0) + ((kp1.point.1 as f64 - kp2.point.1 as f64)).powf(2.0)
}

pub fn kp_feature_distance_f64(f1: &BitArray<64>, f2: &BitArray<64>) -> f64 {
    f1.distance(&f2) as f64
}

pub fn kpi_distance(kpi1: &KeyPointInfo, kpi2: &KeyPointInfo, kpi_weight: f32) -> OrderedFloat<f32> {
    OrderedFloat(kpi1.feature.distance(&kpi2.feature) as f32 * kpi_weight) + kp_distance(&kpi1.point, &kpi2.point)
}

/*
// Probably don't need it.
pub fn kp_heading(kp1: &KeyPointInfo, kp2: &KeyPointInfo) -> f32 {
    (kp2.point.point.1 - kp1.point.point.1).atan2(kp2.point.point.0 - kp1.point.point.0)
}
*/

impl KeyPointInfo {
    pub fn point_mean<I: Iterator<Item = Self>>(iter: I) -> (f32, f32) {
        let mut x_sum = 0.0;
        let mut y_sum = 0.0;
        let mut len = 0.0;
        for kpi in iter {
            let (x, y) = kpi.point.point;
            x_sum += x;
            y_sum += y;
            len += 1.0;
        }
        (x_sum / len, y_sum / len)
    }
}

pub struct KeyPointMovements {
    moves: Vec<(KeyPointInfo, KeyPointInfo)>,
}

impl KeyPointMovements {
    pub fn feature_match(
        last_keypoints: &Vec<KeyPoint>,
        last_features: &Vec<BitArray<64>>,
        keypoints: &Vec<KeyPoint>,
        features: &Vec<BitArray<64>>,
    ) -> Self {
        let matches = correspondences(last_features, features);
        Self::from_matches(&matches, last_keypoints, last_features, keypoints, features)
    }

    pub fn keypoint_match(
        last_keypoints: &Vec<KeyPoint>,
        last_features: &Vec<BitArray<64>>,
        keypoints: &Vec<KeyPoint>,
        features: &Vec<BitArray<64>>,
    ) -> Self {
        let matches =
            stable_matching::stable_matching_distance(last_keypoints, keypoints, kp_distance);
        Self::from_matches(&matches, last_keypoints, last_features, keypoints, features)
    }

    fn from_matches(
        matches: &Vec<(usize, usize)>,
        last_keypoints: &Vec<KeyPoint>,
        last_features: &Vec<BitArray<64>>,
        keypoints: &Vec<KeyPoint>,
        features: &Vec<BitArray<64>>,
    ) -> Self {
        Self {
            moves: matches
                .iter()
                .map(|(l_i, i)| {
                    (
                        KeyPointInfo {
                            point: last_keypoints[*l_i],
                            feature: last_features[*l_i],
                        },
                        KeyPointInfo {
                            point: keypoints[*i],
                            feature: features[*i],
                        },
                    )
                })
                .collect(),
        }
    }

    /*
    // Unused. I don't remember what I had in mind for it. Hanging on
    // to it for now... 
    pub fn render_on(&self, img: &mut ImageBuffer<Rgba<u8>, Vec<u8>>, color: [u8; 4]) {
        for (last_kp, kp) in self.moves.iter().copied() {
            let (x1, y1) = last_kp.point.point;
            let (x2, y2) = kp.point.point;
            for p in BresenhamLinePixelIterMut::new(img, (x1, y1), (x2, y2)) {
                *p = Rgba(color);
            }
        }
    }
    */

    pub fn render_mean_on(&self, img: &mut ImageBuffer<Rgba<u8>, Vec<u8>>, color: [u8; 4]) {
        let (start, end) = self.mean();
        for p in BresenhamLinePixelIterMut::new(img, start, end) {
            *p = Rgba(color);
        }
    }

    pub fn mean(&self) -> ((f32, f32), (f32, f32)) {
        let start_mean = KeyPointInfo::point_mean(self.moves.iter().map(|(kpi, _)| *kpi));
        let end_mean = KeyPointInfo::point_mean(self.moves.iter().map(|(_, kpi)| *kpi));
        (start_mean, end_mean)
    }
}
