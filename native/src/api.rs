use std::{collections::BTreeSet, sync::atomic::{Ordering, AtomicBool, AtomicU64}};
use cv::{feature::akaze::Akaze, image::image::DynamicImage};
use flutter_rust_bridge::{ZeroCopyBuffer};
use image::Rgba;
use std::collections::HashMap;
pub use particle_filter::sonar3bot::{RobotSensorPosition, BOT, MotorData};
use flutter_rust_bridge::support::lazy_static;
use std::sync::{Mutex};
use kmeans::Kmeans;

use crate::{image_proc::{inner_yuv_rgba, simple_yuv_rgb, U8ColorTriple, convert}};

lazy_static! {
    static ref POS: Mutex<RobotSensorPosition> = Mutex::new(RobotSensorPosition::new(BOT));
    static ref RGB_MEANS: Mutex<Option<Kmeans<U8ColorTriple, f64, fn (&U8ColorTriple,&U8ColorTriple)->f64>>> = Mutex::new(None);
    static ref KMEANS_READY: AtomicBool = AtomicBool::new(false);
    static ref TRAINING_TIME: AtomicU64 = AtomicU64::new(0);
}

pub fn kmeans_ready() -> bool {
    KMEANS_READY.load(Ordering::SeqCst)
}

pub fn training_time() -> i64 {
    TRAINING_TIME.load(Ordering::SeqCst) as i64
}

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
    pub right_speed: i64
}

impl SensorData {
    fn motor_data(&self) -> MotorData {
        MotorData {left_count: self.left_count, right_count: self.right_count, left_speed: self.left_speed, right_speed: self.right_speed}
    }
}

pub fn intensity_rgba(intensities: Vec<u8>) -> ZeroCopyBuffer<Vec<u8>> {
    let mut result = Vec::new();
    for byte in intensities.iter().copied() {
        for _ in 0..3 {
            result.push(byte);
        }
        result.push(u8::MAX);
    }
    ZeroCopyBuffer(result)
}

pub fn yuv_rgba(img: ImageData) -> ZeroCopyBuffer<Vec<u8>> {
    ZeroCopyBuffer(inner_yuv_rgba(&img))
}

pub fn color_count(img: ImageData) -> i64 {
    let rgba = inner_yuv_rgba(&img);
    let mut distinct_colors = BTreeSet::new();
    for i in (0..rgba.len()).step_by(4) {
        let color = (rgba[i], rgba[i+1], rgba[i+2]);
        distinct_colors.insert(color);
    }
    distinct_colors.len() as i64
}   

fn cluster_colored(img: ImageData) -> Vec<u8> {
    let image = simple_yuv_rgb(&img);
    RGB_MEANS.lock().unwrap().as_ref().map_or_else(|| {
        (0..(img.height * img.width * 4)).map(|i| if i % 4 == 0 {u8::MAX} else {0}).collect()
    }, |kmeans| {
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
    })
}

pub fn color_clusterer(img: ImageData) -> ZeroCopyBuffer<Vec<u8>> {
    if kmeans_ready() {
        ZeroCopyBuffer(cluster_colored(img))
    } else {
        yuv_rgba(img)
    }
}

pub fn akaze_view(img: ImageData) -> ZeroCopyBuffer<Vec<u8>> {
    let rgba = convert(&img);
    let wrapped = DynamicImage::ImageRgba8(rgba);
    let akaze = Akaze::dense();
    let (keypoints, _) = akaze.extract(&wrapped);
    if let DynamicImage::ImageRgba8(mut unwrapped) = wrapped {
        for kp in keypoints {
            let (x, y) = kp.point;
            unwrapped.put_pixel(x as u32, y as u32, Rgba([255, 0, 0, 255]));
        }
        ZeroCopyBuffer(unwrapped.into_vec())
    } else {
        panic!("This shouldn't happen");
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
    format!("({x:.2} {y:.2} {h}) {:?} #{}", pos.get_encoder_counts(), pos.num_updates())
}

pub fn parse_sensor_data(incoming_data: String) -> SensorData {
    let parts: HashMap<&str,i64> = incoming_data.split(";").map(|s| {
        let mut ss = s.split(":");
        let key = ss.next().unwrap();
        let value: i64 = ss.next().unwrap().parse().unwrap();
        (key, value)
    }).collect();
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
