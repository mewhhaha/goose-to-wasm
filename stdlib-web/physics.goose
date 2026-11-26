// Rigid-body box physics through the Web host.
namespace physics;

import std;
import math;
import vec;

let STATIC = 0;
let KINEMATIC = 1;
let DYNAMIC = 2;
let ALL_BITS: u64 = 0xFFFFFFFFFFFFFFFF;

struct Quat { x: f32 = 0.0, y: f32 = 0.0, z: f32 = 0.0, w: f32 = 1.0 }
struct Transform { p: float3 = float3_0, q: Quat = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 } }
struct World { id: u32 }
struct Body { id: u64 }
struct Shape { id: u64 }
struct Capacity { dynamic_bodies: i32 = 0, static_bodies: i32 = 0, shapes: i32 = 0, joints: i32 = 0 }
struct WorldDef {
    gravity: float3 = float3 { 0.0, -10.0, 0.0 },
    restitution_threshold: f32 = 1.0,
    hit_event_threshold: f32 = 1.0,
    contact_hertz: f32 = 30.0,
    contact_damping_ratio: f32 = 10.0,
    contact_speed: f32 = 3.0,
    maximum_linear_speed: f32 = 400.0,
    enable_sleep: bool = true,
    enable_continuous: bool = true,
    workers: i32 = 1,
    friction_mixing: i32 = 0,
    restitution_mixing: i32 = 0,
    user_data: u64 = 0,
    capacity: Capacity = Capacity {}
}
struct MotionLocks {
    linear_x: bool = false, linear_y: bool = false, linear_z: bool = false,
    angular_x: bool = false, angular_y: bool = false, angular_z: bool = false
}
struct BodyDef {
    body_type: i32 = 0,
    position: float3 = float3_0,
    rotation: Quat = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
    linear_velocity: float3 = float3_0,
    angular_velocity: float3 = float3_0,
    linear_damping: f32 = 0.0,
    angular_damping: f32 = 0.0,
    gravity_scale: f32 = 1.0,
    sleep_threshold: f32 = 0.05,
    safety_factor: f32 = 0.5,
    motion_locks: MotionLocks = MotionLocks {},
    enable_sleep: bool = true,
    is_awake: bool = true,
    is_bullet: bool = false,
    is_enabled: bool = true,
    allow_fast_rotation: bool = false,
    enable_contact_recycling: bool = true,
    user_data: u64 = 0
}
struct SurfaceMaterial {
    friction: f32 = 0.6, restitution: f32 = 0.0, rolling_resistance: f32 = 0.0,
    tangent_velocity: float3 = float3_0, user_material_id: u64 = 0, custom_color: u32 = 0
}
struct Filter {
    category_bits: u64 = 0xFFFFFFFFFFFFFFFF, mask_bits: u64 = 0xFFFFFFFFFFFFFFFF, group_index: i32 = 0
}
struct ShapeDef {
    material: SurfaceMaterial = SurfaceMaterial {},
    density: f32 = 1000.0,
    filter: Filter = Filter {},
    is_sensor: bool = false,
    enable_sensor_events: bool = false,
    enable_contact_events: bool = false,
    enable_hit_events: bool = false,
    invoke_contact_creation: bool = true,
    update_body_mass: bool = true,
    enable_speculative_contact: bool = true,
    explosion_scale: f32 = 1.0,
    user_data: u64 = 0
}
struct ExplosionDef {
    position: float3 = float3_0, radius: f32 = 0.0, falloff: f32 = 0.0,
    impulse_per_area: f32 = 0.0, mask_bits: u64 = 0xFFFFFFFFFFFFFFFF
}

let quat_identity = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
let transform_identity = Transform { p: float3_0, q: quat_identity };

fn quat_axis_angle(axis: float3, angle: f32) -> Quat {
    let size = length(axis);
    if size == 0.0 { return quat_identity; }
    let half: f32 = angle * 0.5;
    let xyz = axis / size * sin(half);
    return Quat { xyz.x, xyz.y, xyz.z, cos(half) };
}

