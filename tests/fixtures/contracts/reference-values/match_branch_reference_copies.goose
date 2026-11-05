fn main() { var a=1; var b=2; let copied=match a { 1 => &a, _ => &b }; a=5; print(copied," ",a); }
