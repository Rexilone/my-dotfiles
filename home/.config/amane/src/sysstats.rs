// загрузка и температуры CPU/GPU, память (SysStats.qml); опрос идёт, пока кто-то смотрит

use std::sync::Mutex;
use std::time::{Duration, Instant};

use amane::Service;

#[derive(Default, Clone)]
pub struct SysStats {
    pub cpu: f32,
    pub cpu_temp: f32,
    pub gpu: f32,
    pub gpu_temp: f32,
    pub vram_used: f64,
    pub vram_total: f64,
    pub ram_used: f64, // КиБ
    pub ram_total: f64,
    prev: Option<(f64, f64)>,
}

static NEED: Mutex<Option<Instant>> = Mutex::new(None);

pub fn need() {
    *NEED.lock().unwrap() = Some(Instant::now());
}

pub fn gb(kib: f64) -> String {
    format!("{:.1}", kib / 1024.0 / 1024.0)
}

const SCRIPT: &str = r#"for h in /sys/class/hwmon/hwmon*; do
    case "$(cat "$h/name")" in
        k10temp|coretemp|zenpower) [ -z "$ct" ] && ct="$h/temp1_input" ;;
        amdgpu) [ -z "$gh" ] && gh="$h" ;;
    esac
done
gd=$(readlink -f "$gh/device" 2>/dev/null)
while :; do
    printf '%s|%s|%s|%s|%s %s|%s\n' \
        "$(head -n1 /proc/stat)" \
        "$(cat "$ct" 2>/dev/null || echo 0)" \
        "$(cat "$gd/gpu_busy_percent" 2>/dev/null || echo 0)" \
        "$(cat "$gh/temp1_input" 2>/dev/null || echo 0)" \
        "$(cat "$gd/mem_info_vram_used" 2>/dev/null || echo 0)" \
        "$(cat "$gd/mem_info_vram_total" 2>/dev/null || echo 0)" \
        "$(awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{print t, a}' /proc/meminfo)"
    sleep 1.5
done"#;

pub fn parse(s: &mut SysStats, line: &str) {
    let p: Vec<&str> = line.split('|').collect();
    if p.len() < 6 {
        return;
    }
    let n: Vec<f64> = p[0].split_whitespace().skip(1).filter_map(|x| x.parse().ok()).collect();
    if n.len() >= 5 {
        let idle = n[3] + n[4];
        let total: f64 = n.iter().take(8).sum();
        if let Some((pi, pt)) = s.prev {
            let dt = total - pt;
            if dt > 0.0 {
                s.cpu = (1.0 - (idle - pi) / dt) as f32;
            }
        }
        s.prev = Some((idle, total));
    }
    let num = |x: &str| x.trim().parse::<f64>().unwrap_or(0.0);
    s.cpu_temp = (num(p[1]) / 1000.0) as f32;
    s.gpu = (num(p[2]) / 100.0) as f32;
    s.gpu_temp = (num(p[3]) / 1000.0) as f32;
    let v: Vec<f64> = p[4].split_whitespace().map(num).collect();
    s.vram_used = v.first().copied().unwrap_or(0.0);
    s.vram_total = v.get(1).copied().unwrap_or(0.0);
    let m: Vec<f64> = p[5].split_whitespace().map(num).collect();
    s.ram_total = m.first().copied().unwrap_or(0.0);
    s.ram_used = s.ram_total - m.get(1).copied().unwrap_or(0.0);
}

impl Service for SysStats {
    fn new() -> Self {
        SysStats::default()
    }

    fn listen() {
        use std::io::BufRead;
        loop {
            let on = || NEED.lock().unwrap().is_some_and(|t| t.elapsed() < Duration::from_secs(3));
            if !on() {
                std::thread::sleep(Duration::from_millis(300));
                continue;
            }
            let Ok(mut child) = std::process::Command::new("sh").arg("-c").arg(SCRIPT).stdout(std::process::Stdio::piped()).spawn() else {
                std::thread::sleep(Duration::from_secs(5));
                continue;
            };
            let out = child.stdout.take().unwrap();
            for line in std::io::BufReader::new(out).lines() {
                let Ok(line) = line else { break };
                let mut s = SysStats::read().clone();
                parse(&mut s, &line);
                *SysStats::write() = s;
                if !on() {
                    break;
                }
            }
            let _ = child.kill();
            let _ = child.wait();
            SysStats::write().prev = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_line() {
        let mut s = SysStats::default();
        parse(&mut s, "cpu  100 0 100 700 100 0 0 0 0 0|45000|30|50000|1073741824 8589934592|16000000 12000000");
        parse(&mut s, "cpu  200 0 200 1300 100 0 0 0 0 0|45000|30|50000|1073741824 8589934592|16000000 12000000");
        assert!((s.cpu - 0.25).abs() < 1e-4);
        assert_eq!(s.cpu_temp, 45.0);
        assert!((s.gpu - 0.3).abs() < 1e-6);
        assert_eq!(s.ram_used, 4000000.0);
        assert_eq!(gb(s.ram_total), "15.3");
    }
}
