struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn empty(p:Row[>..]&?)->bool{!p&&p==null}
fn give<F>(){F()}
fn trial()->i64{give(){return 7 from trial;}0}
fn main(){assert(empty(null));print(trial());}
