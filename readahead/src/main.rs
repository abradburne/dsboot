//! Starting the RG DS+ is held back by how fast its card can be read, and for the first
//! seconds the card sits half idle while udev works. This reads, in that time, the parts of
//! files that the programs started next are going to ask for.
//!
//! `record` notes which pages of which files are in memory now, which during a start is what
//! that start has read so far. `play` reads them back in, in order, on a later one. Recording
//! at several moments of one start and playing the lists in that order has the card read
//! things roughly in the order they will be wanted.

use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::os::unix::fs::{FileExt, MetadataExt};
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

const PAGE: u64 = 4096;
/// Stretches of a file closer together than this are read as one.
const JOIN: u64 = 16 * PAGE;
/// How much `play` asks for at a time, so that other readers get a turn in between.
const STEP: u64 = 256 * 1024;

const USAGE: &str = "usage: dsboot-readahead record LIST --first NAME... --under DIR...
       dsboot-readahead play LIST...
       dsboot-readahead cover ROOT LIST

  record  write to LIST the parts of files now in memory: first the files the running
          programs called NAME have open, in that order, then every file under each DIR
  play    read those parts back in, in the order listed, one LIST after another
  cover   LIST names files as \"size date path\"; mount ROOT/path over each path that
          still has that size and date (seconds)";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let done = match args.split_first() {
        Some((verb, rest)) if verb == "record" && !rest.is_empty() => record(&rest[0], &rest[1..]),
        Some((verb, rest)) if verb == "play" && !rest.is_empty() => {
            stand_back();
            // A list that is missing is passed over, like a file that is.
            rest.iter().for_each(|list| drop(play(list)));
            Ok(())
        }
        Some((verb, rest)) if verb == "cover" && rest.len() == 2 => cover(&rest[0], &rest[1]),
        _ => Err(USAGE.to_owned()),
    };
    if let Err(e) = done {
        eprintln!("dsboot-readahead: {e}");
        std::process::exit(1);
    }
}

fn record(list: &str, args: &[String]) -> Result<(), String> {
    let (mut names, mut dirs, mut into) = (Vec::new(), Vec::new(), None::<bool>);
    for a in args {
        match a.as_str() {
            "--first" => into = Some(true),
            "--under" => into = Some(false),
            _ => match into {
                Some(true) => names.push(a.as_str()),
                Some(false) => dirs.push(PathBuf::from(a)),
                None => return Err(USAGE.to_owned()),
            },
        }
    }

    let mut files = Vec::new();
    for name in names {
        for pid in pids(name) {
            files.extend(mapped(pid).into_iter().filter(|f| dirs.iter().any(|d| f.starts_with(d))));
        }
    }
    for dir in &dirs {
        walk(dir, &mut files);
    }

    let mut out = BufWriter::new(File::create(list).map_err(|e| format!("{list}: {e}"))?);
    let mut seen = HashSet::new();
    let (mut count, mut total) = (0, 0);
    for path in files {
        let Ok(file) = File::open(&path) else { continue };
        let Ok(meta) = file.metadata() else { continue };
        if !meta.is_file() || meta.len() == 0 || !seen.insert((meta.dev(), meta.ino())) {
            continue;
        }
        let runs = resident(&file, meta.len());
        if !runs.is_empty() {
            count += 1;
        }
        for (start, len) in runs {
            total += len;
            writeln!(out, "{start}\t{len}\t{}", path.display()).map_err(|e| e.to_string())?;
        }
    }
    out.flush().map_err(|e| e.to_string())?;
    println!("readahead: {} MB in {count} files", total / (1 << 20));
    Ok(())
}

/// Running programs with this name.
fn pids(name: &str) -> Vec<u32> {
    let mut found: Vec<u32> = fs::read_dir("/proc")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.parse().ok())
        .filter(|pid| fs::read_to_string(format!("/proc/{pid}/comm")).is_ok_and(|c| c.trim_end() == name))
        .collect();
    found.sort();
    found
}

/// The files a program has mapped, in the order they appear.
fn mapped(pid: u32) -> Vec<PathBuf> {
    let Ok(maps) = fs::read_to_string(format!("/proc/{pid}/maps")) else { return Vec::new() };
    let mut files: Vec<PathBuf> = Vec::new();
    for line in maps.lines() {
        // address perms offset dev inode path
        if let Some(path) = line.splitn(6, ' ').nth(5).map(str::trim_start).filter(|p| p.starts_with('/')) {
            if files.last().is_none_or(|last| last != Path::new(path)) {
                files.push(PathBuf::from(path));
            }
        }
    }
    files
}

