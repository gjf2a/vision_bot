use cv::bitarray::BitArray;
use cv::feature::akaze::KeyPoint;
use cv::{feature::akaze::Akaze, image::image::DynamicImage};
use flutter_rust_bridge::support::lazy_static;
use flutter_rust_bridge::ZeroCopyBuffer;
use image::{ImageBuffer, Rgba, RgbaImage, Pixel};
use kmeans::Kmeans;
use knn::Knn;
pub use particle_filter::sonar3bot::{MotorData, RobotSensorPosition, BOT};
use supervised_learning::Classifier;
use std::cmp::min;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::{
    collections::BTreeSet,
    sync::atomic::{AtomicBool, AtomicU64, Ordering},
};

use crate::image_proc::{
    convert, inner_yuv_rgba, simple_yuv_rgb, KeyPointMovements, U8ColorTriple,
};

lazy_static! {
    static ref POS: Mutex<RobotSensorPosition> = Mutex::new(RobotSensorPosition::new(BOT));
    static ref RGB_MEANS: Mutex<Option<Kmeans<U8ColorTriple, f64, fn(&U8ColorTriple, &U8ColorTriple) -> f64>>> =
        Mutex::new(None);
    static ref KMEANS_READY: AtomicBool = AtomicBool::new(false);
    static ref TRAINING_TIME: AtomicU64 = AtomicU64::new(0);
    static ref TOTAL_KEYPOINTS: AtomicU64 = AtomicU64::new(0);
    static ref LAST_POINTS: Arc<Mutex<Vec<KeyPoint>>> = Arc::new(Mutex::new(vec![]));
    static ref LAST_FEATURES: Arc<Mutex<Vec<BitArray<64>>>> = Arc::new(Mutex::new(vec![]));
    static ref ALL_FEATURES: Arc<Mutex<HashSet<BitArray<64>>>> =
        Arc::new(Mutex::new(HashSet::new()));

    static ref KNN_IMAGES: Arc<Mutex<Knn<String, Vec<u8>, f64, fn(&Vec<u8>,&Vec<u8>) -> f64>>> = Arc::new(Mutex::new(Knn::new(3, Arc::new(distance_u8))));
}

pub fn train_knn(k: usize, examples: Vec<LabeledImage>) -> String {
    let mut knn_images = KNN_IMAGES.lock().unwrap();
    knn_images.clear_examples();
    for example in examples {
        knn_images.add_example((example.label, example.image));
    }
    knn_images.set_k(k);
    format!("Training finished; {} examples", knn_images.len())
}

pub fn classify_knn(img: Vec<u8>) -> String {
    match KNN_IMAGES.lock() {
        Ok(knn_images) => {
            if knn_images.has_enough_examples() {
                knn_images.classify(&img)
            } else {
                format!("Need more examples; {} < {}", knn_images.len(), knn_images.get_k())
            }
        }
        Err(e) => format!("Lock error: {e}")
    }
}

fn distance_rgba(img1: &RgbaImage, img2: &RgbaImage) -> f64 {
    img1.pixels().zip(img2.pixels())
        .map(|(p1, p2)| p1.channels().iter().zip(p2.channels().iter()).map(|(c1, c2)| (*c1 as f64 - *c2 as f64).powf(2.0)).sum::<f64>())
        .sum()
}

fn distance_u8(img1: &Vec<u8>, img2: &Vec<u8>) -> f64 {
    (0..min(img1.len(), img2.len()))
        .map(|i| (img1[i] as f64 - img2[i] as f64).powf(2.0))
        .sum()
}

pub fn kmeans_ready() -> bool {
    KMEANS_READY.load(Ordering::SeqCst)
}

pub fn training_time() -> i64 {
    TRAINING_TIME.load(Ordering::SeqCst) as i64
}

#[derive(Clone)]
pub struct LabeledImage {
    pub label: String,
    pub image: Vec<u8>,
}

#[derive(Clone)]
pub struct ImageData {
    pub ys: Vec<u8>,
    pub us: Vec<u8>,
    pub vs: Vec<u8>,
    pub width: i64,
    pub height: i64,
    pub uv_row_stride: i64,
    pub uv_pixel_stride: i64,
}

pub struct SensorData {
    pub sonar_front: i64,
    pub sonar_left: i64,
    pub sonar_right: i64,
    pub left_count: i64,
    pub right_count: i64,
    pub left_speed: i64,
    pub right_speed: i64,
}

pub struct ImageResponse {
    pub img: ZeroCopyBuffer<Vec<u8>>,
    pub msg: String,
}

impl SensorData {
    fn motor_data(&self) -> MotorData {
        MotorData {
            left_count: self.left_count,
            right_count: self.right_count,
            left_speed: self.left_speed,
            right_speed: self.right_speed,
        }
    }
}

pub fn intensity_rgba(intensities: Vec<u8>) -> ImageResponse {
    let mut result = Vec::new();
    for byte in intensities.iter().copied() {
        for _ in 0..3 {
            result.push(byte);
        }
        result.push(u8::MAX);
    }
    ImageResponse {
        img: ZeroCopyBuffer(result),
        msg: "Ok".to_owned(),
    }
}

pub fn yuv_rgba(img: ImageData) -> ImageResponse {
    ImageResponse {
        img: ZeroCopyBuffer(inner_yuv_rgba(&img)),
        msg: "Ok".to_owned(),
    }
}

pub fn color_count(img: ImageData) -> i64 {
    let rgba = inner_yuv_rgba(&img);
    let mut distinct_colors = BTreeSet::new();
    for i in (0..rgba.len()).step_by(4) {
        let color = (rgba[i], rgba[i + 1], rgba[i + 2]);
        distinct_colors.insert(color);
    }
    distinct_colors.len() as i64
}

