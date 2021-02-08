// grep - from Programming Rust, pg. 438

use std::error::Error;
use std::fs::File;
use std::io::prelude::*;
use std::io::{self, BufReader};
use std::path::PathBuf;
use std::io::Cursor;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grep() -> Result<(), String> {
        let v = vec![
            "this is the first line",
            "now another",
            "if this was a haiku it would end here",
            "one more tho",
        ];
        assert_eq!(grep("more", Cursor::new(v))?, Ok());

    }
}

fn grep<R>(target: &str, reader: R) -> io::Result<()>
where
    R: BufRead,
{
    for line_result in reader.lines() {
        let line = line_result?;
        if line.contains(target) {
            println!("{}", line);
        }
    }
    Ok(())
}

// dyn now required
// https://github.com/rust-lang/rfcs/blob/master/text/2113-dyn-trait-syntax.md
fn grep_main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let target = match args.next() {
        Some(s) => s,
        None => Err("usage: grep PATTERN FILE...")?,
    };
    let files: Vec<PathBuf> = args.map(PathBuf::from).collect();
    if files.is_empty() {
        let stdin = io::stdin();
        grep(&target, stdin.lock())?;
    } else {
        for file in files {
            let f = File::open(file)?;
            grep(&target, BufReader::new(f))?;
        }
    }
    Ok(())
}

fn main() {
    let result = grep_main();
    if let Err(err) = result {
        let _ = writeln!(io::stderr(), "{}", err);
    }
}
