# 打波形
$NOOP_HOME/build/emu \
--diff $NOOP_HOME/ready-to-run/riscv64-nemu-interpreter-so \
-W 20000000 -I 40000000 \# 出错的片段
-i <workload> \
--dump-wave  -b <开始时钟> -e <结束时钟> --wave-path <波形文件存放地址> \
--dump-db --dump-select-db "lifetime" --db-path <db数据库文件路径> \
> simulator_out_20m_20m.txt 2> simulator_err_20m_20m.txt

# 不打波形
$NOOP_HOME/build/emu \
--enable-fork \
--diff $NOOP_HOME/ready-to-run/riscv64-nemu-interpreter-so \
-W 20000000 -I 40000000 \
-i <workload> \
--dump-db --dump-select-db "lifetime" --db-path <db数据库文件路径> \
> simulator_out_20m_20m.txt 2> simulator_err_20m_20m.txt