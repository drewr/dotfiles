// To be used with xargs:
//
//     find . -type d | xargs dg

use clap::Clap;
use std::path::Path;
use std::process::{Command, Output};

#[derive(Clap)]
#[clap(version = "1.0", author = "Drew Raines <drew@raines.me>")]
struct Opts {
    #[clap(short)]
    debug: bool,
    paths: Vec<String>,
}

type MyPath = str;

fn path_is_a_repo(path: &MyPath) -> bool {
    let p = Path::new(&path);
    p.is_dir() && p.join(".git").exists()
}

fn git_diff_index(path: &MyPath) -> Option<i32> {
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
    let opts: Opts = Opts::parse();

    for dir in opts.paths.iter() {
        if opts.debug {
            println!("debug: {:?}", &dir);
        }
        match git_diff_index(&dir) {
            Some(128) => println!("nohead {}", &dir),
            Some(1) => println!("dirty {}", &dir),
            _ => (),
        }
    }
    Ok(())
}
