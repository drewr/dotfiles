// To be used with xargs:
//
//     find . -type d | xargs dg

use std::env::args;
use std::path::Path;
use std::process::Command;

/// checks if the path is a dir and contaians ".git" folder
fn path_is_a_repo(path: &str) -> bool {
    let p = Path::new(&path);
    p.is_dir() && p.join(".git").exists()
}

fn git_diff_index(path: &str) -> Option<i32> {
    if path_is_a_repo(path) {
        match Command::new("git").arg("diff-index").arg("--quiet").arg("HEAD")
            .current_dir(path)
            .status()
        {
            Ok(s) => s.code(),
            Err(_) => None,
        }
    } else {
        None
    }
}

fn main() -> std::io::Result<()> {
    for dir in args().skip(1) {
        match git_diff_index(&dir) {
            Some(1) => println!("{}", &dir),
            _ => (),
        }
    }
    Ok(())
}
