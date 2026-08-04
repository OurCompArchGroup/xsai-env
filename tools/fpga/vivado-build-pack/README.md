# Vivado CPU-FPGA Build Pack

这个目录是从原工程中抽出来的 Vivado 自动建工程/综合包，已包含脚本需要的模板 wrapper、BD Tcl 和约束文件，不需要再依赖原始 6GB Vivado 工程目录。

## 它做什么

`build_vivado_project.sh` 会：

1. 读取你提供的 RTL 目录（递归收集 `.v/.sv/.vh/.svh`）。
2. 基于内置模板创建 Vivado 工程，器件为 `xcvu19p-fsva3824-2-e`。
3. 导入 PCIe/DDR BD、wrapper、约束和你的 RTL。
4. 默认运行到 `synth_1`；也可以继续跑 implementation 或 bitstream。
5. 在输出目录生成 Vivado project、日志、`build_summary.txt` 和 `artifacts/`。

## 使用方法

先确保当前 shell 里能直接运行 `vivado`，例如已 source Vivado 环境：

```bash
source /path/to/Vivado/settings64.sh
```

然后运行：

```bash
./build_vivado_project.sh --rtl /path/to/rtl_dir --out /path/to/output_dir
```

常用选项：

```bash
./build_vivado_project.sh \
  --rtl /path/to/rtl_dir \
  --out /path/to/output_dir \
  --name cpu_fpga_build \
  --jobs 8 \
  --run-to synth
```

`--run-to` 可选：

- `project`：只创建/打开工程。
- `synth`：运行综合，默认值。
- `impl`：运行综合和实现。
- `bitstream`：运行到 bitstream。

如果输出目录中同名 Vivado 工程已存在，脚本会打开该工程并继续/恢复指定阶段。

## 目录说明

- `build_vivado_project.sh`：推荐入口，自动使用本包内置模板。
- `scripts/`：实际 Bash/Tcl 实现。
- `kmh_mini_ai_raw_bigddr8g_0522/`：精简后的 Vivado 模板资源。

## 注意

- 本包不包含 Vivado 本身；运行机器仍需安装并授权 Vivado。
- 输入 RTL 目录至少需要包含一个 `.v/.sv/.vh/.svh` 文件。
- 默认目标顶层为 `pcie_part_gating_wrapper`，用户逻辑通过模板中的 `XSTop_wrapper_dse` 连接。
