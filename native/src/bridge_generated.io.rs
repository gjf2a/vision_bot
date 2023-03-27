use super::*;
// Section: wire functions

#[no_mangle]
pub extern "C" fn wire_train_knn(port_: i64, k: usize, examples: *mut wire_list_labeled_image) {
    wire_train_knn_impl(port_, k, examples)
}

#[no_mangle]
pub extern "C" fn wire_classify_knn(port_: i64, img: *mut wire_uint_8_list) {
    wire_classify_knn_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_train_knn_akaze_pos(
    port_: i64,
    k: usize,
    examples: *mut wire_list_labeled_image,
) {
    wire_train_knn_akaze_pos_impl(port_, k, examples)
}

#[no_mangle]
pub extern "C" fn wire_train_knn_akaze_features(
    port_: i64,
    k: usize,
    examples: *mut wire_list_labeled_image,
) {
    wire_train_knn_akaze_features_impl(port_, k, examples)
}

#[no_mangle]
pub extern "C" fn wire_classify_knn_akaze_pos(port_: i64, img: *mut wire_DartImage) {
    wire_classify_knn_akaze_pos_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_classify_knn_akaze_feature(port_: i64, img: *mut wire_DartImage) {
    wire_classify_knn_akaze_feature_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_kmeans_ready(port_: i64) {
    wire_kmeans_ready_impl(port_)
}

#[no_mangle]
pub extern "C" fn wire_training_time(port_: i64) {
    wire_training_time_impl(port_)
}

#[no_mangle]
pub extern "C" fn wire_intensity_rgba(port_: i64, intensities: *mut wire_uint_8_list) {
    wire_intensity_rgba_impl(port_, intensities)
}

#[no_mangle]
pub extern "C" fn wire_yuv_rgba(port_: i64, img: *mut wire_ImageData) {
    wire_yuv_rgba_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_color_count(port_: i64, img: *mut wire_ImageData) {
    wire_color_count_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_color_clusterer(port_: i64, img: *mut wire_ImageData) {
    wire_color_clusterer_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_akaze_view(port_: i64, img: *mut wire_ImageData) {
    wire_akaze_view_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_akaze_flow(port_: i64, img: *mut wire_ImageData) {
    wire_akaze_flow_impl(port_, img)
}

#[no_mangle]
pub extern "C" fn wire_reset_position_estimate(port_: i64) {
    wire_reset_position_estimate_impl(port_)
}

#[no_mangle]
pub extern "C" fn wire_process_sensor_data(port_: i64, incoming_data: *mut wire_uint_8_list) {
    wire_process_sensor_data_impl(port_, incoming_data)
}

#[no_mangle]
pub extern "C" fn wire_parse_sensor_data(port_: i64, incoming_data: *mut wire_uint_8_list) {
    wire_parse_sensor_data_impl(port_, incoming_data)
}

// Section: allocate functions

#[no_mangle]
pub extern "C" fn new_box_autoadd_dart_image_0() -> *mut wire_DartImage {
    support::new_leak_box_ptr(wire_DartImage::new_with_null_ptr())
}

#[no_mangle]
pub extern "C" fn new_box_autoadd_image_data_0() -> *mut wire_ImageData {
    support::new_leak_box_ptr(wire_ImageData::new_with_null_ptr())
}

#[no_mangle]
pub extern "C" fn new_list_labeled_image_0(len: i32) -> *mut wire_list_labeled_image {
    let wrap = wire_list_labeled_image {
        ptr: support::new_leak_vec_ptr(<wire_LabeledImage>::new_with_null_ptr(), len),
        len,
    };
    support::new_leak_box_ptr(wrap)
}

#[no_mangle]
pub extern "C" fn new_uint_8_list_0(len: i32) -> *mut wire_uint_8_list {
    let ans = wire_uint_8_list {
        ptr: support::new_leak_vec_ptr(Default::default(), len),
        len,
    };
    support::new_leak_box_ptr(ans)
}

// Section: related functions

// Section: impl Wire2Api

impl Wire2Api<String> for *mut wire_uint_8_list {
    fn wire2api(self) -> String {
        let vec: Vec<u8> = self.wire2api();
        String::from_utf8_lossy(&vec).into_owned()
    }
}
impl Wire2Api<DartImage> for *mut wire_DartImage {
    fn wire2api(self) -> DartImage {
        let wrap = unsafe { support::box_from_leak_ptr(self) };
        Wire2Api::<DartImage>::wire2api(*wrap).into()
    }
}
impl Wire2Api<ImageData> for *mut wire_ImageData {
    fn wire2api(self) -> ImageData {
        let wrap = unsafe { support::box_from_leak_ptr(self) };
        Wire2Api::<ImageData>::wire2api(*wrap).into()
    }
}
impl Wire2Api<DartImage> for wire_DartImage {
    fn wire2api(self) -> DartImage {
        DartImage {
            bytes: self.bytes.wire2api(),
            width: self.width.wire2api(),
            height: self.height.wire2api(),
        }
    }
}

impl Wire2Api<ImageData> for wire_ImageData {
    fn wire2api(self) -> ImageData {
        ImageData {
            ys: self.ys.wire2api(),
            us: self.us.wire2api(),
            vs: self.vs.wire2api(),
            width: self.width.wire2api(),
            height: self.height.wire2api(),
            uv_row_stride: self.uv_row_stride.wire2api(),
            uv_pixel_stride: self.uv_pixel_stride.wire2api(),
        }
    }
}
impl Wire2Api<LabeledImage> for wire_LabeledImage {
    fn wire2api(self) -> LabeledImage {
        LabeledImage {
            label: self.label.wire2api(),
            image: self.image.wire2api(),
        }
    }
}
impl Wire2Api<Vec<LabeledImage>> for *mut wire_list_labeled_image {
    fn wire2api(self) -> Vec<LabeledImage> {
        let vec = unsafe {
            let wrap = support::box_from_leak_ptr(self);
            support::vec_from_leak_ptr(wrap.ptr, wrap.len)
        };
        vec.into_iter().map(Wire2Api::wire2api).collect()
    }
}

impl Wire2Api<Vec<u8>> for *mut wire_uint_8_list {
    fn wire2api(self) -> Vec<u8> {
        unsafe {
            let wrap = support::box_from_leak_ptr(self);
            support::vec_from_leak_ptr(wrap.ptr, wrap.len)
        }
    }
}

// Section: wire structs

#[repr(C)]
#[derive(Clone)]
pub struct wire_DartImage {
    bytes: *mut wire_uint_8_list,
    width: i64,
    height: i64,
}

#[repr(C)]
#[derive(Clone)]
pub struct wire_ImageData {
    ys: *mut wire_uint_8_list,
    us: *mut wire_uint_8_list,
    vs: *mut wire_uint_8_list,
    width: i64,
    height: i64,
    uv_row_stride: i64,
    uv_pixel_stride: i64,
}

#[repr(C)]
#[derive(Clone)]
pub struct wire_LabeledImage {
    label: *mut wire_uint_8_list,
    image: wire_DartImage,
}

#[repr(C)]
#[derive(Clone)]
pub struct wire_list_labeled_image {
    ptr: *mut wire_LabeledImage,
    len: i32,
}

#[repr(C)]
#[derive(Clone)]
pub struct wire_uint_8_list {
    ptr: *mut u8,
    len: i32,
}

// Section: impl NewWithNullPtr

pub trait NewWithNullPtr {
    fn new_with_null_ptr() -> Self;
}

impl<T> NewWithNullPtr for *mut T {
    fn new_with_null_ptr() -> Self {
        std::ptr::null_mut()
    }
}

impl NewWithNullPtr for wire_DartImage {
    fn new_with_null_ptr() -> Self {
        Self {
            bytes: core::ptr::null_mut(),
            width: Default::default(),
            height: Default::default(),
        }
    }
}

impl Default for wire_DartImage {
    fn default() -> Self {
        Self::new_with_null_ptr()
    }
}

impl NewWithNullPtr for wire_ImageData {
    fn new_with_null_ptr() -> Self {
        Self {
            ys: core::ptr::null_mut(),
            us: core::ptr::null_mut(),
            vs: core::ptr::null_mut(),
            width: Default::default(),
            height: Default::default(),
            uv_row_stride: Default::default(),
            uv_pixel_stride: Default::default(),
        }
    }
}

impl Default for wire_ImageData {
    fn default() -> Self {
        Self::new_with_null_ptr()
    }
}

impl NewWithNullPtr for wire_LabeledImage {
    fn new_with_null_ptr() -> Self {
        Self {
            label: core::ptr::null_mut(),
            image: Default::default(),
        }
    }
}

impl Default for wire_LabeledImage {
    fn default() -> Self {
        Self::new_with_null_ptr()
    }
}

// Section: sync execution mode utility

#[no_mangle]
pub extern "C" fn free_WireSyncReturn(ptr: support::WireSyncReturn) {
    unsafe {
        let _ = support::box_from_leak_ptr(ptr);
    };
}
