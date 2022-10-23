use git2;
use regex::Regex;
use std::{env, path, process};

#[derive(PartialEq, Debug)]
enum RepoVendor {
    GitHub,
    Sourcehut,
}

#[derive(PartialEq, Debug)]
enum RepoProto {
    HTTP,
    SSH,
}

#[derive(PartialEq, Debug)]
struct RepoToClone {
    raw: String,
    name: String,
    org: String,
    vendor: RepoVendor,
    proto: RepoProto,
}

fn make_repo(location: &str) -> Option<RepoToClone> {
    let pat = r"([^@:]+)(@|://)(github\.com|git\.sr\.ht)[:/]~?([^/]+)/([^./]+).*$";
    let re = Regex::new(pat).unwrap();
    let caps = match re.captures(location) {
        Some(result) => result,
        None => return None,
    };
    match [
        caps.get(1).map_or("", |m| m.as_str()),
        caps.get(3).map_or("", |m| m.as_str()),
        caps.get(4).map_or("", |m| m.as_str()),
        caps.get(5).map_or("", |m| m.as_str()),
    ] {
        ["https", "github.com", org, name] => Some(RepoToClone {
            raw: location.to_string(),
            proto: RepoProto::HTTP,
            vendor: RepoVendor::GitHub,
            name: name.to_string(),
            org: org.to_string(),
        }),
        ["git", "github.com", org, name] => Some(RepoToClone {
            raw: location.to_string(),
            proto: RepoProto::SSH,
            vendor: RepoVendor::GitHub,
            name: name.to_string(),
            org: org.to_string(),
        }),
        ["https", "git.sr.ht", org, name] => Some(RepoToClone {
            raw: location.to_string(),
            proto: RepoProto::HTTP,
            vendor: RepoVendor::Sourcehut,
            name: name.to_string(),
            org: org.to_string(),
        }),
        ["git", "git.sr.ht", org, name] => Some(RepoToClone {
            raw: location.to_string(),
            proto: RepoProto::SSH,
            vendor: RepoVendor::Sourcehut,
            name: name.to_string(),
            org: org.to_string(),
        }),
        wrong => {
            println!("failed match: {:?}", wrong);
            None
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        println!("supply at least one repo");
        process::exit(1);
    }

    let repo = match make_repo(&args[1]) {
        Some(r) => r,
        None => {
            println!("invalid repo: {}", &args[1]);
            process::exit(1);
        }
    };

    let dest: path::PathBuf = [
        env::var("HOME").unwrap(),
        "src".to_string(),
        repo.org,
        repo.name,
    ]
    .iter()
    .collect();

    let mut fetch_opts = git2::FetchOptions::new();
    if repo.proto == RepoProto::SSH {
        let mut callbacks = git2::RemoteCallbacks::new();
        callbacks.credentials(|_url, username_from_url, _allowed_types| {
            git2::Cred::ssh_key_from_agent(username_from_url.unwrap())
        });
        fetch_opts.remote_callbacks(callbacks);
    }

    let mut builder = git2::build::RepoBuilder::new();
    builder.fetch_options(fetch_opts);

    match builder.clone(&repo.raw, dest.as_path()) {
        Ok(result) => result,
        Err(e) => panic!("failed: {}", e),
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse() {
        let github_http = RepoToClone {
            raw: "https://github.com/alice/repo".to_string(),
            vendor: RepoVendor::GitHub,
            proto: RepoProto::HTTP,
            name: "repo".to_string(),
            org: "alice".to_string(),
        };

        let sourcehut_http = RepoToClone {
            raw: "https://git.sr.ht/~alice/repo".to_string(),
            vendor: RepoVendor::Sourcehut,
            proto: RepoProto::HTTP,
            name: "repo".to_string(),
            org: "alice".to_string(),
        };

        let github_ssh = RepoToClone {
            raw: "git@github.com:alice/repo".to_string(),
            vendor: RepoVendor::GitHub,
            proto: RepoProto::SSH,
            name: "repo".to_string(),
            org: "alice".to_string(),
        };

        let sourcehut_ssh = RepoToClone {
            raw: "git@git.sr.ht:~alice/repo".to_string(),
            vendor: RepoVendor::Sourcehut,
            proto: RepoProto::SSH,
            name: "repo".to_string(),
            org: "alice".to_string(),
        };

        assert_eq!(
            make_repo("https://github.com/alice/repo").unwrap(),
            github_http
        );
        assert_eq!(make_repo("git@github.com:alice/repo").unwrap(), github_ssh);
        assert_eq!(
            make_repo("https://git.sr.ht/~alice/repo").unwrap(),
            sourcehut_http
        );
        assert_eq!(
            make_repo("git@git.sr.ht:~alice/repo").unwrap(),
            sourcehut_ssh
        );
    }
}
