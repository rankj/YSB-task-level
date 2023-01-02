# [TLC Evaluation of Distributed Stream Processing Systems  ]
The Task Level CPU Efficiency Evaluation for Distributed Stream Processing Systems


### Background
This repository provides a CPU monitoring concept and benchmark integration to allow fine-grained CPU evaluations of Distributed Stream Processing Systems (DSPS).
While traditional performance analysis of DSPS focuses on latency and throughput to evaluate the performance of a system, our goal is to evaluate CPU efficiency, which becomes increasingly important in the context of energy savings, restricted resource environments (e.g. IoT edge computing) or cost savings in pay-as-you-go cloud deployments.
A special feature of this performance evaluation approach is that we do not measure CPU performance on process-level but for each streaming task individually. This allows detailed insights into the actual performance behavior. This way you can monitor how different factors affect the performance of individual parts of the code.

The monitoring uses stacktrace sampling based on the extended Berkley Package Filter (eBPF) in combination with performance monitoring counters (PMC).
The performance monitoring can be integrated into any streaming system. For demonstration purpose we provide an integration with an extended Version of the Yahoo Streaming Benchmark

### Benchmark Integration
Our benchmark integration supports the following engines:
- Apache Flink
- Apache Spark Structured Streaming
- Apache Spark Structured Streaming Continous Processing Mode

For other engines we do not provide a YSB.jar right now. However, you may use the monitoring capabilities for other DSPS as well.

### Instructions for Running the Example Benchmark (Video)

<div align="left">
      <a href="https://youtu.be/U523a6GnTXM">
         <img src="https://github.com/rankj/YSB-task-level/blob/master/video-thumbnail.png" style="width:100%;">
      </a>
</div>


Stay tuned for further updates on this project!

### Related Work
Yahoo Streaming Benchmark: https://github.com/yahoo/streaming-benchmarks
Perf-map-agent: https://github.com/jvm-profiling-tools/perf-map-agent
Bpftrace: https://github.com/iovisor/bpftrace