/// Every regular file under `dir`, without following links.
fn walk(dir: &Path, files: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    let mut entries: Vec<_> = entries.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let Ok(kind) = entry.file_type() else { continue };
        if kind.is_dir() {
            walk(&entry.path(), files);
        } else if kind.is_file() {
            files.push(entry.path());
        }
    }
}

/// The stretches of the file that are in memory, as (start, length) in bytes.
fn resident(file: &File, len: u64) -> Vec<(u64, u64)> {
    let pages = len.div_ceil(PAGE) as usize;
    let mut held = vec![0u8; pages];
    // SAFETY: the mapping is only ever passed to mincore, which reads no memory through it,
    // and is unmapped before returning.
    unsafe {
        let map = libc::mmap(std::ptr::null_mut(), len as usize, libc::PROT_READ, libc::MAP_SHARED, file.as_raw_fd(), 0);
        if map == libc::MAP_FAILED {
            return Vec::new();
        }
        let got = libc::mincore(map, len as usize, held.as_mut_ptr().cast());
        libc::munmap(map, len as usize);
        if got != 0 {
            return Vec::new();
        }
    }
    let mut runs: Vec<(u64, u64)> = Vec::new();
    for (page, _) in held.iter().enumerate().filter(|(_, h)| **h & 1 == 1) {
        let at = page as u64 * PAGE;
        match runs.last_mut() {
            Some((start, run)) if at <= *start + *run + JOIN => *run = at + PAGE - *start,
            _ => runs.push((at, PAGE)),
        }
    }
    if let Some((start, run)) = runs.last_mut() {
        *run = (*run).min(len - *start);
    }
    runs
}

/// Puts this program's reads behind everyone else's. Reading ahead must only use the card
/// when nothing is waiting for it: udev's many small reads were each queuing behind a large
/// one of ours, and it finished later than with no reading ahead at all.
#[cfg(target_os = "linux")]
fn stand_back() {
    const WHO_PROCESS: libc::c_int = 1;
    const CLASS_IDLE: libc::c_int = 3 << 13;
    // SAFETY: a plain system call on this process, with no pointers.
    unsafe { libc::syscall(libc::SYS_ioprio_set, WHO_PROCESS, 0, CLASS_IDLE) };
}

#[cfg(not(target_os = "linux"))]
fn stand_back() {}

/// Mounts the copies under `root` over the files they are copies of: what a shell loop of
/// stat and mount would do, without starting two programs a file.
#[cfg(target_os = "linux")]
fn cover(root: &str, list: &str) -> Result<(), String> {
    use std::ffi::CString;
    let lines = BufReader::new(File::open(list).map_err(|e| format!("{list}: {e}"))?);
    for line in lines.lines().map_while(Result::ok) {
        let mut parts = line.splitn(3, ' ');
        let (Some(size), Some(date), Some(path)) = (parts.next(), parts.next(), parts.next()) else { continue };
        let Ok(meta) = fs::metadata(path) else { continue };
        if size.parse() != Ok(meta.len()) || date.parse() != Ok(meta.mtime()) {
            eprintln!("dsboot-readahead: {path} has changed; not covered");
            continue;
        }
        let (Ok(from), Ok(to)) = (CString::new(format!("{root}{path}")), CString::new(path)) else { continue };
        // SAFETY: both strings are NUL-terminated and outlive the call; a bind mount takes no
        // filesystem type or data.
        let done = unsafe { libc::mount(from.as_ptr(), to.as_ptr(), std::ptr::null(), libc::MS_BIND, std::ptr::null()) };
        if done != 0 {
            eprintln!("dsboot-readahead: {path}: {}", std::io::Error::last_os_error());
        }
    }
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn cover(_root: &str, _list: &str) -> Result<(), String> {
    Err("cover works on Linux only".to_owned())
}

fn play(list: &str) -> Result<(), String> {
    let lines = BufReader::new(File::open(list).map_err(|e| format!("{list}: {e}"))?);
    let mut buf = vec![0u8; STEP as usize];
    let mut open: Option<(String, File)> = None;
    for line in lines.lines().map_while(Result::ok) {
        let mut parts = line.splitn(3, '\t');
        let (Some(start), Some(len), Some(path)) = (parts.next(), parts.next(), parts.next()) else { continue };
        let (Ok(mut at), Ok(len)) = (start.parse::<u64>(), len.parse::<u64>()) else { continue };
        if open.as_ref().is_none_or(|(p, _)| p != path) {
            // A file that is not there yet, or has gone, is passed over.
            open = File::open(path).ok().map(|f| (path.to_owned(), f));
        }
        let Some((_, file)) = &open else { continue };
        let end = at + len;
        while at < end {
            let want = (end - at).min(STEP) as usize;
            match file.read_at(&mut buf[..want], at) {
                Ok(n) if n > 0 => at += n as u64,
                _ => break,
            }
        }
    }
    Ok(())
}
