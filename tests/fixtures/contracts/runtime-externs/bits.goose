// std's rotations (upstream 75ad5bd3) and binary's float bits (23a7533b,
// 71455360), declared as upstream's std and binary declare them. A count
// is taken modulo the width, so a negative one turns the other way.
extern fn rotl32(x: u32, n: i64) -> u32 = "gs_rotl32";
extern fn rotl64(x: u64, n: i64) -> u64 = "gs_rotl64";
extern fn rotr32(x: u32, n: i64) -> u32 = "gs_rotr32";
extern fn rotr64(x: u64, n: i64) -> u64 = "gs_rotr64";
extern fn f32_of_bits(bits: u32) -> f32 = "gs_f32_from_bits";
extern fn f64_of_bits(bits: u64) -> f64 = "gs_f64_from_bits";
extern fn bits_of_f32(v: f32) -> u32 = "gs_f32_to_bits";
extern fn bits_of_f64(v: f64) -> u64 = "gs_f64_to_bits";
fn main() {
    let x: u32 = 2147483649;
    print(rotl32(x, 1), " ", rotl32(x, 0), " ", rotl32(x, 33), " ", rotl32(x, -1), " ", rotr32(x, 1), " ", rotr32(x, -1));
    let y: u64 = 9223372036854775809;
    print(rotl64(y, 4), " ", rotr64(y, 4), " ", rotl64(y, -4), " ", rotr64(y, 64), " ", rotl64(y, 65));
    print(f32_of_bits(1069547520), " ", f64_of_bits(4615063718147915776), " ", bits_of_f32(1.5), " ", bits_of_f64(-2.0));
    let quiet: u64 = 9221120237041090561;
    print(bits_of_f64(f64_of_bits(quiet)) == quiet, " ", bits_of_f32(f32_of_bits(2143289345)));
}