fn mul(a: Quat, b: Quat) -> Quat {
    Quat { a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
           a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
           a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
           a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
}

fn conjugate(q: Quat) -> Quat { Quat { -q.x, -q.y, -q.z, q.w } }

fn normalize(q: Quat) -> Quat {
    let size = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
    if size == 0.0 { return quat_identity; }
    return Quat { q.x / size, q.y / size, q.z / size, q.w / size };
}

fn rotate(q: Quat, v: float3) -> float3 {
    let axis = float3 { q.x, q.y, q.z };
    let t = cross(axis, v) * 2.0;
    return v + t * q.w + cross(axis, t);
}

extern fn detail::available() -> bool = "gs_phys_available";
extern fn detail::create_world(def: const physics::WorldDef&) -> u32 = "gs_phys_create_world";
extern fn detail::destroy_world(id: u32) = "gs_phys_destroy_world";
extern fn detail::create_body(world: u32, def: const physics::BodyDef&) -> u64 = "gs_phys_create_body";
extern fn detail::destroy_body(id: u64) = "gs_phys_destroy_body";
extern fn detail::create_box_shape(body: u64, def: const physics::ShapeDef&, half: const float3&,
                                   frame: const physics::Transform&) -> u64 = "gs_phys_create_box_shape";
extern fn detail::step(world: u32, time_step: f32, sub_steps: i64) = "gs_phys_step";
extern fn detail::transform(body: u64, out: physics::Transform&) = "gs_phys_transform";
extern fn detail::transforms(bodies: const physics::Body[:], out: physics::Transform[:]) = "gs_phys_transforms";
extern fn detail::linear_velocity(body: u64, out: float3&) = "gs_phys_linear_velocity";
extern fn detail::angular_velocity(body: u64, out: float3&) = "gs_phys_angular_velocity";
extern fn detail::set_transform(body: u64, pos: const float3&, rot: const physics::Quat&) = "gs_phys_set_transform";
extern fn detail::set_linear_velocity(body: u64, v: const float3&) = "gs_phys_set_linear_velocity";
extern fn detail::set_angular_velocity(body: u64, v: const float3&) = "gs_phys_set_angular_velocity";
extern fn detail::set_awake(body: u64, awake: bool) = "gs_phys_set_awake";
extern fn detail::explode(world: u32, def: const physics::ExplosionDef&) = "gs_phys_explode";
extern fn detail::awake_body_count(world: u32) -> i64 = "gs_phys_awake_body_count";
extern fn detail::worker_count(world: u32) -> i64 = "gs_phys_worker_count";

fn available() -> bool { detail::available() }

fn create_world() -> World { create_world(WorldDef {}) }
fn create_world(def: WorldDef) -> World { World { id: detail::create_world(def) } }
fn destroy(w: World) { detail::destroy_world(w.id); }

fn create_body(w: World, def: BodyDef) -> Body {
    Body { id: detail::create_body(w.id, def) }
}
fn destroy(b: Body) { detail::destroy_body(b.id); }

fn create_box_shape(b: Body, def: ShapeDef, half_extents: float3) -> Shape {
    create_box_shape(b, def, half_extents, transform_identity)
}
fn create_box_shape(b: Body, def: ShapeDef, half_extents: float3, frame: Transform) -> Shape {
    Shape { id: detail::create_box_shape(b.id, def, half_extents, frame) }
}

fn step(w: World, time_step: f32, sub_steps: i64) { detail::step(w.id, time_step, sub_steps); }

fn transform(b: Body) -> Transform {
    var out = transform_identity;
    detail::transform(b.id, out);
    return out;
}
fn position(b: Body) -> float3 { transform(b).p }
fn rotation(b: Body) -> Quat { transform(b).q }
fn transforms(bodies: const Body[:], out: Transform[:]) { detail::transforms(bodies, out); }

fn linear_velocity(b: Body) -> float3 {
    var out = float3_0;
    detail::linear_velocity(b.id, out);
    return out;
}
fn angular_velocity(b: Body) -> float3 {
    var out = float3_0;
    detail::angular_velocity(b.id, out);
    return out;
}

fn set_transform(b: Body, pos: float3, rot: Quat) { detail::set_transform(b.id, pos, rot); }
fn set_linear_velocity(b: Body, v: float3) { detail::set_linear_velocity(b.id, v); }
fn set_angular_velocity(b: Body, v: float3) { detail::set_angular_velocity(b.id, v); }
fn set_awake(b: Body, awake: bool) { detail::set_awake(b.id, awake); }
fn explode(w: World, def: ExplosionDef) { detail::explode(w.id, def); }
fn awake_body_count(w: World) -> i64 { detail::awake_body_count(w.id) }
fn worker_count(w: World) -> i64 { detail::worker_count(w.id) }
