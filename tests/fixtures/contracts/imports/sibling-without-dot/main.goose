// sub/user.goose names its sibling without the leading dot, so the import
// resolves from the program root, where there is no helper.goose.
import sub.user;

fn main() { user(); }
