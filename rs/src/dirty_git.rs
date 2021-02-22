use std::env::*;
use std::io::*;
use std::path::*;
use std::process::*;

fn path_is_a_repo(path: PathBuf) -> bool {
    path.is_dir() && 
}

fn git_diff_index<P>(path: P) -> Option<i32>
where
    P: AsRef<Path>,
{
    if path_is_a_repo(path.) {
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
    for d in args_os().skip(1) {
        match git_diff_index(&d) {
            Some(1) => println!("{:?}: dirty", &d),
            _ => print!(""),
        }
    }
}