fn cluster_colored(img: ImageData) -> Vec<u8> {
    let image = simple_yuv_rgb(&img);
    RGB_MEANS.lock().unwrap().as_ref().map_or_else(
        || {
            (0..(img.height * img.width * 4))
                .map(|i| if i % 4 == 0 { u8::MAX } else { 0 })
                .collect()
        },
        |kmeans| {
            let mut result = vec![];
            for color in image {
                let mean = kmeans.best_matching_mean(&color);
                let bytes: (u8, u8, u8) = mean.into();
                result.push(bytes.0);
                result.push(bytes.1);
                result.push(bytes.2);
                result.push(u8::MAX);
            }
            result
        },
    )
}

pub fn color_clusterer(img: ImageData) -> ImageResponse {
    if kmeans_ready() {
        ImageResponse {
            img: ZeroCopyBuffer(cluster_colored(img)),
            msg: "Ok".to_owned(),
        }
    } else {
        yuv_rgba(img)
    }
}

pub fn akaze_view(img: ImageData) -> ImageResponse {
    let rgba = convert(&img);
    let wrapped = DynamicImage::ImageRgba8(rgba);
    let akaze = Akaze::dense();
    let (keypoints, features) = akaze.extract(&wrapped);
    if let DynamicImage::ImageRgba8(mut unwrapped) = wrapped {
        let num_points = keypoints.len();
        TOTAL_KEYPOINTS.fetch_add(num_points as u64, Ordering::SeqCst);
        plot_keypoints_on(&keypoints, &mut unwrapped, [255, 0, 0, 255]);
        let total_features_seen = {
            let mut all_features = ALL_FEATURES.lock().unwrap();
            let last_features = LAST_FEATURES.lock().unwrap();
            for feature in last_features.iter() {
                all_features.insert(*feature);
            }
            all_features.len()
        };

        {
            *LAST_POINTS.lock().unwrap() = keypoints;
        }
        {
            *LAST_FEATURES.lock().unwrap() = features;
        }

        let total = TOTAL_KEYPOINTS.load(Ordering::SeqCst);
        ImageResponse {
            img: ZeroCopyBuffer(unwrapped.into_vec()),
            msg: format!(
                "points: {num_points} total features: {total_features_seen} ({} total, {} repeats)",
                total,
                total - total_features_seen as u64
            ),
        }
    } else {
        panic!("This shouldn't happen");
    }
}

pub fn akaze_flow(img: ImageData) -> ImageResponse {
    let rgba = convert(&img);
    let wrapped = DynamicImage::ImageRgba8(rgba);
    let akaze = Akaze::dense();
    let (keypoints, features) = akaze.extract(&wrapped);
    if let DynamicImage::ImageRgba8(mut unwrapped) = wrapped {
        {
            let last_keypoints = LAST_POINTS.lock().unwrap();
            let last_features = LAST_FEATURES.lock().unwrap();
            let movements = KeyPointMovements::feature_match(
                &last_keypoints,
                &last_features,
                &keypoints,
                &features,
            );
            //movements.render_on(&mut unwrapped, [0, 255, 0, 255]);
            movements.render_mean_on(&mut unwrapped, [255, 0, 0, 255]);
        }
        {
            let last_keypoints = LAST_POINTS.lock().unwrap();
            let last_features = LAST_FEATURES.lock().unwrap();
            let movements = KeyPointMovements::keypoint_match(
                &last_keypoints,
                &last_features,
                &keypoints,
                &features,
            );
            //movements.render_on(&mut unwrapped, [0, 0, 255, 255]);
            movements.render_mean_on(&mut unwrapped, [0, 255, 0, 255]);
        }
        {
            *LAST_POINTS.lock().unwrap() = keypoints;
        }
        {
            *LAST_FEATURES.lock().unwrap() = features;
        }
        ImageResponse {
            img: ZeroCopyBuffer(unwrapped.into_vec()),
            msg: format!(""),
        }
    } else {
        panic!("This shouldn't happen");
    }
}

fn plot_keypoints_on(
    keypoints: &Vec<KeyPoint>,
    img: &mut ImageBuffer<Rgba<u8>, Vec<u8>>,
    color: [u8; 4],
) {
    for kp in keypoints.iter().copied() {
        let (x, y) = kp.point;
        img.put_pixel(x as u32, y as u32, Rgba(color));
    }
}

pub fn reset_position_estimate() {
    let mut pos = POS.lock().unwrap();
    pos.reset();
}

pub fn process_sensor_data(incoming_data: String) -> String {
    let parsed = parse_sensor_data(incoming_data);
    let mut pos = POS.lock().unwrap();
    pos.motor_update(parsed.motor_data());
    let (x, y) = pos.get_pos().position();
    let h = pos.get_pos().heading();
    format!(
        "({x:.2} {y:.2} {h}) {:?} #{}",
        pos.get_encoder_counts(),
        pos.num_updates()
    )
}

pub fn parse_sensor_data(incoming_data: String) -> SensorData {
    let parts: HashMap<&str, i64> = incoming_data
        .split(";")
        .map(|s| {
            let mut ss = s.split(":");
            let key = ss.next().unwrap();
            let value: i64 = ss.next().unwrap().parse().unwrap();
            (key, value)
        })
        .collect();
    SensorData {
        sonar_front: *parts.get("SF").unwrap(),
        sonar_left: *parts.get("SL").unwrap(),
        sonar_right: *parts.get("SR").unwrap(),
        left_count: *parts.get("LC").unwrap(),
        right_count: *parts.get("RC").unwrap(),
        left_speed: *parts.get("LS").unwrap(),
        right_speed: *parts.get("RS").unwrap(),
    }
}
