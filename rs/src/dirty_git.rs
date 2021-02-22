use std::env::*;
use std::io::*;
use std::path::*;
use std::process::*;

fn has_dir(path: String, path_inside: &str) -> bool {
    let p = Path::new(&path);
    let mut found = false;
    for entry in p.read_dir().expect("can't read_dir") {
        if let Ok(entry) = entry {
            if entry.file_name() == path_inside {
                found = true
            }
        }
    }
    found
}

fn path_is_a_repo(path: String) -> bool {
    let p = Path::new(&path);
    p.is_dir() && has_dir(path, ".git")
}

fn git_diff_index(path: &String) -> Option<i32> {
    if path_is_a_repo(path.clone()) {
        match Command::new("git")
            .arg("diff-index")
            .arg("--quiet")
            .arg("HEAD")
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

pub fn main() {
    for d in args().skip(1) {
        match git_diff_index(&d) {
            Some(1) => println!("dirty: {:?}", &d),
            _ => (),
        }
    }
}
