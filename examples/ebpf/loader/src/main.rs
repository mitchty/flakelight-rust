use anyhow::Context as _;
use aya::programs::KProbe;
use clap::Parser;
use log::{info, warn};

// For embedded builds embed the ebpf object code into the final binary
// directly. This variant can still load external object code too.
#[cfg(feature = "embedded")]
static EMBEDDED_KPROBE_OBJECT: &[u8] = include_bytes!(env!("KPROBE_EBPF_OBJECT"));

#[derive(Debug, Parser)]
struct Opt {
    /// Full path to the compiled eBPF object to load.
    #[clap(long)]
    bpf_object: Option<String>,

    /// Kernel function symbol to hook.
    ///
    /// Defaults just `sys_execve` for no real reason.
    #[clap(long, default_value = "sys_execve")]
    symbol: String,
}

#[cfg(feature = "embedded")]
fn load_ebpf(bpf_object: Option<String>) -> anyhow::Result<aya::Ebpf> {
    match bpf_object {
        Some(path) => aya::Ebpf::load_file(&path)
            .with_context(|| format!("failed to load eBPF object at {path}")),
        None => aya::Ebpf::load(EMBEDDED_KPROBE_OBJECT).context("failed to load embedded eBPF object"),
    }
}

#[cfg(not(feature = "embedded"))]
fn load_ebpf(bpf_object: Option<String>) -> anyhow::Result<aya::Ebpf> {
    let path = bpf_object
        .context("--bpf-object is a required arg rebuild with `embedded` feature to embed a default eBPF object code")?;
    aya::Ebpf::load_file(&path).with_context(|| format!("failed to load eBPF object at {path}"))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    env_logger::init();
    let opt = Opt::parse();

    // Bump the memlock rlimit for this to load, required on pre-5.11
    // kernels for user BPF maps apparently.
    let rlim = libc::rlimit {
        rlim_cur: libc::RLIM_INFINITY,
        rlim_max: libc::RLIM_INFINITY,
    };

    let ret = unsafe { libc::setrlimit(libc::RLIMIT_MEMLOCK, &rlim) };
    if ret != 0 {
        warn!("failed to remove memlock rlimit, will try to continue regardless");
    }

    let mut ebpf = load_ebpf(opt.bpf_object)?;

    // The `Logger` needs to be kept in scope for the duration of the aya
    // ebpf run to work. Bit janky but normal as per the docs.
    match aya_log::EbpfLogger::init(&mut ebpf) {
        Ok(logger) => {
            let mut logger =
                tokio::io::unix::AsyncFd::with_interest(logger, tokio::io::Interest::READABLE)
                    .context("failed to register eBPF logger fd with tokio")?;
            tokio::task::spawn(async move {
                loop {
                    let Ok(mut guard) = logger.readable_mut().await else {
                        break;
                    };
                    guard.get_inner_mut().flush();
                    guard.clear_ready();
                }
            });
        }
        Err(e) => {
            // Not fatal: the hook still runs, we just won't see its log
            // lines for some reason I've not hit yet.
            warn!("failed to initialize eBPF logger: {e}");
        }
    }

    // Some trivial validation of the eBPF object loaded.
    let program: &mut KProbe = ebpf
        .program_mut("generic_kprobe")
        .context("`generic_kprobe` program not found in the loaded eBPF object")?
        .try_into()?;
    program.load()?;
    program
        .attach(&opt.symbol, 0)
        .with_context(|| format!("failed to attach kprobe to `{}`", opt.symbol))?;

    info!("attached kprobe to `{}`, ctrl-c to exit", opt.symbol);
    tokio::signal::ctrl_c().await?;
    info!("exiting");

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_symbol_is_sys_execve() {
        let opt = Opt::parse_from(["loader", "--bpf-object", "/tmp/kprobe.o"]);
        assert_eq!(opt.symbol, "sys_execve");
    }

    #[test]
    fn bpf_object_is_optional() {
        let opt = Opt::parse_from(["loader"]);
        assert_eq!(opt.bpf_object, None);
    }
}
