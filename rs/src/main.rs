use std::io;
use std::io::prelude::*;
use std::fs::File;

fn main() -> io::Result<()> {
    let mut f = File::open("Cargo.toml")?;
    let mut buffer = [0; 10];

    // read up to 10 bytes
    let n = f.read(&mut buffer)?;

    println!("The bytes: {:?}", &buffer[..n]);
    Ok(())
}
