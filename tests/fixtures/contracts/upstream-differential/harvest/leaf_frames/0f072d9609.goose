recursive fn leave() { return [1] from enable; }
fn enable()->i64[>..] { leave(); return []; }
struct Board { cells:i64[4], marker:i64 }
struct Packet { board:Board, values:i64[>..] }
recursive fn make(n:i64)->Packet {
    recursive fn observe()->i64 { return n+1; }
    return Packet {Board {[n,observe(),n+2,n+3],20},[9]};
}
recursive fn score(b:Board&)->i64 { b.cells[0]+b.cells[1]+b.cells[2]+b.cells[3]+b.marker }
recursive fn place(b:Board&,n:i64) { b.cells[0]+=n; b.marker++; }
recursive fn unplace(b:Board&,n:i64) { b.cells[0]-=n; b.marker--; }
recursive fn solve(b:Board&,n:i64)->i64 {
    if n==0 { return score(b); }
    place(b,n); let value=solve(b,n-1); unplace(b,n); return value+score(b);
}
recursive fn even(b:Board&,n:i64)->i64 {
    if n==0 { return score(b); }
    place(b,n); let value=odd(b,n-1); unplace(b,n); return value+1;
}
recursive fn odd(b:Board&,n:i64)->i64 {
    if n==0 { return score(b); }
    place(b,n); let value=even(b,n-1); unplace(b,n); return value+2;
}
fn main() {
    let packet=make(10); let board:Board& = packet.board; let temporary=make(3);
    print(solve(board,3)," ",score(board)," ",even(board,4)," ",score(board)," ",packet.values[0]);
    print(enable().len);
}
