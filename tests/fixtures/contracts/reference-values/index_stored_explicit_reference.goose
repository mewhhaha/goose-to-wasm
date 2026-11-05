fn main() { var h: u8[>..] = []; h.append("abc"); var views: (u8[:])[>..] = []; views.push(h[0..1]); views.push(h[1..2]); let element: u8[:]& = views[1]; print(views.index_of(element)); }
