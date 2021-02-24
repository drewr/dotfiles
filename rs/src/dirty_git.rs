// To be used with xargs:
//
//     find . -type d | xargs dg

use std::env::args;
use std::path::Path;
use std::process::{Command, Output};

fn path_is_a_repo(path: &str) -> bool {
    let p = Path::new(&path);
    p.is_dir() && p.join(".git").exists()
}

fn git_diff_index(path: &str) -> Option<i32> {
    if path_is_a_repo(path) {
        match Command::new("git")
            .arg("diff-index")
            .arg("--quiet")
            .arg("HEAD")
            .current_dir(path)
            .output()
        {
            Ok(Output { status: s, .. }) => s.code(),
            Err(_) => None,
        }
    } else {
        None
    }
}

fn main() -> std::io::Result<()> {
    for dir in args().skip(1) {
        // TODO eventually take a --debug arg, but don't want to deal
        // with parsing libraries yet
        //println!("debug: {:?}", &dir);
        match git_diff_index(&dir) {
            Some(128) => println!("nohead {}", &dir),
            Some(1) => println!("dirty {}", &dir),
            _ => (),
        }
    }
    Ok(())
}
