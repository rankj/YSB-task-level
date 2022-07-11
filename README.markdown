# [TLC Streaming Benchmark ]
The Task Level CPU Efficiency Benchmark for Distributed Stream Processing Systems


### Background
This repository provides a benchmark that allows fine-grained CPU evaluations of distributed Stream Processing Systems.
While traditional benchmarks focus on latency and throughput to evaluate the performance of a system our goal is to evaluate CPU efficiency, which becomes increasingly important in the context of energy efficiency or in restricted resource environments such as IoT edged computing.
A special feature of this benchmark is that we do not measure CPU performance for the entire application but for each streaming task individually. This increases the transparency of the benchmark results since the entire application no longer has to be generalizable.
It also allows us to observe how different factors affect the performance of each individual task, which can better explain the overall performance behavior.
We support the following engines:
- Apache Flink
- Apache Spark Structured Streaming
- Apache Spark Structured Streaming Continous Processing Mode

This project is based on the Yahoo Streaming Benchmark (YSB) and resembles the same pipeline. However, we extended the original implementation. Most importantly we included a monitoring toolchain based on bpftrace and the perf-map-agent.

### Instructions

<div align="left">
      <a href="https://youtu.be/mWEiSvDezoI">
         <img src="https://i9.ytimg.com/vi/mWEiSvDezoI/mqdefault.jpg?v=62cb6981&sqp=CNzbrZYG&rs=AOn4CLDlme5b9jKgz8hLmI6UXjrBX6mM3Q" style="width:100%;">
      </a>
</div>


### Related Work
Yahoo Streaming Benchmark: https://github.com/yahoo/streaming-benchmarks
Perf-map-agent: https://github.com/jvm-profiling-tools/perf-map-agent
Bpftrace: https://github.com/iovisor/bpftrace


