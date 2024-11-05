echo 0 > /proc/sys/kernel/randomize_va_space
exec python3 ./bench_runner.py "$@"