use std::f32::consts::PI;

pub fn ease_in_out_cubic(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    if t < 0.5 {
        4.0 * t * t * t
    } else {
        1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
    }
}

pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

pub fn phase(p: f32, start: f32, end: f32) -> f32 {
    ((p - start) / (end - start)).clamp(0.0, 1.0)
}

pub fn damped_sin(t: f32, freq: f32, decay: f32) -> f32 {
    (-decay * t).exp() * (2.0 * PI * freq * t).sin()
}
