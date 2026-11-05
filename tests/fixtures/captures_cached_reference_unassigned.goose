struct Cell{v:i64} var cells:Cell[>..]=[];fn run(c:bool){var r:Cell&;fn rd(){print(r.v);}if c{r .= cells[0];rd();}rd();}fn main(){cells.push(Cell{5});run(false);}
